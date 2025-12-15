class CreateUserNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :user_notes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content
      t.string :color, default: 'default'
      t.boolean :pinned, default: false
      t.boolean :archived, default: false
      t.datetime :archived_at

      t.timestamps
    end

    add_index :user_notes, [:user_id, :pinned]
    add_index :user_notes, [:user_id, :archived]
  end
end
