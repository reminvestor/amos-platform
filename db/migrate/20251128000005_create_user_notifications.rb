# frozen_string_literal: true

class CreateUserNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :user_notifications do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :agent_work_item, foreign_key: true
      t.references :scheduled_task_run, foreign_key: true
      
      t.string :notification_type, null: false  # task_completed, action_required, daily_digest, etc.
      t.string :title, null: false
      t.text :body
      t.string :icon                           # emoji or icon name
      
      # Delivery
      t.string :channel, null: false           # in_app, email, both
      t.boolean :email_sent, default: false
      t.datetime :email_sent_at
      t.boolean :push_sent, default: false
      t.datetime :push_sent_at
      
      # User interaction
      t.boolean :read, default: false
      t.datetime :read_at
      t.boolean :dismissed, default: false
      t.datetime :dismissed_at
      
      # Action handling
      t.string :action_url                     # Where to go when clicked
      t.string :action_type                    # view, approve, respond, etc.
      t.jsonb :action_data, default: {}
      
      t.string :priority, default: 'normal'    # low, normal, high, urgent
      t.datetime :expires_at                   # Auto-dismiss after this time
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :user_notifications, :notification_type
    add_index :user_notifications, :channel
    add_index :user_notifications, :read
    add_index :user_notifications, :dismissed
    add_index :user_notifications, :priority
    add_index :user_notifications, [:user_id, :read]
    add_index :user_notifications, [:user_id, :dismissed]
    add_index :user_notifications, [:entity_id, :user_id, :read]
    add_index :user_notifications, :created_at
  end
end

