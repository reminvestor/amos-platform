# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_work_items
#
#  id                       :bigint           not null, primary key
#  entity_id                :bigint           not null
#  user_id                  :bigint           not null
#  agent_plugin_id          :bigint
#  scheduled_task_run_id    :bigint
#  agent_plugin_execution_id :bigint
#  scout_conversation_id    :bigint
#  work_type                :string           not null
#  title                    :string           not null
#  summary                  :text
#  details                  :text
#  asset_type               :string
#  asset_id                 :bigint
#  asset_data               :jsonb            default({})
#  read                     :boolean          default(FALSE)
#  read_at                  :datetime
#  starred                  :boolean          default(FALSE)
#  archived                 :boolean          default(FALSE)
#  archived_at              :datetime
#  priority                 :string           default("normal")
#  requires_action          :boolean          default(FALSE)
#  action_type              :string
#  action_due_at            :datetime
#  metadata                 :jsonb            default({})
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
class AgentWorkItem < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :agent_plugin, optional: true
  belongs_to :scheduled_task_run, optional: true
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :scout_conversation, optional: true
  
  has_many :user_notifications, dependent: :nullify
  has_many :saved_visualizations, dependent: :nullify
  
  # Validations
  validates :work_type, presence: true, inclusion: { 
    in: %w[
      task_completed scheduled_task_completed asset_created report_generated 
      email_sent email_drafted research_completed integration_synced
      agent_created tool_created landing_page_created campaign_created
      analysis_completed visualization_created action_required info_retrieved
    ]
  }
  validates :title, presence: true
  validates :priority, presence: true, inclusion: { in: %w[low normal high urgent] }
  
  # Scopes
  scope :unread, -> { where(read: false) }
  scope :read, -> { where(read: true) }
  scope :starred, -> { where(starred: true) }
  scope :not_archived, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :requiring_action, -> { where(requires_action: true) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where('created_at >= ?', Time.current.beginning_of_day) }
  scope :this_week, -> { where('created_at >= ?', 1.week.ago) }
  
  # Callbacks
  before_create :set_defaults
  after_create :broadcast_new_item
  after_create :create_notification_if_needed
  
  # Work type configurations
  WORK_TYPES = {
    'task_completed' => { icon: '✅', category: 'tasks' },
    'scheduled_task_completed' => { icon: '⏰', category: 'scheduled' },
    'asset_created' => { icon: '🏗️', category: 'assets' },
    'report_generated' => { icon: '📊', category: 'reports' },
    'email_sent' => { icon: '📧', category: 'email' },
    'email_drafted' => { icon: '✉️', category: 'email' },
    'research_completed' => { icon: '🔍', category: 'research' },
    'integration_synced' => { icon: '🔄', category: 'integrations' },
    'agent_created' => { icon: '🤖', category: 'agents' },
    'tool_created' => { icon: '🔧', category: 'tools' },
    'landing_page_created' => { icon: '📄', category: 'pages' },
    'campaign_created' => { icon: '📣', category: 'campaigns' },
    'analysis_completed' => { icon: '📈', category: 'analytics' },
    'visualization_created' => { icon: '📉', category: 'visualizations' },
    'action_required' => { icon: '⚠️', category: 'actions' },
    'info_retrieved' => { icon: '🌤️', category: 'info' }
  }.freeze
  
  # Instance methods
  def mark_as_read!
    return if read?
    update!(read: true, read_at: Time.current)
  end
  
  def mark_as_unread!
    update!(read: false, read_at: nil)
  end
  
  def toggle_starred!
    update!(starred: !starred?)
  end
  
  def archive!
    update!(archived: true, archived_at: Time.current)
  end
  
  def unarchive!
    update!(archived: false, archived_at: nil)
  end
  
  def complete_action!
    update!(requires_action: false)
  end
  
  def icon
    WORK_TYPES.dig(work_type, :icon) || '📋'
  end
  
  def category
    WORK_TYPES.dig(work_type, :category) || 'general'
  end
  
  def asset
    return nil unless asset_type.present? && asset_id.present?
    
    begin
      asset_type.constantize.find_by(id: asset_id)
    rescue NameError
      nil
    end
  end
  
  def agent_name
    agent_plugin&.name || 'Scout'
  end
  
  def time_ago
    time_ago_in_words(created_at)
  end
  
  # Class methods
  def self.inbox_for(user, entity)
    for_user(user)
      .for_entity(entity)
      .not_archived
      .recent
  end
  
  def self.unread_count_for(user, entity)
    for_user(user)
      .for_entity(entity)
      .not_archived
      .unread
      .count
  end
  
  def self.action_required_count_for(user, entity)
    for_user(user)
      .for_entity(entity)
      .not_archived
      .requiring_action
      .count
  end
  
  private
  
  def set_defaults
    self.priority ||= 'normal'
  end
  
  def broadcast_new_item
    # Broadcast to user's channel for real-time updates
    ActionCable.server.broadcast(
      "user_#{user_id}_work_items",
      {
        type: 'new_work_item',
        work_item: {
          id: id,
          work_type: work_type,
          title: title,
          summary: summary,
          icon: icon,
          priority: priority,
          requires_action: requires_action,
          created_at: created_at.iso8601
        }
      }
    )
  end
  
  def create_notification_if_needed
    return unless requires_action? || priority.in?(%w[high urgent])
    
    UserNotification.create!(
      entity: entity,
      user: user,
      agent_work_item: self,
      notification_type: requires_action? ? 'action_required' : 'work_completed',
      title: title,
      body: summary,
      icon: icon,
      channel: 'in_app',
      priority: priority,
      action_url: "/scout?view=inbox&item_id=#{id}",
      action_type: action_type || 'view'
    )
  end
  
  def time_ago_in_words(time)
    seconds = (Time.current - time).to_i
    
    case seconds
    when 0..59 then "just now"
    when 60..3599 then "#{seconds / 60}m ago"
    when 3600..86399 then "#{seconds / 3600}h ago"
    when 86400..604799 then "#{seconds / 86400}d ago"
    else time.strftime('%b %d')
    end
  end
end

