class AddStyleGuidelinesToBusinessProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :business_profiles, :style_guidelines, :jsonb, default: {}, null: false
    
    add_index :business_profiles, :style_guidelines, using: :gin
  end
end
