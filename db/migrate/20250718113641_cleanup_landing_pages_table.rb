class CleanupLandingPagesTable < ActiveRecord::Migration[8.0]
  def up
    # Remove columns we no longer need
    remove_column :landing_pages, :content, :jsonb
    remove_column :landing_pages, :page_type, :string
    remove_column :landing_pages, :meta_description, :text
    remove_column :landing_pages, :meta_keywords, :string
    remove_column :landing_pages, :custom_domain, :string
    remove_column :landing_pages, :published, :boolean
    remove_column :landing_pages, :published_at, :datetime
    remove_column :landing_pages, :headline, :string
    remove_column :landing_pages, :subheadline, :text
    remove_column :landing_pages, :cta_text, :string
    remove_column :landing_pages, :cta_url, :string
    remove_column :landing_pages, :primary_color, :string
    remove_column :landing_pages, :secondary_color, :string
    remove_column :landing_pages, :font_family, :string
    remove_column :landing_pages, :image_url, :string
    remove_column :landing_pages, :image_prompts, :jsonb
    remove_column :landing_pages, :ai_settings, :jsonb
    remove_column :landing_pages, :migration_status, :string
    remove_column :landing_pages, :clarification_questions, :text
    remove_column :landing_pages, :clarification_answers, :text

    # Remove the published index since we're removing the column (if it exists)
    remove_index :landing_pages, :published if index_exists?(:landing_pages, :published)
  end

  def down
    # Add back all the columns if we need to rollback
    add_column :landing_pages, :content, :jsonb, default: {}
    add_column :landing_pages, :page_type, :string
    add_column :landing_pages, :meta_description, :text
    add_column :landing_pages, :meta_keywords, :string
    add_column :landing_pages, :custom_domain, :string
    add_column :landing_pages, :published, :boolean, default: false
    add_column :landing_pages, :published_at, :datetime
    add_column :landing_pages, :headline, :string
    add_column :landing_pages, :subheadline, :text
    add_column :landing_pages, :cta_text, :string
    add_column :landing_pages, :cta_url, :string
    add_column :landing_pages, :primary_color, :string
    add_column :landing_pages, :secondary_color, :string
    add_column :landing_pages, :font_family, :string
    add_column :landing_pages, :image_url, :string
    add_column :landing_pages, :image_prompts, :jsonb
    add_column :landing_pages, :ai_settings, :jsonb
    add_column :landing_pages, :migration_status, :string, default: 'pending'
    add_column :landing_pages, :clarification_questions, :text
    add_column :landing_pages, :clarification_answers, :text

    add_index :landing_pages, :published
  end
end
