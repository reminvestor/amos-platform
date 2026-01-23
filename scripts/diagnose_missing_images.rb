#!/usr/bin/env rails runner
# Diagnose missing images in landing pages
# Run with: rails runner scripts/diagnose_missing_images.rb

puts "🔍 Diagnosing missing images..."
puts "=" * 60

# Check ActiveStorage::Blob count
total_blobs = ActiveStorage::Blob.count
puts "📦 Total ActiveStorage::Blob records: #{total_blobs}"

# Check ImageAsset count and attached files
total_assets = ImageAsset.count
attached_assets = ImageAsset.joins(:file_attachment).count
unattached_assets = total_assets - attached_assets
puts "🖼️  Total ImageAsset records: #{total_assets}"
puts "   - With attached files: #{attached_assets}"
puts "   - Without attached files: #{unattached_assets}"

# Check for blobs referenced in landing pages
puts "\n📄 Checking landing pages with Active Storage URLs..."

missing_blobs = []
found_blobs = []

LandingPage.where.not(html_content: nil).find_each do |lp|
  next if lp.html_content.blank?
  
  # Extract blob signed IDs from HTML
  blob_refs = lp.html_content.scan(/blobs\/redirect\/([^\/]+)/).flatten
  
  next if blob_refs.empty?
  
  blob_refs.each do |signed_id|
    begin
      blob = ActiveStorage::Blob.find_signed(signed_id)
      if blob
        found_blobs << { lp_id: lp.id, blob_id: blob.id, filename: blob.filename.to_s }
      else
        missing_blobs << { lp_id: lp.id, signed_id: signed_id[0..20] + "..." }
      end
    rescue ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError => e
      missing_blobs << { lp_id: lp.id, signed_id: signed_id[0..20] + "...", error: e.class.name }
    rescue => e
      missing_blobs << { lp_id: lp.id, signed_id: signed_id[0..20] + "...", error: e.message }
    end
  end
end

puts "\n✅ Found #{found_blobs.count} valid blob references"
puts "❌ Missing #{missing_blobs.count} blob references"

if missing_blobs.any?
  puts "\n❌ Missing blobs:"
  missing_blobs.first(10).each do |mb|
    puts "   LP #{mb[:lp_id]}: #{mb[:signed_id]} #{mb[:error]}"
  end
  puts "   ... and #{missing_blobs.count - 10} more" if missing_blobs.count > 10
end

# Check if there are orphaned blobs (exist in DB but file missing from storage)
puts "\n🔍 Checking for blobs with missing files in storage..."
orphaned_count = 0
ActiveStorage::Blob.find_each do |blob|
  begin
    unless blob.service.exist?(blob.key)
      orphaned_count += 1
      puts "   ⚠️ Blob #{blob.id} (#{blob.filename}) - file missing from storage" if orphaned_count <= 5
    end
  rescue => e
    # Storage check failed
  end
end
puts "   Total blobs with missing files: #{orphaned_count}"

# Check localstack status (if in Docker)
if ENV['DOCKER_ENV'] == 'true' || ENV['DOCKER_CONTAINER'] == 'true'
  puts "\n🐳 Docker/Localstack detected"
  puts "   ⚠️ If localstack was restarted, S3 data may be lost!"
  puts "   Suggestion: Add localstack data volume to docker-compose.yml"
end

puts "\n" + "=" * 60
