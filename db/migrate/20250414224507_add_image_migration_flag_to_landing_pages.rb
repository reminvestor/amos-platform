class AddImageMigrationFlagToLandingPages < ActiveRecord::Migration[8.0]
  # Define the MigrationLandingPage class outside the method
  class MigrationLandingPage < ActiveRecord::Base
    self.table_name = "landing_pages"
    has_one_attached :hero_image
  end

  def up
    # Add migration_status column
    add_column :landing_pages, :migration_status, :string, default: 'pending'

    # Migrate existing images
    say_with_time "Migrating existing landing page images to Active Storage" do
      # Get all landing pages with image_url
      MigrationLandingPage.where.not(image_url: [ nil, '' ]).each do |landing_page|
        say "Migrating image for landing page ##{landing_page.id} - #{landing_page.title}"

        begin
          # Skip if already has a hero_image
          if landing_page.hero_image.attached?
            landing_page.update(migration_status: 'skipped_already_attached')
            say "  Already has hero_image attached, skipping"
            next
          end

          # Skip if image_url doesn't start with http
          unless landing_page.image_url.start_with?('http')
            landing_page.update(migration_status: 'skipped_invalid_url')
            say "  Invalid URL format: #{landing_page.image_url}, skipping"
            next
          end

          # Download and attach the image
          require 'open-uri'
          require 'securerandom'

          say "  Downloading from: #{landing_page.image_url}"
          downloaded_image = URI.open(landing_page.image_url)
          filename = "#{SecureRandom.uuid}-hero.png"

          landing_page.hero_image.attach(
            io: downloaded_image,
            filename: filename,
            content_type: 'image/png'
          )

          # Mark as migrated
          landing_page.update(migration_status: 'completed')
          say "  Successfully migrated"
        rescue StandardError => e
          landing_page.update(migration_status: "error: #{e.message.to_s[0..100]}")
          say "  Error: #{e.message}"
        end
      end

      # Return count of processed landing pages
      MigrationLandingPage.where(migration_status: 'completed').count
    end
  end

  def down
    # Just remove the migration_status column
    remove_column :landing_pages, :migration_status
  end
end
