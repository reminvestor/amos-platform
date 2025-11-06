class DocumentTagAssignment < ApplicationRecord
  belongs_to :rag_document
  belongs_to :document_tag
  
  validates :rag_document_id, uniqueness: { scope: :document_tag_id }
  
  # Update usage count on tag
  after_create :increment_tag_usage
  after_destroy :decrement_tag_usage
  
  private
  
  def increment_tag_usage
    document_tag.increment_usage!
  end
  
  def decrement_tag_usage
    document_tag.decrement_usage!
  end
end
