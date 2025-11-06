class DocumentAnnotation < ApplicationRecord
  belongs_to :rag_document
  belongs_to :user
  belongs_to :resolved_by, class_name: 'User', optional: true
  
  validates :content, presence: true
  
  scope :unresolved, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :by_page, ->(page) { where(page_number: page) }
  
  # Mark as resolved
  def resolve!(user)
    update!(
      resolved: true,
      resolved_by: user,
      resolved_at: Time.current
    )
  end
end
