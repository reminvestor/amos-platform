class AddSharedWithEntityToImageAssets < ActiveRecord::Migration[7.1]
  def change
    # Add shared_with_entity flag - default false means private to user
    add_column :image_assets, :shared_with_entity, :boolean, default: false, null: false
    
    # Add index for efficient querying
    add_index :image_assets, [:user_id, :shared_with_entity]
    add_index :image_assets, [:entity_id, :shared_with_entity]
  end
end

