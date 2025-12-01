# frozen_string_literal: true

# == Schema Information
#
# Table name: dynamic_contents
#
#  id                        :bigint           not null, primary key
#  entity_id                 :bigint           not null
#  user_id                   :bigint           not null
#  scout_conversation_id     :bigint
#  agent_plugin_execution_id :bigint
#  scheduled_task_run_id     :bigint
#  content_type              :string           not null
#  title                     :string           not null
#  subtitle                  :text
#  html_content              :text             not null
#  data_snapshot             :jsonb            default({})
#  generation_context        :jsonb            default({})
#  session_id                :string
#  message_index             :integer
#  category                  :string
#  tags                      :jsonb            default([])
#  metadata                  :jsonb            default({})
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
class DynamicContent < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :scout_conversation, optional: true
  belongs_to :agent_plugin_execution, optional: true
  belongs_to :scheduled_task_run, optional: true
  
  has_many :saved_visualizations, dependent: :nullify
  
  # Validations
  validates :content_type, presence: true, inclusion: { 
    in: %w[visualization report dashboard analysis table chart comparison custom]
  }
  validates :title, presence: true
  validates :html_content, presence: true
  
  # Scopes
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :by_type, ->(type) { where(content_type: type) }
  scope :by_category, ->(category) { where(category: category) }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where('created_at >= ?', Time.current.beginning_of_day) }
  scope :this_week, -> { where('created_at >= ?', 1.week.ago) }
  
  # Content type configurations
  CONTENT_TYPES = {
    'visualization' => { icon: '📊', color: 'primary' },
    'report' => { icon: '📄', color: 'info' },
    'dashboard' => { icon: '📈', color: 'success' },
    'analysis' => { icon: '🔍', color: 'warning' },
    'table' => { icon: '📋', color: 'secondary' },
    'chart' => { icon: '📉', color: 'primary' },
    'comparison' => { icon: '⚖️', color: 'info' },
    'custom' => { icon: '✨', color: 'dark' }
  }.freeze
  
  # Class method to create from canvas_data
  def self.create_from_canvas(user:, entity:, canvas_data:, session_id: nil, context: {})
    title = canvas_data['title'] || canvas_data[:title] || 'Untitled'
    subtitle = canvas_data['subtitle'] || canvas_data[:subtitle]
    html_content = canvas_data['html_content'] || canvas_data[:html_content]
    
    return nil if html_content.blank?
    
    content_type = determine_content_type(title, canvas_data)
    
    create!(
      entity: entity,
      user: user,
      content_type: content_type,
      title: title,
      subtitle: subtitle,
      html_content: html_content,
      data_snapshot: canvas_data['data'] || canvas_data[:data] || {},
      session_id: session_id,
      generation_context: context,
      category: determine_category(title, content_type),
      metadata: {
        created_from: 'canvas',
        canvas_type: 'dynamic_canvas'
      }
    )
  end
  
  def self.determine_content_type(title, canvas_data)
    title_lower = title.to_s.downcase
    
    case title_lower
    when /dashboard/i then 'dashboard'
    when /report/i then 'report'
    when /comparison|compare|vs/i then 'comparison'
    when /chart|graph/i then 'chart'
    when /table|list/i then 'table'
    when /analysis|analyze/i then 'analysis'
    else 'visualization'
    end
  end
  
  def self.determine_category(title, content_type)
    title_lower = title.to_s.downcase
    
    case title_lower
    when /sales|pipeline|deal|revenue/i then 'sales'
    when /marketing|campaign|email|lead/i then 'marketing'
    when /finance|budget|cost|expense/i then 'finance'
    when /customer|support|ticket/i then 'support'
    when /hr|employee|hiring/i then 'hr'
    when /operation|process|workflow/i then 'operations'
    else 'general'
    end
  end
  
  # Instance methods
  def icon
    CONTENT_TYPES.dig(content_type, :icon) || '📊'
  end
  
  def color_class
    CONTENT_TYPES.dig(content_type, :color) || 'secondary'
  end
  
  def to_canvas_data
    {
      'title' => title,
      'subtitle' => subtitle,
      'html_content' => html_content,
      'data' => data_snapshot
    }
  end
  
  # Save as a reusable visualization
  def save_as_visualization!(name: nil, description: nil)
    SavedVisualization.create!(
      entity: entity,
      user: user,
      dynamic_content: self,
      scout_conversation_id: scout_conversation_id,
      agent_plugin_execution_id: agent_plugin_execution_id,
      name: name || title,
      description: description || subtitle,
      visualization_type: content_type,
      source_type: 'dynamic_content',
      source_session_id: session_id,
      canvas_data_cache: to_canvas_data,
      category: category
    )
  end
  
  def time_ago
    seconds = (Time.current - created_at).to_i
    
    case seconds
    when 0..59 then "just now"
    when 60..3599 then "#{seconds / 60}m ago"
    when 3600..86399 then "#{seconds / 3600}h ago"
    when 86400..604799 then "#{seconds / 86400}d ago"
    else created_at.strftime('%b %d')
    end
  end
end

