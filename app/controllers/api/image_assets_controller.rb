module Api
  class ImageAssetsController < Api::BaseController
    before_action :set_image_asset, only: [:show, :destroy, :toggle_sharing]

    # GET /api/image_assets
    def index
      @image_assets = current_entity.image_assets
                                    .visible_to_user(current_user)
                                    .recent
                                    .limit(100)
      
      render json: {
        image_assets: @image_assets.map { |img| image_asset_json(img) }
      }
    end

    # GET /api/image_assets/:id
    def show
      render json: { image_asset: image_asset_json(@image_asset) }
    end

    # POST /api/image_assets
    def create
      @image_asset = current_entity.image_assets.build(
        user: current_user,
        source: params[:source] || 'upload',
        title: params[:title] || params[:file]&.original_filename,
        shared_with_entity: params[:shared_with_entity] || false
      )
      
      if params[:file].present?
        @image_asset.file.attach(params[:file])
      end
      
      if @image_asset.save
        render json: { 
          success: true, 
          image_asset: image_asset_json(@image_asset) 
        }, status: :created
      else
        render json: { 
          success: false, 
          errors: @image_asset.errors.full_messages 
        }, status: :unprocessable_entity
      end
    end

    # DELETE /api/image_assets/:id
    def destroy
      if @image_asset.user_id == current_user.id || current_user.admin?
        @image_asset.destroy
        render json: { success: true }
      else
        render json: { success: false, error: 'Not authorized' }, status: :forbidden
      end
    end

    # POST /api/image_assets/:id/toggle_sharing
    def toggle_sharing
      if @image_asset.user_id == current_user.id
        @image_asset.update(shared_with_entity: !@image_asset.shared_with_entity)
        render json: { 
          success: true, 
          shared: @image_asset.shared_with_entity 
        }
      else
        render json: { success: false, error: 'Not authorized' }, status: :forbidden
      end
    end

    # POST /api/image_assets/generate
    def generate
      # Placeholder for AI image generation
      prompt = params[:prompt]
      
      # TODO: Integrate with image generation service
      render json: { 
        success: false, 
        error: 'AI image generation coming soon' 
      }, status: :not_implemented
    end

    private

    def set_image_asset
      @image_asset = current_entity.image_assets.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Image not found' }, status: :not_found
    end

    def image_asset_json(img)
      {
        id: img.id,
        title: img.display_title,
        source: img.source,
        url: img.url,
        shared: img.shared?,
        created_at: img.created_at.iso8601,
        thumbnail_url: img.file.attached? ? 
          Rails.application.routes.url_helpers.rails_representation_url(
            img.file.variant(resize_to_limit: [300, 300]),
            only_path: true
          ) : img.placeholder_url
      }
    end
  end
end

