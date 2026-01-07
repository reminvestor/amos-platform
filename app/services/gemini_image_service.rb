# frozen_string_literal: true

# GeminiImageService - Google Gemini Image Generation (Nano Banana)
#
# Supports two models:
#   - gemini-2.5-flash-image (Nano Banana) - Fast, efficient (~$0.039/image)
#   - gemini-3-pro-image-preview (Nano Banana Pro) - High-fidelity, text rendering
#
# All generated images include SynthID watermarking.
#
class GeminiImageService
  include HTTParty
  base_uri "https://generativelanguage.googleapis.com/v1beta"

  MODELS = {
    nano_banana: "gemini-2.5-flash-image",
    nano_banana_pro: "gemini-3-pro-image-preview"
  }.freeze

  ASPECT_RATIOS = {
    square: "1:1",
    landscape: "16:9",
    portrait: "9:16",
    wide: "4:3",
    tall: "3:4"
  }.freeze

  class GenerationError < StandardError; end
  class RateLimitError < StandardError; end
  class SafetyFilterError < StandardError; end

  def initialize(model: :nano_banana)
    @api_key = ENV["GEMINI_API_KEY"]
    raise ArgumentError, "GEMINI_API_KEY environment variable not set" if @api_key.blank?

    @model = MODELS[model.to_sym] || MODELS[:nano_banana]
  end

  # Generate image from text prompt
  #
  # @param prompt [String] Text description of image to generate
  # @param aspect_ratio [Symbol] One of :square, :landscape, :portrait, :wide, :tall
  # @param person_generation [String] "allow_adult" or "dont_allow"
  # @return [Hash] { image_data: base64_string, mime_type: "image/png" }
  #
  def generate(prompt, aspect_ratio: :square, person_generation: "allow_adult")
    response = self.class.post(
      "/models/#{@model}:generateContent",
      query: { key: @api_key },
      headers: { "Content-Type" => "application/json" },
      body: build_request_body(prompt, aspect_ratio, person_generation).to_json
    )

    handle_response(response)
  end

  # Generate image and return as Tempfile (compatible with existing ImageGenerationService)
  #
  # @param prompt [String] Text description
  # @param size [String] Size hint (mapped to aspect ratio)
  # @return [Tempfile] PNG image file
  #
  def generate_image_file(prompt, size: "1024x1024")
    aspect_ratio = size_to_aspect_ratio(size)
    result = generate(prompt, aspect_ratio: aspect_ratio)

    # Decode base64 and write to tempfile
    tempfile = Tempfile.new(["gemini_image", ".png"])
    tempfile.binmode
    tempfile.write(Base64.decode64(result[:image_data]))
    tempfile.rewind
    tempfile
  end

  # Generate and store image into ImageAsset
  #
  def generate_and_store!(user:, entity:, title:, description:, size: "1024x1024", tags: [])
    file = generate_image_file(description, size: size)

    asset = ImageAsset.new(
      user: user,
      entity: entity,
      title: title,
      description: description,
      source: "ai",
      tags: tags + ["gemini_nano_banana"]
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

  # Edit existing image with text instructions
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param instruction [String] Edit instruction
  # @return [Hash] { image_data: base64_string, mime_type: "image/png" }
  #
  def edit(image_data, instruction)
    # Load image if path provided
    if File.exist?(image_data.to_s)
      image_data = Base64.strict_encode64(File.binread(image_data))
    end

    response = self.class.post(
      "/models/#{@model}:generateContent",
      query: { key: @api_key },
      headers: { "Content-Type" => "application/json" },
      body: build_edit_request_body(image_data, instruction).to_json
    )

    handle_response(response)
  end

  # List available models
  def self.available_models
    MODELS.map do |key, model_id|
      {
        key: key,
        model_id: model_id,
        name: key.to_s.titleize,
        description: key == :nano_banana ? "Fast & efficient" : "High-fidelity, best text rendering"
      }
    end
  end

  private

  def build_request_body(prompt, aspect_ratio, _person_generation)
    {
      contents: [
        {
          parts: [
            { text: prompt }
          ]
        }
      ],
      generationConfig: {
        responseModalities: ["TEXT", "IMAGE"],
        imageConfig: {
          aspectRatio: ASPECT_RATIOS[aspect_ratio.to_sym] || "1:1"
        }
      }
    }
  end

  def build_edit_request_body(image_data, instruction)
    {
      contents: [
        {
          parts: [
            {
              inlineData: {
                mimeType: "image/png",
                data: image_data
              }
            },
            { text: instruction }
          ]
        }
      ],
      generationConfig: {
        responseModalities: ["image", "text"]
      },
      safetySettings: default_safety_settings
    }
  end

  def default_safety_settings
    [
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE" }
    ]
  end

  def handle_response(response)
    case response.code
    when 200
      parse_image_response(response.parsed_response)
    when 429
      raise RateLimitError, "Gemini API rate limit exceeded: #{response.body}"
    when 400
      error_message = response.dig("error", "message") || "Bad request"
      if error_message.include?("safety")
        raise SafetyFilterError, "Image generation blocked by safety filters: #{error_message}"
      else
        raise GenerationError, "Gemini API error: #{error_message}"
      end
    else
      raise GenerationError, "Gemini API error (#{response.code}): #{response.body}"
    end
  end

  def parse_image_response(response)
    candidates = response["candidates"] || []
    content = candidates.dig(0, "content", "parts") || []

    # Find the image part in the response
    image_part = content.find { |part| part["inlineData"].present? }

    if image_part.nil?
      # Check for text-only response (might contain error or description)
      text_part = content.find { |part| part["text"].present? }
      raise GenerationError, "No image generated. Response: #{text_part&.dig('text') || 'Unknown error'}"
    end

    {
      image_data: image_part.dig("inlineData", "data"),
      mime_type: image_part.dig("inlineData", "mimeType") || "image/png"
    }
  end

  def size_to_aspect_ratio(size)
    width, height = size.split("x").map(&:to_i)
    return :square if width == height

    ratio = width.to_f / height
    case ratio
    when 1.7..1.8 then :landscape  # 16:9
    when 0.55..0.6 then :portrait  # 9:16
    when 1.3..1.4 then :wide       # 4:3
    when 0.7..0.8 then :tall       # 3:4
    else :square
    end
  end

  def sanitized_filename(title, size)
    base = title.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-")[0..60].presence || "image"
    "#{base}-#{size}-nano-banana.png"
  end
end
