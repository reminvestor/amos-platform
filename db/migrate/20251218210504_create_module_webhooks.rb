# frozen_string_literal: true

class CreateModuleWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :module_webhooks do |t|
      t.references :app_module, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Webhook identification
      t.string :event_name, null: false  # stripe.payment_succeeded, shopify.order_created
      t.string :slug, null: false        # Unique URL-safe identifier
      t.text :description
      
      # Authentication
      t.string :auth_type, default: 'token'  # token, signature, ip_allowlist, none
      t.string :auth_token                   # For token auth (hashed)
      t.string :signing_secret               # For signature verification
      t.jsonb :ip_allowlist, default: []     # For IP filtering
      
      # Payload configuration
      t.jsonb :payload_schema, default: {}   # Expected JSON schema
      t.jsonb :field_mappings, default: {}   # Map incoming fields to internal fields
      # {
      #   'data.object.customer_email' => 'contact.email',
      #   'data.object.amount' => 'payment.amount'
      # }
      
      # Target - what to trigger
      t.string :target_type, null: false    # agent, tool, workflow
      t.bigint :target_id                   # ID of the agent/workflow
      t.string :target_tool                 # Tool name if target_type is 'tool'
      
      # Additional context to pass to target
      t.jsonb :context_template, default: {}
      
      # Rate limiting
      t.integer :rate_limit_per_minute, default: 60
      t.integer :rate_limit_per_hour, default: 1000
      
      # Status and logging
      t.string :status, default: 'active'  # active, paused, disabled
      t.integer :call_count, default: 0
      t.datetime :last_called_at
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.text :last_failure_reason
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :module_webhooks, [:entity_id, :slug], unique: true
    add_index :module_webhooks, [:app_module_id, :event_name]
    add_index :module_webhooks, :status
    add_index :module_webhooks, :target_type
  end
end





