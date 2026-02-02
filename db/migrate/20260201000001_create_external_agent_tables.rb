# frozen_string_literal: true

# External Agent Protocol (EAP) - Database Schema
#
# Enables AI agents from external platforms (OpenClaw, custom builds)
# to register, discover bounties, execute work, and earn tokens.
#
class CreateExternalAgentTables < ActiveRecord::Migration[8.0]
  def change
    # Main registration table for external agents
    create_table :external_agent_registrations do |t|
      # Relationships
      t.references :entity, null: false, foreign_key: true
      t.references :operator, null: false, foreign_key: { to_table: :users }

      # Agent identity
      t.string :agent_identifier, null: false  # Unique ID from agent platform
      t.string :agent_name, null: false
      t.string :agent_platform, null: false, default: 'openclaw'  # openclaw, custom, etc.
      
      # Authentication
      t.string :api_key, null: false  # Unique API key for this agent
      t.string :api_key_prefix, null: false  # First 8 chars for lookup

      # Capabilities and permissions
      t.jsonb :capabilities, null: false, default: {}  # What the agent can do
      t.string :allowed_bounty_types, array: true, default: []  # Approved bounty types
      t.string :allowed_tools, array: true, default: []  # Approved tools
      
      # Status and trust
      t.string :status, null: false, default: 'pending'  # pending, active, suspended, revoked
      t.decimal :reputation_score, precision: 5, scale: 2, default: 50.0
      t.integer :trust_level, default: 1  # 1-5, unlocks more capabilities
      
      # Limits
      t.integer :daily_bounty_limit, default: 3
      t.integer :max_concurrent_bounties, default: 1
      t.integer :tool_calls_per_bounty, default: 50
      
      # Statistics
      t.integer :total_bounties_claimed, default: 0
      t.integer :total_bounties_completed, default: 0
      t.integer :total_bounties_rejected, default: 0
      t.decimal :total_tokens_earned, precision: 18, scale: 4, default: 0
      
      # Metadata
      t.jsonb :metadata, default: {}  # Platform-specific info
      t.datetime :last_active_at
      t.datetime :suspended_at
      t.string :suspension_reason

      t.timestamps
    end

    # Indexes for external_agent_registrations
    add_index :external_agent_registrations, :agent_identifier, unique: true
    add_index :external_agent_registrations, :api_key, unique: true
    add_index :external_agent_registrations, :api_key_prefix
    add_index :external_agent_registrations, [:entity_id, :status]
    add_index :external_agent_registrations, [:operator_id, :status]
    add_index :external_agent_registrations, :agent_platform
    add_index :external_agent_registrations, :reputation_score
    add_index :external_agent_registrations, :trust_level

    # Execution tracking - each bounty claim creates an execution
    create_table :external_agent_executions do |t|
      t.references :external_agent_registration, null: false, foreign_key: true
      t.references :bounty, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      # Status
      t.string :status, null: false, default: 'in_progress'  # in_progress, submitted, approved, rejected, expired, cancelled

      # Work tracking
      t.jsonb :tools_used, default: []  # Array of {tool_name, args, result, timestamp}
      t.integer :tool_calls_count, default: 0
      t.text :work_log  # Agent's narrative of what they did
      t.jsonb :submission_data, default: {}  # Final work submission
      
      # Review
      t.jsonb :review_result, default: {}  # AI reviewer's assessment
      t.decimal :quality_score, precision: 5, scale: 2  # 0-100 quality rating
      t.text :review_notes
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true

      # Timing
      t.datetime :started_at
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.datetime :expires_at  # When claim expires if not submitted
      
      # Tokens awarded (if approved)
      t.decimal :tokens_awarded, precision: 18, scale: 4

      t.timestamps
    end

    # Indexes for external_agent_executions
    add_index :external_agent_executions, :status
    add_index :external_agent_executions, [:external_agent_registration_id, :status], name: 'idx_ext_agent_exec_agent_status'
    add_index :external_agent_executions, [:bounty_id, :status]
    add_index :external_agent_executions, :expires_at

    # Tool call audit log - detailed record of every tool call
    create_table :external_agent_tool_calls do |t|
      t.references :external_agent_execution, null: false, foreign_key: true
      t.references :external_agent_registration, null: false, foreign_key: true
      
      t.string :tool_name, null: false
      t.jsonb :arguments, default: {}
      t.jsonb :result, default: {}
      t.boolean :success, default: true
      t.string :error_message
      t.integer :latency_ms
      
      # Policy check result
      t.boolean :policy_allowed, default: true
      t.string :policy_rule_applied
      
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :external_agent_tool_calls, :tool_name
    add_index :external_agent_tool_calls, :executed_at
    add_index :external_agent_tool_calls, [:external_agent_registration_id, :executed_at], name: 'idx_ext_agent_tool_calls_agent_time'

    # Daily activity tracking for rate limiting
    create_table :external_agent_daily_stats do |t|
      t.references :external_agent_registration, null: false, foreign_key: true
      t.date :stat_date, null: false
      
      t.integer :bounties_claimed, default: 0
      t.integer :bounties_completed, default: 0
      t.integer :bounties_rejected, default: 0
      t.integer :tool_calls, default: 0
      t.decimal :tokens_earned, precision: 18, scale: 4, default: 0

      t.timestamps
    end

    add_index :external_agent_daily_stats, [:external_agent_registration_id, :stat_date], unique: true, name: 'idx_ext_agent_daily_stats_unique'
  end
end
