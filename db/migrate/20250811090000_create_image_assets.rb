class CreateImageAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :image_assets do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.string :source, null: false, default: 'upload' # upload | ai
      t.string :tags, array: true, default: []
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :image_assets, :tags, using: :gin
  end
end
