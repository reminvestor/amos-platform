class CreateUserReminders < ActiveRecord::Migration[8.0]
  def change
    create_table :user_reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.datetime :remind_at, null: false
      t.string :repeat_interval  # none, daily, weekly, monthly
      t.boolean :completed, default: false
      t.datetime :completed_at
      t.boolean :notified, default: false
      t.datetime :notified_at
      t.string :priority, default: 'normal'  # low, normal, high

      t.timestamps
    end

    add_index :user_reminders, [:user_id, :remind_at]
    add_index :user_reminders, [:user_id, :completed]
  end
end
