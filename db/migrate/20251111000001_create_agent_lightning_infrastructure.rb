class CreateAgentLightningInfrastructure < ActiveRecord::Migration[8.0]
  def change
    # Main trace collection table for Agent Lightning training
    create_table :agent_lightning_traces do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :workflow_execution, null: true, foreign_key: true
      t.references :task_session, null: true, foreign_key: true

      # Trace metadata
      t.string :trace_id, null: false  # Unique trace identifier
      t.string :trace_type, null: false  # "workflow", "llm_call", "tool_execution", etc.
      t.string :status, null: false, default: "pending"  # pending, completed, failed, training_ready

      # Input and output data
      t.jsonb :input_data, null: false, default: {}  # Initial request/context
      t.jsonb :output_data, null: false, default: {}  # Final result/response
      t.jsonb :intermediate_steps, null: false, default: []  # Step-by-step execution

      # Metadata for training
      t.jsonb :metadata, null: false, default: {}  # Additional context
      t.integer :token_count, null: true  # Total tokens used
      t.decimal :cost_estimate, null: true, precision: 10, scale: 6

      # Timing information
      t.integer :duration_ms, null: true  # Execution duration
      t.datetime :started_at, null: true
      t.datetime :completed_at, null: true

      # Reward signal (optional, for RL training)
      t.decimal :reward_signal, null: true, precision: 10, scale: 6
      t.string :reward_source, null: true  # "user_feedback", "automated", "validation"
      t.text :reward_explanation, null: true

      # Version tracking
      t.integer :template_version, null: true  # Workflow template version used
      t.string :model_used, null: true  # LLM model identifier

      # Training status
      t.boolean :included_in_training, default: false
      t.datetime :training_used_at, null: true

      t.timestamps
      t.index :trace_id, unique: true
      t.index [:entity_id, :trace_type, :status]
      t.index [:status, :included_in_training]
      t.index :created_at
    end

    # LLM call tracking for prompt optimization
    create_table :agent_llm_calls do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :agent_lightning_trace, null: true, foreign_key: true

      t.string :call_id, null: false
      t.string :model, null: false  # "claude-sonnet-4.5", etc.
      t.string :agent_role, null: false  # "planner", "executor", "validator"

      # Prompt and response data
      t.jsonb :system_prompt, null: false, default: {}
      t.jsonb :user_messages, null: false, default: []
      t.jsonb :response_content, null: false, default: {}

      # Token tracking
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0

      # Timing and cost
      t.integer :latency_ms, null: false, default: 0
      t.decimal :cost, null: true, precision: 10, scale: 8

      # Result tracking
      t.string :status, null: false  # "success", "error", "throttled"
      t.text :error_message, null: true

      # Success indicators
      t.jsonb :parsed_actions, null: true  # AI-generated actions/decisions
      t.boolean :actions_executed_successfully, null: true
      t.decimal :success_score, null: true, precision: 10, scale: 6

      t.datetime :called_at, null: false
      t.timestamps
      t.index :call_id, unique: true
      t.index [:entity_id, :agent_role, :status]
      t.index :called_at
    end

    # Tool execution tracking for action learning
    create_table :agent_tool_executions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :agent_lightning_trace, null: true, foreign_key: true
      t.references :agent_llm_call, null: true, foreign_key: true

      t.string :execution_id, null: false
      t.string :tool_name, null: false  # Tool being executed
      t.string :tool_category, null: false  # "crud", "integration", "search", etc.

      # Input and output
      t.jsonb :input_arguments, null: false, default: {}
      t.jsonb :output_result, null: false, default: {}

      # Execution details
      t.string :status, null: false  # "pending", "running", "success", "error"
      t.integer :execution_time_ms, null: false, default: 0
      t.text :error_message, null: true

      # Success indicators
      t.boolean :result_met_expectations, null: true
      t.decimal :execution_quality_score, null: true, precision: 10, scale: 6

      # Dependencies and chaining
      t.integer :sequence_number, null: false, default: 0  # Order in execution chain
      t.integer :parent_tool_execution_id, null: true  # For nested tool calls

      # Metadata
      t.jsonb :metadata, null: false, default: {}

      t.datetime :started_at, null: true
      t.datetime :completed_at, null: true
      t.timestamps
      t.index :execution_id, unique: true
      t.index [:entity_id, :tool_name, :status]
      t.index :started_at
    end

    # Workflow phase execution tracking
    create_table :agent_phase_executions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :workflow_execution, null: true, foreign_key: true
      t.references :agent_lightning_trace, null: true, foreign_key: true

      t.string :phase_id, null: false  # "gather_context", "execute_goal", "validate"
      t.string :phase_type, null: false

      # Execution tracking
      t.string :status, null: false  # "pending", "running", "success", "failed", "awaiting_input"
      t.integer :attempts, null: false, default: 1
      t.integer :duration_ms, null: false, default: 0

      # Input and output
      t.jsonb :phase_input, null: false, default: {}
      t.jsonb :phase_output, null: false, default: {}

      # Success metrics
      t.boolean :met_success_criteria, null: true
      t.decimal :phase_success_score, null: true, precision: 10, scale: 6
      t.text :failure_reason, null: true

      # Retry/self-healing information
      t.integer :max_retries, null: false, default: 3
      t.jsonb :retry_history, null: false, default: []

      t.datetime :started_at, null: true
      t.datetime :completed_at, null: true
      t.timestamps
      t.index [:entity_id, :workflow_execution_id, :phase_id]
      t.index :started_at
    end

    # Reward signals for RL training
    create_table :agent_rewards do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :agent_lightning_trace, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.string :reward_type, null: false  # "completion", "quality", "efficiency", "user_feedback", "validation"
      t.decimal :reward_value, null: false, precision: 10, scale: 6

      # Reward context
      t.text :reason, null: true
      t.jsonb :metadata, null: false, default: {}

      # Attribution
      t.string :source, null: false  # "user", "automated", "validation_engine"
      t.datetime :assigned_at, null: false

      t.timestamps
      t.index [:entity_id, :agent_lightning_trace_id]
      t.index [:reward_type, :assigned_at]
    end

    # Training job history
    create_table :agent_training_jobs do |t|
      t.references :entity, null: false, foreign_key: true

      t.string :job_id, null: false
      t.string :job_type, null: false  # "prompt_optimization", "supervised_finetuning", "rl_training"
      t.string :status, null: false, default: "pending"  # "pending", "running", "completed", "failed"

      # Training configuration
      t.jsonb :training_config, null: false, default: {}
      t.jsonb :model_config, null: false, default: {}

      # Training data
      t.integer :traces_used, null: false, default: 0
      t.integer :total_traces_available, null: false, default: 0

      # Results
      t.jsonb :training_results, null: false, default: {}
      t.decimal :improvement_score, null: true, precision: 10, scale: 6

      # Error tracking
      t.text :error_message, null: true

      # Timestamps
      t.datetime :started_at, null: true
      t.datetime :completed_at, null: true
      t.datetime :scheduled_for, null: true

      t.timestamps
      t.index :job_id, unique: true
      t.index [:entity_id, :status]
      t.index :scheduled_for
    end

    # Agent Lightning configuration per entity
    create_table :agent_lightning_configs do |t|
      t.references :entity, null: false, foreign_key: true

      t.boolean :enabled, default: true
      t.string :mode, null: false, default: "observing"  # "observing", "optimizing", "training"

      # Training strategy
      t.string :training_strategy, null: false, default: "prompt_optimization"
      t.integer :retrain_frequency_hours, null: false, default: 24
      t.datetime :last_training_at, null: true

      # Data retention
      t.integer :trace_retention_days, null: false, default: 90
      t.integer :min_traces_for_training, null: false, default: 100

      # Configuration
      t.jsonb :optimization_targets, null: false, default: {}  # Which metrics to optimize
      t.jsonb :learning_parameters, null: false, default: {}  # RL hyperparameters

      t.timestamps
      t.index :entity_id, unique: true
    end
  end
end
