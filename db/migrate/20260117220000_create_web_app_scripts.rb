# frozen_string_literal: true

class CreateWebAppScripts < ActiveRecord::Migration[7.1]
  def change
    # WebAppScript - Safe external JS libraries for web apps
    create_table :web_app_scripts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :web_app, null: true, foreign_key: true
      t.references :website, null: true, foreign_key: true
      t.references :landing_page, null: true, foreign_key: { to_table: :landing_pages }
      
      t.string :name, null: false
      t.string :library_type, null: false  # cdn, inline, npm
      t.string :library_name               # e.g., 'chart.js', 'alpine.js'
      t.string :cdn_url                    # CDN URL if type is cdn
      t.text :inline_code                  # Inline JS if type is inline
      t.string :version                    # Library version
      t.string :integrity_hash             # SRI hash for CDN
      t.boolean :is_module, default: false # ES module or classic script
      t.string :load_strategy, default: 'defer'  # defer, async, blocking
      t.integer :load_order, default: 0    # Order to load scripts
      t.string :status, default: 'active'  # active, disabled, deprecated
      t.jsonb :config, default: {}         # Library-specific configuration
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :web_app_scripts, [:entity_id, :library_name]
    add_index :web_app_scripts, [:web_app_id, :load_order]
    add_index :web_app_scripts, [:website_id, :load_order]
    add_index :web_app_scripts, [:landing_page_id, :load_order]
  end
end

