#!/usr/bin/env rails runner
# Fix corrupted CSS styles in landing page HTML content
# Run with: rails runner scripts/fix_corrupted_landing_page_styles.rb

puts "🔍 Scanning landing pages for corrupted CSS styles..."

# Common corruption patterns (broken CSS property names)
CORRUPTION_PATTERNS = [
  # Split property names (e.g., "max-wi" "dth:" becoming separate)
  { pattern: /max-wi\s*dth:/i, replacement: 'max-width:' },
  { pattern: /min-wi\s*dth:/i, replacement: 'min-width:' },
  { pattern: /back\s*ground:/i, replacement: 'background:' },
  { pattern: /pad\s*ding:/i, replacement: 'padding:' },
  { pattern: /mar\s*gin:/i, replacement: 'margin:' },
  { pattern: /bor\s*der:/i, replacement: 'border:' },
  { pattern: /hei\s*ght:/i, replacement: 'height:' },
  { pattern: /wid\s*th:/i, replacement: 'width:' },
  { pattern: /fon\s*t-/i, replacement: 'font-' },
  { pattern: /col\s*or:/i, replacement: 'color:' },
  { pattern: /dis\s*play:/i, replacement: 'display:' },
  { pattern: /pos\s*ition:/i, replacement: 'position:' },
  { pattern: /ali\s*gn-/i, replacement: 'align-' },
  { pattern: /jus\s*tify-/i, replacement: 'justify-' },
  { pattern: /fle\s*x/i, replacement: 'flex' },
  { pattern: /gri\s*d/i, replacement: 'grid' },
  
  # Fix malformed URLs in src/href attributes (spaces in URLs)
  { pattern: /src\s*=\s*"\s+/, replacement: 'src="' },
  { pattern: /href\s*=\s*"\s+/, replacement: 'href="' },
]

fixed_count = 0
total_checked = 0

LandingPage.find_each do |lp|
  total_checked += 1
  next if lp.html_content.blank?
  
  original_html = lp.html_content
  fixed_html = original_html.dup
  
  CORRUPTION_PATTERNS.each do |cp|
    if fixed_html.match?(cp[:pattern])
      puts "  ⚠️ Found corruption in LP #{lp.id} (#{lp.title}): #{cp[:pattern].inspect}"
      fixed_html.gsub!(cp[:pattern], cp[:replacement])
    end
  end
  
  if fixed_html != original_html
    puts "✅ Fixing landing page #{lp.id}: #{lp.title}"
    
    # Create backup before fixing
    lp.create_version_backup("Automated fix for corrupted CSS styles") if lp.respond_to?(:create_version_backup)
    
    lp.update_column(:html_content, fixed_html)
    fixed_count += 1
  end
end

puts ""
puts "=" * 60
puts "📊 Summary:"
puts "   Total landing pages checked: #{total_checked}"
puts "   Landing pages fixed: #{fixed_count}"
puts "=" * 60
