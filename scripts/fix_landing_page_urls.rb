# Fix Landing Page URLs - Convert to Public S3 URLs
# Run with: rails runner scripts/fix_landing_page_urls.rb
# Or paste directly into Rails console

bucket = ENV.fetch('AWS_S3_BUCKET', 'agent-marketing-rag-storage')
region = ENV.fetch('AWS_REGION', 'us-east-1')

puts "🔧 Fixing Landing Page URLs"
puts "   Bucket: #{bucket}"
puts "   Region: #{region}"
puts "=" * 50

fixed_count = 0
error_count = 0

LandingPage.find_each do |lp|
  next if lp.html_content.blank?
  
  html = lp.html_content.dup
  changed = false
  
  # Pattern 1: Match expired S3 presigned URLs (with query params)
  # Example: https://bucket.s3.region.amazonaws.com/key?X-Amz-Algorithm=...
  html.gsub!(%r{https://[^"'\s]+\.s3\.[^"'\s]+\.amazonaws\.com/([^"'\s?]+)\?[^"'\s]+}) do |match|
    key = $1
    changed = true
    "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
  end
  
  # Pattern 2: Match Rails Active Storage redirect URLs
  # Example: /rails/active_storage/blobs/redirect/SIGNED_ID/filename
  html.gsub!(%r{(["']?)(https?://[^/\s"']+)?/rails/active_storage/(blobs|representations)/(redirect|proxy)/([A-Za-z0-9\-_=]+)(?:/[^"'\s>]*)?(["']?)}) do |match|
    open_quote = $1
    signed_id = $5
    close_quote = $6
    
    begin
      blob = ActiveStorage::Blob.find_signed(signed_id)
      if blob
        changed = true
        "#{open_quote}https://#{bucket}.s3.#{region}.amazonaws.com/#{blob.key}#{close_quote}"
      else
        match
      end
    rescue => e
      puts "   ⚠️  Could not find blob: #{signed_id[0..20]}..."
      match
    end
  end
  
  if changed
    begin
      lp.update_column(:html_content, html)
      fixed_count += 1
      puts "✅ Fixed: #{lp.title} (ID: #{lp.id})"
    rescue => e
      error_count += 1
      puts "❌ Error saving #{lp.id}: #{e.message}"
    end
  end
end

puts ""
puts "=" * 50
puts "✅ Done! Fixed #{fixed_count} landing pages (#{error_count} errors)"
