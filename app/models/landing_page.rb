class LandingPage < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :entity
  belongs_to :campaign, optional: true
  
  # ActionText Rich Content
  has_many :rich_text_sections, dependent: :destroy
  has_many :landing_page_chat_messages, dependent: :destroy
  has_many :landing_page_versions, dependent: :destroy
  
  # Active Storage
  has_one_attached :hero_image
  
  # Validations
  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
  validates :status, inclusion: { in: %w[draft published archived] }
  
  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && title.present? }
  before_save :set_published_at, if: -> { published_changed? && published? }
  
  # Scopes
  scope :published, -> { where(published: true) }
  scope :drafts, -> { where(published: false, status: 'draft') }
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  
  # Get full URL for the landing page
  def full_url(base_url = nil)
    if custom_domain.present?
      "https://#{custom_domain}"
    elsif base_url.present?
      "#{base_url}/#{slug}"
    else
      "/landing/#{slug}"
    end
  end
  
  # Add meta tags based on AI-generated content
  def generate_meta_tags
    return if ai_settings.blank?
    
    self.meta_description ||= ai_settings.dig('seo', 'description')
    self.meta_keywords ||= ai_settings.dig('seo', 'keywords')
  end
  
  # Generate a preview of the landing page
  def preview_data
    {
      title: title,
      headline: headline,
      subheadline: subheadline,
      cta_text: cta_text,
      image_url: hero_image_url,
      content: content,
      colors: {
        primary: primary_color || '#0d6efd',
        secondary: secondary_color || '#6c757d'
      },
      font: font_family || 'Arial, sans-serif',
      updated_at: updated_at
    }
  end
  
  # Convert content JSON to rich text sections and vice versa
  def convert_to_rich_text
    return if content.blank?
    
    content.each_with_index do |section, index|
      rich_text_sections.create(
        title: section['title'],
        content: section['content'],
        section_type: section['type'] || 'text',
        section_index: index,
        image_url: section['image_url']
      )
    end
  end
  
  def sync_content_from_rich_text
    self.content = rich_text_sections.order(:section_index).map do |section|
      {
        title: section.title,
        content: section.content.to_s,
        type: section.section_type,
        section_index: section.section_index,
        image_url: section.image_url
      }
    end
  end
  
  # Get hero image URL (either from attachment or stored URL)
  def hero_image_url
    if hero_image.attached?
      Rails.application.routes.url_helpers.rails_blob_url(hero_image, only_path: true)
    else
      image_url
    end
  end
  
  private
  
  def generate_slug
    base_slug = title.parameterize
    self.slug = base_slug
    
    # Check for uniqueness
    counter = 1
    while LandingPage.where(slug: slug).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end
  
  def set_published_at
    self.published_at = Time.current if published_at.blank?
  end
end 