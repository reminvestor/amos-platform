# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_scratchpads
#
#  id                     :bigint           not null, primary key
#  entity_id              :bigint           not null
#  user_id                :bigint           not null
#  session_id             :string           not null
#  key                    :string           not null
#  data                   :jsonb            default({})
#  data_type              :string
#  description            :text
#  source_agent_plugin_id :bigint
#  source_execution_id    :bigint
#  expires_at             :datetime         not null
#  metadata               :jsonb            default({})
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Agent Scratchpad - Temporary working memory for agents within a session
#
# This enables:
# 1. Multi-agent data handoff (Web Research saves data → Document Export reads it)
# 2. Single-agent multi-step tasks (save intermediate results)
# 3. Resumable tasks (preserve working state)
#
# Data is session-scoped and auto-expires after 24 hours.
#
class AgentScratchpad < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :user
  belongs_to :source_agent_plugin, class_name: 'AgentPlugin', optional: true
  belongs_to :source_execution, class_name: 'AgentPluginExecution', optional: true

  # Validations
  validates :session_id, presence: true
  validates :key, presence: true
  validates :key, uniqueness: { scope: :session_id, message: 'already exists in this session' }
  validates :expires_at, presence: true
  validates :data_type, inclusion: { 
    in: %w[research_data intermediate_result handoff_data working_state export_data raw_data],
    allow_blank: true 
  }

  # Callbacks
  before_validation :set_default_expiry, on: :create

  # Scopes
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  scope :by_key, ->(key) { where(key: key) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(data_type: type) }

  # Class methods for easy access
  class << self
    # Save data to scratchpad (upsert - update if key exists)
    def save_data(session_id:, key:, data:, user:, entity:, description: nil, data_type: nil, agent: nil, execution: nil, ttl_hours: 24)
      entry = find_or_initialize_by(session_id: session_id, key: key)
      
      entry.assign_attributes(
        data: data,
        description: description,
        data_type: data_type,
        user: user,
        entity: entity,
        source_agent_plugin: agent,
        source_execution: execution,
        expires_at: ttl_hours.hours.from_now,
        metadata: entry.metadata.merge(
          updated_count: (entry.metadata['updated_count'] || 0) + 1,
          last_updated_by: agent&.name || 'system'
        )
      )
      
      entry.save!
      entry
    end

    # Read data from scratchpad
    def read_data(session_id:, key:)
      active.for_session(session_id).by_key(key).first
    end

    # List all entries for a session
    def list_for_session(session_id)
      active.for_session(session_id).recent
    end

    # Delete expired entries (for cleanup job)
    def cleanup_expired!
      count = expired.delete_all
      Rails.logger.info "[AgentScratchpad] Cleaned up #{count} expired entries" if count > 0
      count
    end

    # Get all data for a session as a hash
    def session_data(session_id)
      active.for_session(session_id).each_with_object({}) do |entry, hash|
        hash[entry.key] = {
          data: entry.data,
          description: entry.description,
          data_type: entry.data_type,
          created_at: entry.created_at,
          source_agent: entry.source_agent_plugin&.name
        }
      end
    end
  end

  # Instance methods
  def expired?
    expires_at <= Time.current
  end

  def time_until_expiry
    return 0 if expired?
    (expires_at - Time.current).to_i
  end

  def extend_expiry!(hours = 24)
    update!(expires_at: hours.hours.from_now)
  end

  def data_size
    data.to_json.bytesize
  end

  def data_row_count
    return 0 unless data.is_a?(Array)
    data.length
  end

  def summary
    {
      key: key,
      description: description,
      data_type: data_type,
      row_count: data_row_count,
      size_bytes: data_size,
      source_agent: source_agent_plugin&.name,
      created_at: created_at,
      expires_at: expires_at
    }
  end

  private

  def set_default_expiry
    self.expires_at ||= 24.hours.from_now
  end
end

