class CreatePlatformTables < ActiveRecord::Migration[7.0]
  def change
    # Enable pg_trgm extension for trigram searches
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')
    # Custom plugins (agents, tools, workflows)
    create_table :custom_plugins do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :plugin_type, null: false # agent, tool, model, workflow
      t.string :plugin_id, null: false
      t.jsonb :spec, null: false, default: {}
      t.text :code # Ruby code for agents/tools
      t.string :status, default: 'pending'
      t.jsonb :metadata, default: {}
      t.timestamps
      
      t.index [:entity_id, :plugin_type, :plugin_id], unique: true, name: 'idx_custom_plugins_unique'
      t.index :plugin_type
      t.index :status
    end
    
    # Custom models configuration
    create_table :custom_models do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :model_id, null: false
      t.string :bedrock_model_id # Bedrock's ID for the model
      t.jsonb :config, null: false, default: {}
      t.string :status, default: 'pending'
      t.jsonb :training_metrics, default: {}
      t.timestamps
      
      t.index [:entity_id, :model_id], unique: true
      t.index :bedrock_model_id
      t.index :status
    end
    
    # Plugin permissions
    create_table :plugin_permissions do |t|
      t.references :custom_plugin, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :entity, foreign_key: true
      t.string :permission_type, null: false # use, edit, share
      t.datetime :expires_at
      t.timestamps
      
      t.index [:custom_plugin_id, :user_id, :permission_type], unique: true, name: 'idx_plugin_perms_user'
      t.index [:custom_plugin_id, :entity_id, :permission_type], unique: true, name: 'idx_plugin_perms_entity'
    end
    
    # Plugin usage tracking
    create_table :plugin_usages do |t|
      t.string :plugin_id, null: false
      t.references :user, foreign_key: true
      t.references :entity, foreign_key: true
      t.integer :execution_count, default: 1
      t.float :memory_mb
      t.float :cpu_seconds
      t.integer :api_calls
      t.integer :tokens_used
      t.float :duration_ms
      t.jsonb :metrics, default: {}
      t.datetime :created_at, null: false
      
      t.index :plugin_id
      t.index [:plugin_id, :created_at]
      t.index :created_at
    end
    
    # Model permissions
    create_table :model_permissions do |t|
      t.references :custom_model, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :permission_type, null: false # use, fine_tune
      t.integer :usage_limit # tokens per month
      t.timestamps
      
      t.index [:custom_model_id, :entity_id, :permission_type], unique: true, name: 'idx_model_perms'
    end
    
    # Shared plugins marketplace
    create_table :shared_plugins do |t|
      t.references :custom_plugin, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true # Publisher
      t.string :listing_status, default: 'pending' # pending, approved, rejected
      t.string :title, null: false
      t.text :description
      t.string :category
      t.jsonb :tags, default: []
      t.decimal :price, precision: 10, scale: 2, default: 0.0
      t.string :pricing_model # free, one_time, subscription, usage_based
      t.integer :install_count, default: 0
      t.float :average_rating
      t.jsonb :screenshots, default: []
      t.timestamps
      
      t.index :listing_status
      t.index :category
      t.index :price
      t.index :tags, using: :gin
    end
    
    # Plugin ratings and reviews
    create_table :plugin_reviews do |t|
      t.references :shared_plugin, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :rating, null: false # 1-5
      t.text :review
      t.boolean :verified_purchase, default: false
      t.timestamps
      
      t.index [:shared_plugin_id, :user_id], unique: true
      t.index :rating
    end
    
    # Shared models marketplace
    create_table :shared_models do |t|
      t.references :custom_model, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true # Provider
      t.string :name, null: false
      t.text :description
      t.string :base_model
      t.jsonb :capabilities, default: []
      t.jsonb :benchmark_scores, default: {}
      t.decimal :cost_per_1k_tokens, precision: 10, scale: 6
      t.integer :usage_count, default: 0
      t.float :average_rating
      t.boolean :active, default: true
      t.timestamps
      
      t.index :active
      t.index :base_model
      t.index :cost_per_1k_tokens
    end
    
    # Agent collaboration messages
    create_table :agent_messages do |t|
      t.string :sender_id, null: false
      t.string :recipient_id, null: false
      t.string :message_type, null: false
      t.jsonb :content, null: false
      t.references :task_session, foreign_key: true
      t.string :priority, default: 'normal'
      t.string :parent_message_id
      t.jsonb :metadata, default: {}
      t.timestamps
      
      t.index :sender_id
      t.index :recipient_id
      t.index [:task_session_id, :created_at]
      t.index :message_type
      t.index :parent_message_id
    end
    
    # Plugin marketplace transactions
    create_table :plugin_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :shared_plugin, foreign_key: true
      t.references :shared_model, foreign_key: true
      t.string :transaction_type # purchase, subscription, usage
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency, default: 'USD'
      t.string :status # pending, completed, failed, refunded
      t.jsonb :payment_details, default: {}
      t.timestamps
      
      t.index :status
      t.index [:entity_id, :created_at]
    end
    
    # Add platform fields to existing tables
    add_column :users, :developer_mode, :boolean, default: false
    add_column :users, :api_key_encrypted, :string
    add_column :users, :plugin_development_enabled, :boolean, default: false
    
    add_column :entities, :platform_tier, :string, default: 'standard' # standard, developer, enterprise
    add_column :entities, :custom_plugin_limit, :integer, default: 5
    add_column :entities, :custom_model_limit, :integer, default: 1
    add_column :entities, :marketplace_vendor, :boolean, default: false
    
    # Create indexes for performance
    add_index :plugin_usages, [:entity_id, :plugin_id, :created_at], name: 'idx_plugin_usage_analytics'
    add_index :shared_plugins, [:listing_status, :average_rating], name: 'idx_marketplace_ranking'
  end
end