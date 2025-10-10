class CreateSequenceSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :sequence_steps do |t|
      t.references :email_sequence, null: false, foreign_key: true
      t.integer :step_number, null: false
      t.integer :delay_hours, default: 0, null: false
      t.references :email_template, null: true, foreign_key: true
      t.string :subject
      t.text :body
      t.integer :sent_count, default: 0
      t.integer :opened_count, default: 0
      t.integer :clicked_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :sequence_steps, [:email_sequence_id, :step_number], unique: true
    add_index :sequence_steps, :delay_hours
  end
end
