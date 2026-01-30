# frozen_string_literal: true

class CreateSequenceEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :sequence_email_deliveries do |t|
      t.references :email_sequence, null: false, foreign_key: true
      t.references :sequence_step, null: false, foreign_key: true
      t.references :sequence_enrollment, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      t.string :status, default: 'pending', null: false
      t.string :ses_message_id
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.text :error_message

      t.timestamps
    end

    add_index :sequence_email_deliveries, :ses_message_id, unique: true
    add_index :sequence_email_deliveries, :status
    add_index :sequence_email_deliveries, [:email_sequence_id, :sequence_step_id], name: 'idx_seq_deliveries_on_seq_and_step'
    add_index :sequence_email_deliveries, [:contact_id, :sequence_enrollment_id], name: 'idx_seq_deliveries_on_contact_and_enrollment'
  end
end
