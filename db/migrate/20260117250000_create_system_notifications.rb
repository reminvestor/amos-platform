# frozen_string_literal: true

class CreateSystemNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :system_notifications do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      
      t.string :category, null: false
      t.string :severity, null: false, default: 'info'
      t.string :title, null: false
      t.text :message
      t.jsonb :metadata, default: {}
      
      # Action support
      t.boolean :actionable, default: false
      t.string :action_label
      t.string :action_path
      
      # Read status
      t.datetime :read_at
      
      # Dismissal
      t.datetime :dismissed_at
      t.string :dismissed_by
      
      t.timestamps
    end

    add_index :system_notifications, [:entity_id, :user_id, :read_at], name: 'idx_notifications_unread'
    add_index :system_notifications, [:entity_id, :category]
    add_index :system_notifications, [:entity_id, :severity]
    add_index :system_notifications, [:entity_id, :created_at]
  end
end

