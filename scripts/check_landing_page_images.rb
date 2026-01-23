#!/usr/bin/env rails runner
# Check landing page images for broken blobs
# Run with: rails runner scripts/check_landing_page_images.rb

require 'net/http'
require 'uri'

puts "🔍 Checking landing page images..."
puts "=" * 60

issues = []
checked = 0

# Get landing pages with images
LandingPage.where.not(html_content: nil).find_each do |lp|
  next if lp.html_content.blank?
  
  # Extract image URLs from HTML
  image_urls = lp.html_content.scan(/src\s*=\s*["']([^"']+)["']/i).flatten
  image_urls = image_urls.select { |url| url.include?('active_storage') || url.include?('blob') }
  
  next if image_urls.empty?
  
  checked += 1
  puts "\n📄 Landing Page #{lp.id}: #{lp.title}"
  puts "   Found #{image_urls.count} Active Storage images"
  
  image_urls.each do |url|
    begin
      # Parse the blob signed ID from the URL
      if url =~ /blobs\/redirect\/([^\/]+)/
        signed_id = $1
        blob = ActiveStorage::Blob.find_signed(signed_id)
        
        if blob
          puts "   ✅ Blob #{blob.id} exists: #{blob.filename}"
          
          # Check if the file exists in storage
          if blob.service.exist?(blob.key)
            puts "      ✅ File exists in storage"
          else
            puts "      ❌ FILE MISSING FROM STORAGE!"
            issues << { lp_id: lp.id, lp_title: lp.title, blob_id: blob.id, issue: "File missing from storage" }
          end
        else
          puts "   ❌ Blob not found for signed ID"
          issues << { lp_id: lp.id, lp_title: lp.title, issue: "Blob not found for signed ID" }
        end
      else
        puts "   ⚠️ Could not parse blob ID from URL: #{url[0..80]}..."
      end
    rescue ActiveStorage::FileNotFoundError => e
      puts "   ❌ File not found: #{e.message}"
      issues << { lp_id: lp.id, lp_title: lp.title, issue: "FileNotFoundError: #{e.message}" }
    rescue => e
      puts "   ❌ Error checking: #{e.message}"
      issues << { lp_id: lp.id, lp_title: lp.title, issue: e.message }
    end
  end
end

puts "\n"
puts "=" * 60
puts "📊 Summary:"
puts "   Landing pages with images checked: #{checked}"
puts "   Issues found: #{issues.count}"

if issues.any?
  puts "\n❌ Issues:"
  issues.each do |issue|
    puts "   LP #{issue[:lp_id]} (#{issue[:lp_title]}): #{issue[:issue]}"
  end
end

puts "=" * 60
