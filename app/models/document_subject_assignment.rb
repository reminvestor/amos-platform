class DocumentSubjectAssignment < ApplicationRecord
  belongs_to :rag_document
  belongs_to :document_subject, counter_cache: :documents_count
  belongs_to :assigned_by, class_name: 'User', optional: true
  
  validates :rag_document_id, uniqueness: { scope: :document_subject_id }
  
  # Callbacks
  after_create :track_assignment
  after_destroy :track_unassignment
  
  private
  
  def track_assignment
    # Could be used for activity tracking
    Rails.logger.info "Document #{rag_document_id} assigned to subject #{document_subject.name}"
  end
  
  def track_unassignment
    Rails.logger.info "Document #{rag_document_id} removed from subject #{document_subject.name}"
  end
end
