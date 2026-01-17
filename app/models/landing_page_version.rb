# LandingPageVersion
#
# Stores version history for landing pages. The `content` field is a JSONB
# that stores the html_content at the time of the backup.
#
class LandingPageVersion < ApplicationRecord
  belongs_to :landing_page

  validates :landing_page_id, presence: true

  # Create a version from a landing page (new style - html_content based)
  def self.create_from_landing_page(landing_page, ai_applied: true, description: nil)
    create(
      landing_page: landing_page,
      content: { html_content: landing_page.html_content },
      ai_applied: ai_applied,
      description: description || (ai_applied ? "AI-generated update" : "Manual update")
    )
  end

  # Restore this version to the landing page
  def restore
    # Get html_content from the content JSONB
    html_to_restore = content&.dig('html_content') || content&.dig(:html_content)
    
    unless html_to_restore.present?
      Rails.logger.warn "Version #{id} has no html_content to restore"
      return false
    end

    # Create backup of current state first
    landing_page.create_version_backup("Before restore to version from #{created_at.strftime('%Y-%m-%d %H:%M')}")

    # Restore the html_content
    result = landing_page.update(html_content: html_to_restore)

    if result
      # Create a new version that represents the rollback
      LandingPageVersion.create(
        landing_page: landing_page,
        content: { html_content: html_to_restore },
        ai_applied: false,
        description: "Restored from version: #{created_at.strftime('%Y-%m-%d %H:%M')}"
      )
    end

    result
  end
end
