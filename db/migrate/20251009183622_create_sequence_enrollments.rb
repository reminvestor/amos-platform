class CreateSequenceEnrollments < ActiveRecord::Migration[8.0]
  def change
    create_table :sequence_enrollments do |t|
      t.references :email_sequence, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :status, default: 'pending', null: false
      t.integer :current_step_number, default: 0
      t.datetime :next_send_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_email_sent_at

      t.timestamps
    end

    add_index :sequence_enrollments, [:email_sequence_id, :contact_id], unique: true, name: 'index_enrollments_on_sequence_and_contact'
    add_index :sequence_enrollments, :status
    add_index :sequence_enrollments, :next_send_at
    add_index :sequence_enrollments, [:entity_id, :status]
  end
end
