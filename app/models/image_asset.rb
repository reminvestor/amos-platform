class ImageAsset < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  has_one_attached :file

  validates :file, presence: true, unless: :placeholder?
  validates :source, inclusion: { in: %w[upload ai placeholder] }

  def placeholder?
    source == "placeholder"
  end

  # Scopes for user-centric asset management
  # User's own private assets (not shared with entity)
  scope :private_to_user, ->(user_id) { where(user_id: user_id, shared_with_entity: false) }
  
  # Assets shared with the entity (visible to all entity members)
  scope :shared_with_entity, ->(entity_id) { where(entity_id: entity_id, shared_with_entity: true) }
  
  # Assets visible to a user: their own private + entity shared
  scope :visible_to_user, ->(user) { 
    where(user_id: user.id)
      .or(where(entity_id: user.entity_id, shared_with_entity: true))
  }
  
  # Legacy scope (deprecated - prefer visible_to_user)
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Check if this asset is shared with the entity
  def shared?
    shared_with_entity?
  end
  
  # Share this asset with the entity
  def share_with_entity!
    update!(shared_with_entity: true)
  end
  
  # Make this asset private to the owner
  def make_private!
    update!(shared_with_entity: false)
  end

  def display_title
    title.presence || file&.filename&.to_s || "Image"
  end

  def url
    if file.attached?
      # Use public S3 URL in production (permanent, no expiration)
      # Falls back to presigned URL if public access not available
      if Rails.env.production? && file.blob.service_name.to_s.include?('amazon')
        public_s3_url
      else
        Rails.application.routes.url_helpers.rails_blob_url(file, only_path: false)
      end
    elsif placeholder?
      placeholder_url
    else
      nil
    end
  end
  
  # Get a public S3 URL (requires bucket to allow public reads)
  # Format: https://bucket-name.s3.region.amazonaws.com/key
  def public_s3_url
    return nil unless file.attached?
    
    blob = file.blob
    bucket = ENV.fetch('AWS_BUCKET', 'amos-labs-production')
    region = ENV.fetch('AWS_REGION', 'us-west-2')
    
    "https://#{bucket}.s3.#{region}.amazonaws.com/#{blob.key}"
  end
  
  # Get a fresh presigned URL (max 7 days for S3)
  def fresh_url(expires_in: 7.days)
    return placeholder_url if placeholder?
    return nil unless file.attached?
    
    if file.blob.service.respond_to?(:url)
      # S3 - use max 7 days (S3 limit)
      capped_expiration = [expires_in, 7.days].min
      file.blob.url(expires_in: capped_expiration)
    else
      # Local storage - rails path
      Rails.application.routes.url_helpers.rails_blob_url(file, only_path: false)
    end
  end

  def placeholder_url
    slot = metadata&.dig("slot") || 1
    # Inline SVG data URI to avoid missing static asset 404s in dev
    colors = {
      1 => "#e9ecef",
      2 => "#f8f9fa",
      3 => "#dee2e6"
    }
    bg = colors[slot.to_i] || "#e9ecef"
    svg = <<~SVG
      <svg xmlns='http://www.w3.org/2000/svg' width='600' height='400'>
        <rect width='100%' height='100%' fill='#{bg}'/>
        <text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle' font-family='Arial, Helvetica, sans-serif' font-size='22' fill='#6c757d'>Placeholder Image #{slot}</text>
      </svg>
    SVG
    "data:image/svg+xml;utf8,#{ERB::Util.url_encode(svg.strip)}"
  end
end
