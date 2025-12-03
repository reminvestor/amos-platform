#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# Theme Issues Scanner
# Scans all ERB and SCSS files for hardcoded colors and theme issues

require 'fileutils'

class ThemeIssueScanner
  HEX_COLOR = /#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{3}\b/
  RGB_COLOR = /rgba?\([^)]+\)/
  HARDCODED_DARK = /#0A0E1A|#0F172A|#1A1F35|#1E293B|#252a3d|#1e2433|#2d3548|#3a4158/
  HARDCODED_LIGHT = /#FFFFFF|#F8FAFC|#F1F5F9|#E2E8F0|#CBD5E1|#f8f9fa|#e9ecef|#dee2e6/
  HARDCODED_TEXT = /#94A3B8|#64748B|#9ca3af|#6b7280|#e5e7eb|#E2E8F0/
  
  def initialize
    @issues = []
    @file_count = 0
  end

  def scan_file(file_path)
    return unless File.file?(file_path)
    
    content = File.read(file_path, encoding: 'UTF-8')
    lines = content.lines
    relative_path = file_path.sub(Dir.pwd + '/', '')
    
    lines.each_with_index do |line, index|
      line_num = index + 1
      
      # Skip comments
      next if line.strip.start_with?('//', '/*', '*')
      
      # Check for hardcoded colors in inline styles
      if line.match?(/style=.*#{HEX_COLOR}/i)
        hex_colors = line.scan(HEX_COLOR)
        hex_colors.each do |color|
          severity = determine_severity(color, line)
          @issues << {
            file: relative_path,
            line: line_num,
            type: 'inline_style',
            color: color,
            severity: severity,
            context: line.strip[0..100]
          }
        end
      end
      
      # Check for hardcoded colors in style blocks
      if line.match?(/#{HEX_COLOR}/) && (file_path.end_with?('.erb') || file_path.end_with?('.scss'))
        # Skip if it's a CSS variable or already using var()
        next if line.include?('var(--') || line.include?('--scout-primary') || line.include?('--accent-')
        
        hex_colors = line.scan(HEX_COLOR)
        hex_colors.each do |color|
          # Skip semantic colors that are acceptable
          next if semantic_color?(color)
          
          severity = determine_severity(color, line)
          @issues << {
            file: relative_path,
            line: line_num,
            type: 'hardcoded_color',
            color: color,
            severity: severity,
            context: line.strip[0..100]
          }
        end
      end
    end
    
    @file_count += 1
  end

  def semantic_color?(color)
    # These are semantic colors that are acceptable (status colors, etc.)
    semantic_colors = [
      '#10b981', '#10B981', '#22c55e', '#22C55E', # success green
      '#ef4444', '#EF4444', '#dc2626', '#DC2626', # error red
      '#f59e0b', '#F59E0B', '#fbbf24', '#FBBF24', # warning yellow
      '#3b82f6', '#3B82F6', '#06b6d4', '#06B6D4', # info blue
      '#7C3AED', '#A78BFA', '#6366f1', '#6366F1'  # purple accent
    ]
    semantic_colors.include?(color.upcase) || semantic_colors.include?(color)
  end

  def determine_severity(color, line)
    color_up = color.upcase
    
    # Critical: Hardcoded dark backgrounds/text that break light mode
    if HARDCODED_DARK.match?(color_up) && (line.include?('background') || line.include?('color'))
      return 'CRITICAL'
    end
    
    # High: Hardcoded light colors that break dark mode
    if HARDCODED_LIGHT.match?(color_up) && (line.include?('background') || line.include?('color'))
      return 'HIGH'
    end
    
    # Medium: Hardcoded text colors
    if HARDCODED_TEXT.match?(color_up)
      return 'MEDIUM'
    end
    
    # Low: Other hardcoded colors (might be semantic)
    'LOW'
  end

  def scan_directory(dir)
    Dir.glob("#{dir}/**/*").each do |path|
      next unless File.file?(path)
      next unless path.match?(/\.(erb|scss|css)$/)
      next if path.include?('node_modules')
      next if path.include?('vendor')
      next if path.include?('builds')
      
      scan_file(path)
    end
  end

  def generate_report
    puts "\n" + "="*80
    puts "THEME ISSUES SCAN REPORT"
    puts "="*80
    puts "\nScanned #{@file_count} files"
    puts "Found #{@issues.length} potential issues\n"
    
    # Group by severity
    by_severity = @issues.group_by { |i| i[:severity] }
    
    %w[CRITICAL HIGH MEDIUM LOW].each do |severity|
      issues = by_severity[severity] || []
      next if issues.empty?
      
      puts "\n#{severity} PRIORITY (#{issues.length} issues):"
      puts "-" * 80
      
      # Group by file
      by_file = issues.group_by { |i| i[:file] }
      by_file.sort.each do |file, file_issues|
        puts "\n  📄 #{file} (#{file_issues.length} issues)"
        file_issues.each do |issue|
          puts "     Line #{issue[:line].to_s.rjust(4)}: #{issue[:color]} - #{issue[:type]}"
          puts "            #{issue[:context]}"
        end
      end
    end
    
    # Summary
    puts "\n" + "="*80
    puts "SUMMARY"
    puts "="*80
    puts "Total Issues: #{@issues.length}"
    puts "  CRITICAL: #{by_severity['CRITICAL']&.length || 0}"
    puts "  HIGH:     #{by_severity['HIGH']&.length || 0}"
    puts "  MEDIUM:   #{by_severity['MEDIUM']&.length || 0}"
    puts "  LOW:      #{by_severity['LOW']&.length || 0}"
    puts "\n"
    
    # Files with most issues
    by_file = @issues.group_by { |i| i[:file] }
    top_files = by_file.sort_by { |f, issues| -issues.length }.first(10)
    
    puts "Top 10 Files Needing Attention:"
    puts "-" * 80
    top_files.each do |file, issues|
      puts "  #{file}: #{issues.length} issues"
    end
    puts "\n"
  end
end

# Run the scanner
scanner = ThemeIssueScanner.new

puts "Scanning for theme issues..."
scanner.scan_directory('app/views/scout/canvas')
scanner.scan_directory('app/assets/stylesheets')
scanner.generate_report

