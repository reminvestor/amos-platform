# frozen_string_literal: true

class AddPublicAccessToModuleCanvases < ActiveRecord::Migration[8.0]
  def change
    add_column :module_canvases, :is_public, :boolean, default: false, null: false
    add_column :module_canvases, :public_slug, :string
    add_column :module_canvases, :published_at, :datetime
    add_column :module_canvases, :view_count, :integer, default: 0, null: false
    
    add_index :module_canvases, :is_public
    add_index :module_canvases, :public_slug, unique: true, where: "public_slug IS NOT NULL"
  end
end
