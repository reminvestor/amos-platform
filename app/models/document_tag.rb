class DocumentTag < ApplicationRecord
  belongs_to :entity
  has_many :document_tag_assignments, dependent: :destroy
  has_many :rag_documents, through: :document_tag_assignments
  
  validates :name, presence: true, uniqueness: { scope: [:entity_id, :category] }
  validates :name, length: { minimum: 2, maximum: 100 }
  validates :name, format: { with: /\A[\w\s\-]+\z/, message: "can only contain letters, numbers, spaces, and hyphens" }
  validates :category, inclusion: { in: %w[topic type status priority custom], allow_nil: true }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, allow_blank: true }
  
  before_validation :normalize_name
  before_validation :set_default_category
  before_save :set_default_color
  
  CATEGORIES = {
    topic: { icon: 'tag', color: '#6366F1' },
    type: { icon: 'file-type', color: '#8B5CF6' },
    status: { icon: 'check-circle', color: '#10B981' },
    priority: { icon: 'alert-circle', color: '#F59E0B' },
    custom: { icon: 'hash', color: '#6B7280' }
  }.freeze
  
  scope :popular, -> { order(usage_count: :desc) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :recent, -> { order(created_at: :desc) }
  scope :alphabetical, -> { order(:name) }
  
  # Increment usage count when assigned
  def increment_usage!
    increment!(:usage_count)
  end
  
  # Decrement usage count when unassigned
  def decrement_usage!
    decrement!(:usage_count) if usage_count > 0
  end
  
  # Get category info
  def category_info
    CATEGORIES[category&.to_sym] || CATEGORIES[:custom]
  end
  
  # Display icon
  def display_icon
    category_info[:icon]
  end
  
  # Display color
  def display_color
    color.presence || category_info[:color]
  end
  
  # Search tags
  def self.search(query)
    return none if query.blank?
    
    where("name ILIKE ?", "%#{query}%").alphabetical
  end
  
  # Suggest tags based on document content
  def self.suggest_for_document(document, limit: 5)
    return [] if document.blank?
    
    # Get existing tags used with similar documents
    similar_docs = document.rag_store
                          .rag_documents
                          .joins(:document_tags)
                          .where.not(id: document.id)
                          .distinct
    
    # Find tags commonly used with similar content
    suggested_tags = DocumentTag
      .joins(:rag_documents)
      .where(rag_documents: { id: similar_docs.select(:id) })
      .group(:id)
      .order('COUNT(document_tag_assignments.id) DESC')
      .limit(limit)
    
    suggested_tags.to_a
  end
  
  # Merge with another tag
  def merge_into(other_tag)
    return false if other_tag.entity_id != entity_id
    
    transaction do
      # Move all assignments to the other tag
      document_tag_assignments.find_each do |assignment|
        # Check if document already has the target tag
        unless DocumentTagAssignment.exists?(
          rag_document_id: assignment.rag_document_id,
          document_tag_id: other_tag.id
        )
          assignment.update!(document_tag_id: other_tag.id)
        else
          assignment.destroy!
        end
      end
      
      # Update usage count
      other_tag.update!(usage_count: other_tag.document_tag_assignments.count)
      
      # Delete this tag
      destroy!
    end
    
    true
  end
  
  # Bulk create tags
  def self.create_from_list(entity, tag_names, category = 'custom')
    tag_names.map do |name|
      next if name.blank?
      
      find_or_create_by(
        entity: entity,
        name: name.strip.downcase,
        category: category
      )
    end.compact
  end
  
  private
  
  def normalize_name
    self.name = name&.strip&.downcase
  end
  
  def set_default_category
    self.category ||= 'custom'
  end
  
  def set_default_color
    return if color.present?
    
    # Generate a color based on the category
    self.color = category_info[:color]
  end
end
