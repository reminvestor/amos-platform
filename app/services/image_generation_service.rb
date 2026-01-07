# frozen_string_literal: true

# ImageGenerationService - Unified interface for AI image generation
#
# Supports multiple providers:
#   - :openai (DALL-E 3) - Default, established quality
#   - :gemini (Nano Banana) - Google's fast image gen (~$0.039/image)
#   - :gemini_pro (Nano Banana Pro) - High-fidelity, text rendering
#
class ImageGenerationService
  PROVIDERS = {
    openai: { name: "DALL-E 3", model: "dall-e-3" },
    gemini: { name: "Nano Banana", model: :nano_banana },
    gemini_pro: { name: "Nano Banana Pro", model: :nano_banana_pro }
  }.freeze

  attr_reader :provider

  def initialize(provider: :openai, model: nil)
    @provider = provider.to_sym
    @model = model

    validate_provider!
  end

  # Generate image from text prompt, returns Tempfile
  #
  # @param description [String] Text prompt
  # @param size [String] Size (e.g., "1024x1024", "1200x600")
  # @param quality [String] Quality level (OpenAI only: "standard" or "hd")
  # @return [Tempfile] PNG image file
  #
  def generate_image_file(description, size: "1024x1024", quality: "standard")
    case @provider
    when :openai
      generate_with_openai(description, size: size, quality: quality)
    when :gemini, :gemini_pro
      generate_with_gemini(description, size: size)
    else
      raise ArgumentError, "Unknown provider: #{@provider}"
    end
  end

  # Generate and store image into ImageAsset + ActiveStorage
  #
  def generate_and_store!(user:, entity:, title:, description:, size: "1024x1024", quality: "standard", tags: [])
    file = generate_image_file(description, size: size, quality: quality)

    asset = ImageAsset.new(
      user: user,
      entity: entity,
      title: title,
      description: description,
      source: source_name,
      tags: tags
    )
    asset.file.attach(
      io: File.open(file.path),
      filename: sanitized_filename(title, size),
      content_type: "image/png"
    )
    asset.save!
    asset
  ensure
    file&.close!
  end

  # Edit existing image (Gemini only)
  #
  def edit_image(image_path_or_data, instruction)
    raise NotImplementedError, "Image editing only supported with Gemini" unless gemini_provider?

    gemini_service.edit(image_path_or_data, instruction)
  end

  # List available providers for UI
  def self.available_providers
    providers = []

    # OpenAI always available if key present
    if ENV["OPENAI_API_KEY"].present?
      providers << {
        key: :openai,
        name: "DALL-E 3",
        description: "OpenAI's established image model",
        available: true
      }
    end

    # Gemini if key present
    if ENV["GEMINI_API_KEY"].present?
      providers << {
        key: :gemini,
        name: "Nano Banana",
        description: "Google Gemini - Fast & efficient (~$0.039/image)",
        available: true
      }
      providers << {
        key: :gemini_pro,
        name: "Nano Banana Pro",
        description: "Google Gemini Pro - High-fidelity, best text rendering",
        available: true
      }
    end

    providers
  end

  private

  def validate_provider!
    unless PROVIDERS.key?(@provider)
      raise ArgumentError, "Unknown provider: #{@provider}. Valid: #{PROVIDERS.keys.join(', ')}"
    end

    case @provider
    when :openai
      raise ArgumentError, "OPENAI_API_KEY not configured" if ENV["OPENAI_API_KEY"].blank?
    when :gemini, :gemini_pro
      raise ArgumentError, "GEMINI_API_KEY not configured" if ENV["GEMINI_API_KEY"].blank?
    end
  end

  def generate_with_openai(description, size:, quality:)
    client = OpenAI::Client.new(
      access_token: ENV["OPENAI_API_KEY"],
      organization_id: ENV["OPENAI_ORG_ID"]
    )

    model = @model || "dall-e-3"
    response = client.images.generate(
      parameters: { model: model, prompt: description, size: size, quality: quality, n: 1 }
    )

    url = response.dig("data", 0, "url")
    raise "DALL-E image generation failed" if url.blank?

    Down.download(url)
  end

  def generate_with_gemini(description, size:)
    gemini_service.generate_image_file(description, size: size)
  end

  def gemini_service
    @gemini_service ||= GeminiImageService.new(model: PROVIDERS[@provider][:model])
  end

  def gemini_provider?
    [:gemini, :gemini_pro].include?(@provider)
  end

  def source_name
    # All AI providers use "ai" as source - specific provider is stored in tags
    "ai"
  end

  def sanitized_filename(title, size)
    base = title.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-")[0..60].presence || "image"
    suffix = gemini_provider? ? "-nano-banana" : "-dalle"
    "#{base}-#{size}#{suffix}.png"
  end
end
