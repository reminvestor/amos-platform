namespace :images do
  desc "Migrate landing page images to Active Storage"
  task migrate_to_active_storage: :environment do
    puts "Starting migration of landing page images to Active Storage..."
    
    # Get all landing pages with image_url
    landing_pages = LandingPage.where.not(image_url: [nil, ''])
    
    puts "Found #{landing_pages.count} landing pages with image URLs"
    
    # Track statistics
    stats = {
      success: 0,
      skipped_already_attached: 0,
      skipped_invalid_url: 0,
      error: 0
    }
    
    landing_pages.each do |landing_page|
      puts "Processing landing page ##{landing_page.id} - #{landing_page.title}"
      
      begin
        # Skip if already has a hero_image
        if landing_page.hero_image.attached?
          landing_page.update(migration_status: 'skipped_already_attached')
          puts "  Already has hero_image attached, skipping"
          stats[:skipped_already_attached] += 1
          next
        end
        
        # Skip if image_url doesn't start with http
        unless landing_page.image_url.start_with?('http')
          landing_page.update(migration_status: 'skipped_invalid_url')
          puts "  Invalid URL format: #{landing_page.image_url}, skipping"
          stats[:skipped_invalid_url] += 1
          next
        end
        
        # For DALL-E images, they might be expired, so we should generate a new one
        if landing_page.image_url.include?('oaidalleapiprodscus.blob.core.windows.net')
          puts "  DALL-E URL detected, may be expired"
          
          # Use a placeholder image instead
          placeholder_url = "https://placehold.co/1024x1024.png"
          puts "  Using placeholder: #{placeholder_url}"
          
          require 'open-uri'
          require 'securerandom'
          
          downloaded_image = URI.open(placeholder_url)
          filename = "#{SecureRandom.uuid}-hero.png"
          
          landing_page.hero_image.attach(
            io: downloaded_image,
            filename: filename,
            content_type: 'image/png'
          )
          
          # Mark as migrated but with a note about placeholder
          landing_page.update(migration_status: 'completed_placeholder')
          puts "  Successfully attached placeholder image"
          stats[:success] += 1
        else
          # Try to download the regular image
          puts "  Downloading from: #{landing_page.image_url}"
          
          require 'open-uri'
          require 'securerandom'
          
          downloaded_image = URI.open(landing_page.image_url)
          filename = "#{SecureRandom.uuid}-hero.png"
          
          landing_page.hero_image.attach(
            io: downloaded_image,
            filename: filename,
            content_type: 'image/png'
          )
          
          # Mark as migrated
          landing_page.update(migration_status: 'completed')
          puts "  Successfully migrated"
          stats[:success] += 1
        end
      rescue StandardError => e
        landing_page.update(migration_status: "error: #{e.message.to_s[0..100]}")
        puts "  Error: #{e.message}"
        stats[:error] += 1
      end
    end
    
    # Print summary
    puts "\nMigration summary:"
    puts "  Total landing pages processed: #{landing_pages.count}"
    puts "  Successfully migrated: #{stats[:success]}"
    puts "  Skipped (already attached): #{stats[:skipped_already_attached]}"
    puts "  Skipped (invalid URL): #{stats[:skipped_invalid_url]}"
    puts "  Errors: #{stats[:error]}"
  end
end 