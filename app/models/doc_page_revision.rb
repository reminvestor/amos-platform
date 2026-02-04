# frozen_string_literal: true

class DocPageRevision < ApplicationRecord
  belongs_to :doc_page
  belongs_to :user, optional: true
  
  validates :content, presence: true
  validates :action, presence: true
  
  scope :recent, -> { order(created_at: :desc) }
  
  def editor_name
    if ai_generated_by.present?
      "AMOS (#{ai_generated_by})"
    elsif user.present?
      user.full_name || user.email.split('@').first
    else
      'Unknown'
    end
  end
  
  def content_diff
    # Simple diff - could use a proper diff library
    return nil unless previous_content.present?
    
    {
      additions: content.lines.count - previous_content.lines.count,
      previous_length: previous_content.length,
      new_length: content.length
    }
  end
end
