# frozen_string_literal: true

class CreatePlatformEvolutionTables < ActiveRecord::Migration[7.1]
  def change
    # Support Tickets - The entry point for all issues
    create_table :support_tickets do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :scout_conversation, foreign_key: true

      t.string :ticket_number, null: false  # Human-readable ID like "AMOS-1234"
      t.string :title, null: false
      t.text :description

      # Source of the ticket
      t.string :source, null: false, default: 'user_reported'
      # user_reported, amos_detected, log_monitor, scheduled_scan, agent_failure

      # Status tracking
      t.string :status, null: false, default: 'open'
      # open, investigating, debugging, fixing, testing, pr_submitted, pr_approved, resolved, closed, wont_fix

      # Priority and categorization
      t.string :priority, null: false, default: 'medium'
      # low, medium, high, critical

      t.string :category
      # bug, performance, feature_request, security, data_issue, agent_error, integration_error

      # Error details (for auto-detected issues)
      t.string :error_class
      t.string :error_message
      t.text :stack_trace
      t.string :error_signature  # Hash for deduplication
      t.string :error_file
      t.integer :error_line
      t.jsonb :error_context, default: {}

      # Assignment
      t.string :assigned_to_type  # 'agent' or 'human'
      t.string :assigned_to_id

      # Resolution
      t.text :resolution_notes
      t.datetime :resolved_at
      t.string :resolved_by

      # Metrics
      t.integer :time_to_first_response_minutes
      t.integer :time_to_resolution_minutes
      t.integer :debug_session_count, default: 0
      t.integer :code_fix_attempts, default: 0

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :ticket_number, unique: true
      t.index :status
      t.index :priority
      t.index :source
      t.index :error_signature
      t.index [:entity_id, :status]
      t.index [:entity_id, :created_at]
    end

    # Debug Sessions - Interactive debugging conversations
    create_table :debug_sessions do |t|
      t.references :support_ticket, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true

      t.string :session_id, null: false  # Unique session identifier
      t.string :status, null: false, default: 'gathering_info'
      # gathering_info, analyzing, reproducing, proposing_fix, awaiting_approval, completed, abandoned

      # Conversation with user/agent
      t.jsonb :conversation_history, default: []
      # Array of {role: 'user'|'agent'|'system', content: '...', timestamp: '...'}

      # Analysis results
      t.jsonb :findings, default: {}
      # {logs_analyzed: [...], code_reviewed: [...], patterns_found: [...]}

      t.text :root_cause_analysis
      t.decimal :confidence_score, precision: 5, scale: 4

      # Proposed fixes
      t.jsonb :proposed_fixes, default: []
      # Array of {description: '...', files: [...], risk_level: '...', estimated_impact: '...'}

      t.integer :selected_fix_index
      t.text :fix_rationale

      # Reproduction
      t.boolean :reproduced, default: false
      t.jsonb :reproduction_steps, default: []
      t.jsonb :reproduction_results, default: {}

      # AI model tracking
      t.string :ai_model_used
      t.integer :total_tokens_used, default: 0
      t.decimal :total_cost_usd, precision: 10, scale: 4, default: 0

      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :session_id, unique: true
      t.index :status
      t.index [:support_ticket_id, :status]
    end

    # Code Fixes - Generated code changes
    create_table :code_fixes do |t|
      t.references :debug_session, null: false, foreign_key: true
      t.references :support_ticket, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      t.string :fix_id, null: false  # Unique fix identifier
      t.string :status, null: false, default: 'drafting'
      # drafting, testing, test_failed, validated, rejected, applied, rolled_back

      # What's being fixed
      t.text :fix_description
      t.string :fix_type  # hotfix, refactor, enhancement, config_change
      t.string :risk_level  # low, medium, high, critical

      # The actual changes
      t.jsonb :files_modified, default: []
      # Array of {path: '...', original_content: '...', modified_content: '...', diff: '...'}

      t.integer :files_changed_count, default: 0
      t.integer :lines_added, default: 0
      t.integer :lines_removed, default: 0

      # Testing
      t.jsonb :test_results, default: {}
      # {tests_run: 0, tests_passed: 0, tests_failed: 0, test_output: '...'}

      t.boolean :tests_passed, default: false
      t.boolean :lint_passed, default: false
      t.text :validation_notes

      # Git tracking
      t.string :git_branch
      t.string :git_commit_sha
      t.string :base_commit_sha

      # Approval
      t.string :reviewed_by
      t.datetime :reviewed_at
      t.text :review_notes
      t.string :review_decision  # approved, rejected, needs_changes

      # Application
      t.datetime :applied_at
      t.string :applied_by
      t.datetime :rolled_back_at
      t.string :rolled_back_by
      t.text :rollback_reason

      # AI tracking
      t.string :ai_model_used
      t.integer :tokens_used, default: 0
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :fix_id, unique: true
      t.index :status
      t.index :git_branch
      t.index :git_commit_sha
      t.index [:support_ticket_id, :status]
    end

    # Pull Request Submissions - GitHub/GitLab integration
    create_table :pull_request_submissions do |t|
      t.references :code_fix, null: false, foreign_key: true
      t.references :support_ticket, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      t.string :pr_number
      t.string :pr_url
      t.string :pr_title
      t.text :pr_body

      t.string :source_branch
      t.string :target_branch, default: 'main'

      t.string :status, null: false, default: 'pending'
      # pending, open, review_requested, approved, changes_requested, merged, closed

      # Review tracking
      t.jsonb :reviewers, default: []
      t.jsonb :review_comments, default: []
      t.integer :review_count, default: 0
      t.integer :approval_count, default: 0

      # CI/CD
      t.string :ci_status  # pending, running, passed, failed
      t.jsonb :ci_results, default: {}

      # Merge tracking
      t.datetime :merged_at
      t.string :merged_by
      t.string :merge_commit_sha

      # Closure tracking
      t.datetime :closed_at
      t.string :closed_by
      t.text :close_reason

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :pr_number
      t.index :status
      t.index [:code_fix_id, :status]
    end

    # Error Log Entries - Captured from logs for analysis
    create_table :error_log_entries do |t|
      t.references :entity, foreign_key: true
      t.references :support_ticket, foreign_key: true

      t.string :log_level, null: false  # error, fatal, warn
      t.string :error_class
      t.string :error_message
      t.text :stack_trace
      t.string :error_signature  # Hash for grouping

      t.string :source_file
      t.integer :source_line
      t.string :source_method

      t.jsonb :context, default: {}
      # {request_id: '...', user_id: '...', params: {...}, headers: {...}}

      t.datetime :occurred_at, null: false
      t.integer :occurrence_count, default: 1  # For grouped entries
      t.datetime :first_occurrence
      t.datetime :last_occurrence

      t.boolean :processed, default: false
      t.boolean :ticket_created, default: false

      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :error_signature
      t.index :log_level
      t.index :occurred_at
      t.index [:entity_id, :occurred_at]
      t.index [:error_signature, :processed]
    end
  end
end


