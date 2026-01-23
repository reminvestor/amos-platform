# frozen_string_literal: true

class CreateIntegrationActions < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_actions do |t|
      t.references :integration, null: false, foreign_key: true
      t.references :integration_operation, null: false, foreign_key: true
      t.references :entity, foreign_key: true  # nil = global template
      t.references :created_by, foreign_key: { to_table: :users }

      # Action identity
      t.string :action_name, null: false      # "place_limit_order"
      t.string :slug, null: false             # "coinbase.place_limit_order"
      t.text :description
      t.string :category                      # "trading", "crm", "messaging"

      # Input schema (what Amos provides - normalized interface)
      # Format: [{ name: "symbol", type: "string", required: true, description: "Trading pair" }]
      t.jsonb :input_schema, default: []

      # AI-generated Ruby code for mapping inputs → API params
      t.text :mapping_code
      t.integer :mapping_code_version, default: 0
      t.datetime :mapping_code_generated_at
      t.string :mapping_code_generated_by

      # Optional: AI-generated Ruby code for normalizing response
      t.text :response_mapping_code

      # Sample data for testing and documentation
      t.jsonb :sample_input, default: {}
      t.jsonb :sample_output, default: {}
      t.jsonb :sample_response, default: {}

      # Status tracking
      t.integer :status, default: 0           # draft, testing, active, deprecated

      # Usage metrics
      t.integer :usage_count, default: 0
      t.integer :success_count, default: 0
      t.integer :error_count, default: 0
      t.datetime :last_used_at

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :integration_actions, [:integration_id, :action_name], unique: true
    add_index :integration_actions, :slug, unique: true
    add_index :integration_actions, :status
    add_index :integration_actions, :category

    # Execution audit trail
    create_table :integration_action_executions do |t|
      t.references :integration_action, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :entity, foreign_key: true

      # What was requested
      t.jsonb :inputs, default: {}

      # What was sent to API (after mapping)
      t.jsonb :mapped_params, default: {}

      # What came back
      t.jsonb :raw_response, default: {}
      t.jsonb :normalized_response, default: {}

      # Status
      t.integer :status, default: 0  # pending, success, failed, rate_limited
      t.text :error_message
      t.integer :http_status_code

      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      t.timestamps
    end

    add_index :integration_action_executions, :status
    add_index :integration_action_executions, :created_at
  end
end

