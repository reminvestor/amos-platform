#!/usr/bin/env ruby
# encoding: UTF-8
# Test script to verify theme switching functionality

require 'fileutils'

puts "=" * 80
puts "Theme Switching Test"
puts "=" * 80
puts

# Test 1: Check if theme files exist
puts "Test 1: Checking theme files..."
theme_files = [
  'app/assets/stylesheets/themes.scss',
  'app/javascript/theme_manager.js'
]

all_exist = true
theme_files.each do |file|
  exists = File.exist?(file)
  status = exists ? "✓" : "✗"
  puts "  #{status} #{file}"
  all_exist = false unless exists
end

if all_exist
  puts "  ✓ All theme files exist"
else
  puts "  ✗ Some theme files are missing"
end
puts

# Test 2: Check if themes.scss has both light and dark theme definitions
puts "Test 2: Checking theme definitions in themes.scss..."
themes_content = File.read('app/assets/stylesheets/themes.scss')
has_dark = themes_content.include?('[data-theme="dark"]')
has_light = themes_content.include?('[data-theme="light"]')
has_root = themes_content.include?(':root')

puts "  #{has_root ? '✓' : '✗'} :root selector found"
puts "  #{has_dark ? '✓' : '✗'} [data-theme=\"dark\"] selector found"
puts "  #{has_light ? '✓' : '✗'} [data-theme=\"light\"] selector found"

if has_dark && has_light
  puts "  ✓ Both light and dark themes are defined"
else
  puts "  ✗ Missing theme definitions"
end
puts

# Test 3: Check if CSS variables are defined
puts "Test 3: Checking CSS variable definitions..."
required_vars = [
  '--bg-primary',
  '--bg-card',
  '--text-primary',
  '--text-muted',
  '--border-primary'
]

dark_vars = required_vars.all? { |var| themes_content.include?("#{var}:") && themes_content.scan(/#{Regexp.escape(var)}:/).count >= 2 }
light_vars = themes_content.include?('[data-theme="light"]') && required_vars.all? { |var| themes_content.match?(/#{Regexp.escape(var)}:.*#/m) }

puts "  #{dark_vars ? '✓' : '✗'} Dark theme variables defined"
puts "  #{light_vars ? '✓' : '✗'} Light theme variables defined"

if dark_vars && light_vars
  puts "  ✓ All required CSS variables are defined for both themes"
else
  puts "  ✗ Some CSS variables are missing"
end
puts

# Test 4: Check if ThemeManager is properly exported
puts "Test 4: Checking ThemeManager JavaScript..."
theme_manager_content = File.read('app/javascript/theme_manager.js')
has_class = theme_manager_content.include?('class ThemeManager')
has_export = theme_manager_content.include?('export default ThemeManager')
has_toggle = theme_manager_content.include?('toggleTheme')
has_apply = theme_manager_content.include?('applyTheme')

puts "  #{has_class ? '✓' : '✗'} ThemeManager class found"
puts "  #{has_export ? '✓' : '✗'} ThemeManager exported"
puts "  #{has_toggle ? '✓' : '✗'} toggleTheme method found"
puts "  #{has_apply ? '✓' : '✗'} applyTheme method found"

if has_class && has_export && has_toggle && has_apply
  puts "  ✓ ThemeManager is properly implemented"
else
  puts "  ✗ ThemeManager implementation incomplete"
end
puts

# Test 5: Check if ThemeManager is imported in application.js
puts "Test 5: Checking ThemeManager import..."
app_js_content = File.read('app/javascript/application.js')
has_import = app_js_content.include?("import ThemeManager") || app_js_content.include?("from './theme_manager'")

puts "  #{has_import ? '✓' : '✗'} ThemeManager imported in application.js"

if has_import
  puts "  ✓ ThemeManager is properly imported"
else
  puts "  ✗ ThemeManager not imported"
end
puts

# Test 6: Check for hardcoded colors that should use variables
puts "Test 6: Checking for potential hardcoded colors in key files..."
problematic_colors = {
  '#0A0E1A' => '--bg-primary',
  '#1A1F35' => '--bg-card',
  '#FFFFFF' => '--text-primary',
  '#94A3B8' => '--text-muted',
  '#1E293B' => '--border-primary'
}

# Check a few key canvas files
canvas_files = Dir.glob('app/views/scout/canvas/*.html.erb').first(5)
issues_found = 0

canvas_files.each do |file|
  begin
    content = File.read(file, encoding: 'UTF-8')
    problematic_colors.each do |color, var|
      # Count occurrences but exclude comments and theme definitions
      count = content.scan(/#{Regexp.escape(color)}/i).count
      if count > 0
        # Check if it's in a style attribute (problematic) vs in a comment or theme file
        if content.match?(/style=["'][^"']*#{Regexp.escape(color)}/i)
          issues_found += count
        end
      end
    end
  rescue => e
    # Skip files with encoding issues
    next
  end
end

if issues_found == 0
  puts "  ✓ No hardcoded theme colors found in sample canvas files"
else
  puts "  ⚠ Found #{issues_found} potential hardcoded color(s) in sample files"
  puts "    (This may be acceptable if they're in dynamic Ruby code)"
end
puts

# Summary
puts "=" * 80
puts "Test Summary"
puts "=" * 80

tests_passed = [
  all_exist,
  has_dark && has_light,
  dark_vars && light_vars,
  has_class && has_export && has_toggle && has_apply,
  has_import
].count(true)

total_tests = 5
puts "Tests passed: #{tests_passed}/#{total_tests}"

if tests_passed == total_tests
  puts "✓ All tests passed! Theme system appears to be properly configured."
  exit 0
else
  puts "✗ Some tests failed. Please review the output above."
  exit 1
end

