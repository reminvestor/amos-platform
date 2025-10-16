class CreateEntities < ActiveRecord::Migration[8.0]
  def change
    create_table :entities do |t|
      t.string :name
      t.string :subdomain
      t.string :slug
      t.string :status, default: 'active'
      t.jsonb :settings, default: {}

      t.timestamps
    end

    add_index :entities, :subdomain, unique: true
    add_index :entities, :slug, unique: true
  end
end
