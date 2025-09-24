class ImageAsset < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  has_one_attached :file

  validates :file, presence: true, unless: :placeholder?
  validates :source, inclusion: { in: %w[upload ai placeholder] }
  
  def placeholder?
    source == 'placeholder'
  end

  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :recent, -> { order(created_at: :desc) }

  def display_title
    title.presence || file&.filename&.to_s || "Image"
  end

  def url
    if file.attached?
      Rails.application.routes.url_helpers.rails_blob_url(file, only_path: false)
    elsif placeholder?
      placeholder_url
    else
      nil
    end
  end
  
  def placeholder_url
    slot = metadata&.dig('slot') || 1
    # Inline SVG data URI to avoid missing static asset 404s in dev
    colors = {
      1 => '#e9ecef',
      2 => '#f8f9fa',
      3 => '#dee2e6'
    }
    bg = colors[slot.to_i] || '#e9ecef'
    svg = <<~SVG
      <svg xmlns='http://www.w3.org/2000/svg' width='600' height='400'>
        <rect width='100%' height='100%' fill='#{bg}'/>
        <text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle' font-family='Arial, Helvetica, sans-serif' font-size='22' fill='#6c757d'>Placeholder Image #{slot}</text>
      </svg>
    SVG
    "data:image/svg+xml;utf8,#{ERB::Util.url_encode(svg.strip)}"
  end
end



