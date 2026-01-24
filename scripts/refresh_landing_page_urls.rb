# Refresh all landing page image URLs to use direct S3 URLs
# Run with: rails runner scripts/refresh_landing_page_urls.rb

class UrlRefresher
  include LandingPageRendering
end

refresher = UrlRefresher.new
count = 0
errors = 0

LandingPage.find_each do |lp|
  next if lp.content.blank?
  
  begin
    original = lp.content
    refreshed = refresher.refresh_signed_urls(lp.content)
    
    if original != refreshed
      lp.update_column(:content, refreshed)
      count += 1
      puts "✅ Refreshed: #{lp.title} (ID: #{lp.id})"
    end
  rescue => e
    errors += 1
    puts "❌ Error on #{lp.id}: #{e.message}"
  end
end

puts "\n" + "=" * 50
puts "Done! Refreshed #{count} landing pages (#{errors} errors)"
