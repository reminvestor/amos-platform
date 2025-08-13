class ImageAsset < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  has_one_attached :file

  validates :file, presence: true
  validates :source, inclusion: { in: %w[upload ai] }

  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :recent, -> { order(created_at: :desc) }

  def display_title
    title.presence || file&.filename&.to_s || "Image"
  end

  def url
    return nil unless file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(file, only_path: false)
  end
end



