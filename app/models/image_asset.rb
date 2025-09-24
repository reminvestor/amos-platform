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
    "/assets/placeholder-#{slot}.jpg"
  end
end



