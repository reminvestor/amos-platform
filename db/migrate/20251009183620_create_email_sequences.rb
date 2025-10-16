class CreateEmailSequences < ActiveRecord::Migration[8.0]
  def change
    create_table :email_sequences do |t|
      t.string :name, null: false
      t.text :goal
      t.string :status, default: 'draft', null: false
      t.references :contact_group, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.integer :enrolled_count, default: 0
      t.integer :completed_count, default: 0
      t.integer :active_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :email_sequences, :status
    add_index :email_sequences, [:entity_id, :status]
  end
end
