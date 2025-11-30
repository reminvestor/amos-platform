# frozen_string_literal: true

# == Schema Information
#
# Table name: saved_visualizations
#
#  id                        :bigint           not null, primary key
#  entity_id                 :bigint           not null
#  user_id                   :bigint           not null
#  scout_message_id          :bigint
#  scout_conversation_id     :bigint
#  agent_work_item_id        :bigint
#  agent_plugin_execution_id :bigint
#  name                      :string           not null
#  description               :text
#  visualization_type        :string           not null
#  source_type               :string           not null
#  source_session_id         :string
#  source_message_index      :integer
#  html_content_cache        :text
#  canvas_data_cache         :jsonb            default({})
#  cache_expires_at          :datetime
#  original_prompt           :text
#  generation_config         :jsonb            default({})
#  auto_refresh              :boolean          default(FALSE)
#  refresh_schedule          :string
#  last_refreshed_at         :datetime
#  next_refresh_at           :datetime
#  category                  :string
#  tags                      :jsonb            default([])
#  pinned                    :boolean          default(FALSE)
#  shared                    :boolean          default(FALSE)
#  archived                  :boolean          default(FALSE)
#  metadata                  :jsonb            default({})
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
class SavedVisualization < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :dynamic_content, optional: true
  belongs_to :scout_message, optional: true
  belongs_to :scout_conversation, optional: true
  belongs_to :agent_work_item, optional: true
  belongs_to :agent_plugin_execution, optional: true
  
  # Validations
  validates :name, presence: true
  validates :visualization_type, presence: true, inclusion: { 
    in: %w[dashboard report comparison chart table custom analysis]
  }
  validates :source_type, presence: true, inclusion: { 
    in: %w[message_metadata artifact inline agent_execution dynamic_content]
  }
  
  # Scopes
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_user, ->(user) { where(user: user) }
  scope :shared_in_entity, ->(entity) { where(entity: entity, shared: true) }
  scope :pinned, -> { where(pinned: true) }
  scope :not_archived, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :needs_refresh, -> { where(auto_refresh: true).where('next_refresh_at <= ?', Time.current) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Callbacks
  before_save :update_cache_if_needed
  before_save :calculate_next_refresh, if: :auto_refresh_changed?
  
  # Get the actual visualization content
  def html_content
    # First try cache if valid
    if html_content_cache.present? && cache_valid?
      return html_content_cache
    end
    
    # Otherwise fetch from source
    content = fetch_from_source
    
    # Update cache
    if content.present?
      update_cache!(content)
    end
    
    content
  end
  
  def canvas_data
    # First try cache if valid
    if canvas_data_cache.present? && cache_valid?
      return canvas_data_cache
    end
    
    # Otherwise fetch from source
    data = fetch_canvas_data_from_source
    
    # Update cache
    if data.present?
      update_columns(
        canvas_data_cache: data,
        cache_expires_at: 1.hour.from_now
      )
    end
    
    data
  end
  
  def cache_valid?
    cache_expires_at.present? && cache_expires_at > Time.current
  end
  
  def refresh!
    content = regenerate_visualization
    if content.present?
      update!(
        html_content_cache: content[:html_content],
        canvas_data_cache: content[:canvas_data] || {},
        cache_expires_at: 1.day.from_now,
        last_refreshed_at: Time.current
      )
      calculate_next_refresh
      save!
    end
  end
  
  def toggle_pin!
    update!(pinned: !pinned?)
  end
  
  def toggle_share!
    update!(shared: !shared?)
  end
  
  def archive!
    update!(archived: true)
  end
  
  def unarchive!
    update!(archived: false)
  end
  
  # Class method to save a visualization from a canvas broadcast
  def self.save_from_canvas(user:, entity:, name:, canvas_data:, session_id: nil, message: nil, prompt: nil)
    create!(
      user: user,
      entity: entity,
      name: name,
      description: canvas_data['subtitle'] || canvas_data[:subtitle],
      visualization_type: determine_type(canvas_data),
      source_type: message.present? ? 'message_metadata' : 'inline',
      source_session_id: session_id,
      scout_message: message,
      html_content_cache: canvas_data['html_content'] || canvas_data[:html_content],
      canvas_data_cache: canvas_data,
      cache_expires_at: 1.day.from_now,
      original_prompt: prompt,
      generation_config: {
        saved_at: Time.current,
        canvas_type: 'dynamic_canvas'
      }
    )
  end
  
  def self.determine_type(canvas_data)
    title = (canvas_data['title'] || canvas_data[:title] || '').downcase
    
    case title
    when /dashboard/i then 'dashboard'
    when /report/i then 'report'
    when /comparison|compare|vs/i then 'comparison'
    when /chart|graph/i then 'chart'
    when /table|list/i then 'table'
    when /analysis|analyze/i then 'analysis'
    else 'custom'
    end
  end
  
  private
  
  def fetch_from_source
    case source_type
    when 'dynamic_content'
      dynamic_content&.html_content
    when 'message_metadata'
      fetch_from_message
    when 'artifact'
      fetch_from_artifact
    when 'agent_execution'
      fetch_from_agent_execution
    when 'inline'
      html_content_cache
    end
  end
  
  def fetch_canvas_data_from_source
    case source_type
    when 'dynamic_content'
      dynamic_content&.to_canvas_data || canvas_data_cache
    when 'message_metadata'
      message = scout_message || find_source_message
      message&.metadata&.dig('canvas_data') || canvas_data_cache
    when 'agent_execution'
      agent_plugin_execution&.output_result&.dig('canvas_data') || canvas_data_cache
    else
      canvas_data_cache
    end
  end
  
  def fetch_from_message
    message = scout_message || find_source_message
    return nil unless message
    
    # Check metadata for canvas_data
    canvas = message.metadata&.dig('canvas_data')
    canvas&.dig('html_content') || canvas&.dig(:html_content)
  end
  
  def fetch_from_artifact
    # If we have a reference to a pipeline artifact
    artifact_id = metadata&.dig('artifact_id')
    return nil unless artifact_id
    
    artifact = PipelineArtifact.find_by(id: artifact_id)
    artifact&.get_content
  end
  
  def fetch_from_agent_execution
    return nil unless agent_plugin_execution
    
    result = agent_plugin_execution.output_result
    result&.dig('canvas_data', 'html_content') || result&.dig(:canvas_data, :html_content)
  end
  
  def find_source_message
    return nil unless source_session_id.present?
    
    messages = ScoutMessage.where(session_id: source_session_id)
                          .where(role: 'assistant')
                          .order(created_at: :asc)
    
    if source_message_index.present?
      messages.offset(source_message_index).first
    else
      # Find the message with canvas_data in metadata
      messages.find { |m| m.metadata&.dig('canvas_data').present? }
    end
  end
  
  def regenerate_visualization
    return nil unless original_prompt.present?
    
    # TODO: Implement regeneration by re-running the original prompt
    # This would involve calling Scout with the original prompt
    # and capturing the new canvas_data
    Rails.logger.info "Regeneration not yet implemented for visualization #{id}"
    nil
  end
  
  def update_cache!(content)
    update_columns(
      html_content_cache: content,
      cache_expires_at: 1.hour.from_now
    )
  end
  
  def update_cache_if_needed
    # If we have source references but no cache, try to populate
    if html_content_cache.blank? && source_type != 'inline'
      content = fetch_from_source
      if content.present?
        self.html_content_cache = content
        self.cache_expires_at = 1.hour.from_now
      end
    end
  end
  
  def calculate_next_refresh
    return unless auto_refresh? && refresh_schedule.present?
    
    begin
      cron = Fugit::Cron.parse(refresh_schedule)
      self.next_refresh_at = cron.next_time.to_t
    rescue => e
      Rails.logger.error "Failed to parse refresh schedule '#{refresh_schedule}': #{e.message}"
    end
  end
end

