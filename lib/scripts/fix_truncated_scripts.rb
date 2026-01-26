# Fix truncated JavaScript in AI-generated landing pages
# Run with: rails runner lib/scripts/fix_truncated_scripts.rb

fixed = 0

LandingPage.find_each do |lp|
  next unless lp.html_content.present?
  
  html = lp.html_content
  original = html.dup
  
  # Find and fix incomplete scrollIntoView blocks
  # Pattern: scrollIntoView({ ... block: \n (without closing)
  html = html.gsub(
    /scrollIntoView\(\{\s*behavior:\s*['"]smooth['"],\s*block:\s*\n/m,
    "scrollIntoView({ behavior: 'smooth', block: 'start' });\n"
  )
  
  # Also fix: block:\n    </script> (block value missing)
  html = html.gsub(
    /block:\s*\n\s*<\/script>/m,
    "block: 'start' });\n                }\n            });\n        });\n    </script>"
  )
  
  # Fix incomplete arrow functions ending the file
  # If script tag content ends with { and newlines only, close it
  html = html.gsub(
    /=>\s*\{\s*\n\s*<\/script>/m,
    "=> { /* incomplete */ });\n    </script>"
  )
  
  if html != original
    lp.update_column(:html_content, html)
    puts "Cleaned LP #{lp.id}"
    fixed += 1
  end
end

puts "Cleaned #{fixed} landing pages"
