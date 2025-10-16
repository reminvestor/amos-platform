class ImageGenerationService
  def initialize(model: "dall-e-3")
    @api_key = ENV["OPENAI_API_KEY"]
    @organization_id = ENV["OPENAI_ORG_ID"]
    @model = model
  end

  # description: text prompt
  # size: e.g., "1200x600" or "1024x1024"
  # returns a Tempfile with PNG data
  def generate_image_file(description, size: "1024x1024", quality: "standard")
    client = OpenAI::Client.new(access_token: @api_key, organization_id: @organization_id)
    response = client.images.generate(parameters: { model: @model, prompt: description, size: size, quality: quality, n: 1 })

    url = response.dig("data", 0, "url")
    raise "Image generation failed" if url.blank?

    tempfile = Down.download(url)
    tempfile
  end

  # Generates and stores image into ImageAsset + ActiveStorage
  def generate_and_store!(user:, entity:, title:, description:, size: "1024x1024", quality: "standard", tags: [])
    file = generate_image_file(description, size: size, quality: quality)

    asset = ImageAsset.new(user: user, entity: entity, title: title, description: description, source: "ai", tags: tags)
    asset.file.attach(io: File.open(file.path), filename: sanitized_filename(title, size), content_type: "image/png")
    asset.save!
    asset
  ensure
    file&.close!
  end

  private

  def sanitized_filename(title, size)
    base = title.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-")[0..60].presence || "image"
    "#{base}-#{size}.png"
  end
end
