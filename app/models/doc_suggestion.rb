# frozen_string_literal: true

class DocSuggestion < ApplicationRecord
  belongs_to :doc_page, optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true
  
  validates :suggestion_type, presence: true
  validates :content, presence: true
  validates :status, presence: true
  
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :from_amos, -> { where(suggested_by: 'amos') }
  
  def approve!(reviewer)
    transaction do
      update!(
        status: 'approved',
        reviewed_by: reviewer,
        reviewed_at: Time.current
      )
      
      # Apply the suggestion
      if doc_page.present?
        doc_page.update!(content: content, last_edited_by: reviewer)
      else
        # Create new page
        DocPage.create!(
          title: title,
          content: content,
          created_by: reviewer,
          last_edited_by: reviewer
        )
      end
    end
  end
  
  def reject!(reviewer, reason = nil)
    update!(
      status: 'rejected',
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      rationale: [rationale, "Rejection reason: #{reason}"].compact.join("\n\n")
    )
  end
end
