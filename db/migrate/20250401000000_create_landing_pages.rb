class CreateLandingPages < ActiveRecord::Migration[8.0]
  def change
    create_table :landing_pages do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.jsonb :content, default: {}
      t.string :status, default: 'draft'
      t.string :page_type
      t.text :meta_description
      t.string :meta_keywords
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :campaign, foreign_key: true
      t.string :custom_domain
      t.boolean :published, default: false
      t.datetime :published_at
      t.string :headline
      t.text :subheadline
      t.string :cta_text
      t.string :cta_url
      t.string :primary_color
      t.string :secondary_color
      t.string :font_family
      t.string :image_url
      t.jsonb :image_prompts
      t.jsonb :ai_settings

      t.timestamps
    end

    add_index :landing_pages, :slug, unique: true
    add_index :landing_pages, :published
  end
end
