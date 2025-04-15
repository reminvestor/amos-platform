class CreateLandingPageVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :landing_page_versions do |t|
      t.references :landing_page, null: false, foreign_key: true
      t.jsonb :content
      t.string :headline
      t.text :subheadline
      t.string :cta_text
      t.string :cta_url
      t.string :primary_color
      t.string :secondary_color
      t.string :font_family
      t.boolean :ai_applied
      t.text :description

      t.timestamps
    end
  end
end
