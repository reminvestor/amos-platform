class AddMetadataToLandingPages < ActiveRecord::Migration[8.0]
  def change
    add_column :landing_pages, :metadata, :jsonb, default: {}, null: false
    add_index :landing_pages, :metadata, using: :gin
  end
end
