# frozen_string_literal: true

namespace :gemini do
  desc "Check Gemini API configuration"
  task check: :environment do
    puts "🍌 Nano Banana (Gemini Image) Configuration Check"
    puts "=" * 50

    if ENV["GEMINI_API_KEY"].present?
      puts "✅ GEMINI_API_KEY is configured"
      key_preview = "#{ENV['GEMINI_API_KEY'][0..7]}...#{ENV['GEMINI_API_KEY'][-4..]}"
      puts "   Key: #{key_preview}"
    else
      puts "❌ GEMINI_API_KEY is NOT configured"
      puts "   Get your key at: https://aistudio.google.com/apikey"
      exit 1
    end

    puts "\n📋 Available Models:"
    GeminiImageService::MODELS.each do |key, model_id|
      puts "   - #{key}: #{model_id}"
    end

    puts "\n🎨 Aspect Ratios:"
    GeminiImageService::ASPECT_RATIOS.each do |key, ratio|
      puts "   - #{key}: #{ratio}"
    end

    puts "\n✅ Configuration looks good!"
  end

  desc "Test Gemini image generation with a simple prompt"
  task :test, [:prompt] => :environment do |_t, args|
    prompt = args[:prompt] || "A cute robot holding a banana, digital art style"

    puts "🍌 Testing Nano Banana Image Generation"
    puts "=" * 50
    puts "Prompt: #{prompt}"
    puts ""

    begin
      service = GeminiImageService.new(model: :nano_banana)
      puts "⏳ Generating image..."

      result = service.generate(prompt, aspect_ratio: :square)

      puts "✅ Image generated successfully!"
      puts "   MIME Type: #{result[:mime_type]}"
      puts "   Data size: #{result[:image_data].length} bytes (base64)"

      # Save to temp file for preview
      filename = "/tmp/nano_banana_test_#{Time.now.to_i}.png"
      File.binwrite(filename, Base64.decode64(result[:image_data]))
      puts "   Saved to: #{filename}"
      puts ""
      puts "🖼️  Open with: open #{filename}"
    rescue GeminiImageService::GenerationError => e
      puts "❌ Generation failed: #{e.message}"
    rescue GeminiImageService::SafetyFilterError => e
      puts "⚠️  Blocked by safety filter: #{e.message}"
    rescue GeminiImageService::RateLimitError => e
      puts "⏱️  Rate limited: #{e.message}"
    rescue StandardError => e
      puts "❌ Error: #{e.class} - #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end

  desc "Test image editing with Gemini"
  task :edit, [:image_path, :instruction] => :environment do |_t, args|
    unless args[:image_path] && args[:instruction]
      puts "Usage: rails gemini:edit[/path/to/image.png,'make it more colorful']"
      exit 1
    end

    puts "🍌 Testing Nano Banana Image Editing"
    puts "=" * 50
    puts "Image: #{args[:image_path]}"
    puts "Instruction: #{args[:instruction]}"
    puts ""

    begin
      service = GeminiImageService.new(model: :nano_banana)
      puts "⏳ Editing image..."

      result = service.edit(args[:image_path], args[:instruction])

      puts "✅ Image edited successfully!"

      filename = "/tmp/nano_banana_edit_#{Time.now.to_i}.png"
      File.binwrite(filename, Base64.decode64(result[:image_data]))
      puts "   Saved to: #{filename}"
      puts ""
      puts "🖼️  Open with: open #{filename}"
    rescue StandardError => e
      puts "❌ Error: #{e.class} - #{e.message}"
    end
  end

  desc "Compare all available image providers"
  task compare: :environment do
    puts "🎨 Image Generation Provider Comparison"
    puts "=" * 50

    providers = ImageGenerationService.available_providers
    if providers.empty?
      puts "❌ No providers configured!"
      puts "   Set OPENAI_API_KEY and/or GEMINI_API_KEY"
      exit 1
    end

    puts "Available providers:"
    providers.each do |p|
      status = p[:available] ? "✅" : "❌"
      puts "   #{status} #{p[:name]} (#{p[:key]})"
      puts "      #{p[:description]}"
    end
  end
end
