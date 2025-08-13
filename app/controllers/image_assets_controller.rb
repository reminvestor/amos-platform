class ImageAssetsController < ApplicationController
  include EntityScoped

  before_action :authenticate_user!
  before_action :set_image_asset, only: [:show, :destroy]

  def index
    @image_assets = ImageAsset.by_entity(current_entity.id).recent
    respond_to do |format|
      format.html
      format.json do
        render json: {
          images: @image_assets.map { |a| serialize_asset(a) }
        }
      end
    end
  end

  def new
    @image_asset = ImageAsset.new
  end

  def create
    @image_asset = ImageAsset.new(image_asset_params)
    @image_asset.user_id = current_user.id
    @image_asset.entity_id = current_entity.id
    @image_asset.source ||= 'upload'

    respond_to do |format|
      if @image_asset.save
        format.html { redirect_to image_assets_path, notice: 'Image uploaded successfully.' }
        format.json { render json: { success: true, image: serialize_asset(@image_asset) } }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { error: @image_asset.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  # POST /image_assets/generate (JSON only)
  # Params: prompt, size (e.g. "1200x600"), title(optional), tags(optional array)
  def generate
    prompt = params[:prompt].to_s.strip
    requested_size = params[:size].presence || '1024x1024'
    title = params[:title].presence || "AI Image"
    tags = Array(params[:tags]).map(&:to_s)

    if prompt.blank?
      render json: { error: 'prompt is required' }, status: :unprocessable_entity and return
    end

    begin
      # Sanitize size to OpenAI-supported values
      allowed_sizes = %w[1024x1024 1024x1792 1792x1024]
      size = if allowed_sizes.include?(requested_size)
        requested_size
      else
        # Pick closest by aspect ratio
        if requested_size.to_s =~ /\A(\d+)x(\d+)\z/
          w = $1.to_i; h = $2.to_i
          if w > h
            '1792x1024'
          elsif h > w
            '1024x1792'
          else
            '1024x1024'
          end
        else
          '1024x1024'
        end
      end

      asset = ImageGenerationService.new.generate_and_store!(
        user: current_user,
        entity: current_entity,
        title: title,
        description: prompt,
        size: size,
        tags: tags
      )
      render json: { success: true, image: serialize_asset(asset) }
    rescue => e
      Rails.logger.error("AI image generation failed: #{e.message}")
      render json: { error: 'Image generation failed' }, status: :internal_server_error
    end
  end

  def show
  end

  def destroy
    @image_asset.destroy
    redirect_to image_assets_path, notice: 'Image removed.'
  end

  private

  def set_image_asset
    @image_asset = ImageAsset.by_entity(current_entity.id).find(params[:id])
  end

  def image_asset_params
    params.require(:image_asset).permit(:title, :description, :file, :source, tags: [])
  end

  def serialize_asset(asset)
    blob = asset.file if asset.file.attached?
    {
      id: asset.id,
      title: asset.display_title,
      source: asset.source,
      url: (blob ? rails_blob_url(blob) : nil),
      # Avoid eager variant processing on dev macOS to prevent fork-related crashes
      thumb_url: (blob ? rails_blob_url(blob) : nil),
      created_at: asset.created_at.iso8601
    }
  end
end


