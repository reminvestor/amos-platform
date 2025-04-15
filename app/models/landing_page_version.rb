class LandingPageVersion < ApplicationRecord
  belongs_to :landing_page
  
  validates :landing_page_id, presence: true
  
  # Create a version from a landing page
  def self.create_from_landing_page(landing_page, ai_applied: true, description: nil)
    create(
      landing_page: landing_page,
      content: landing_page.content,
      headline: landing_page.headline,
      subheadline: landing_page.subheadline,
      cta_text: landing_page.cta_text,
      cta_url: landing_page.cta_url,
      primary_color: landing_page.primary_color,
      secondary_color: landing_page.secondary_color,
      font_family: landing_page.font_family,
      ai_applied: ai_applied,
      description: description || (ai_applied ? "AI-generated update" : "Manual update")
    )
  end
  
  # Restore this version to the landing page
  def restore
    landing_page.update(
      content: self.content,
      headline: self.headline,
      subheadline: self.subheadline,
      cta_text: self.cta_text,
      cta_url: self.cta_url,
      primary_color: self.primary_color,
      secondary_color: self.secondary_color,
      font_family: self.font_family
    )
    
    # Create a new version that represents the rollback
    LandingPageVersion.create(
      landing_page: landing_page,
      content: self.content,
      headline: self.headline,
      subheadline: self.subheadline,
      cta_text: self.cta_text,
      cta_url: self.cta_url,
      primary_color: self.primary_color,
      secondary_color: self.secondary_color,
      font_family: self.font_family,
      ai_applied: false,
      description: "Rollback to version from #{self.created_at.strftime('%Y-%m-%d %H:%M')}"
    )
  end
end
