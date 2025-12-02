class DocumentSubject < ApplicationRecord
  belongs_to :entity
  belongs_to :parent, class_name: 'DocumentSubject', optional: true
  has_many :children, class_name: 'DocumentSubject', foreign_key: :parent_id, dependent: :destroy
  has_many :document_subject_assignments, dependent: :destroy
  has_many :rag_documents, through: :document_subject_assignments
  belongs_to :assigned_by, class_name: 'User', optional: true
  
  validates :name, presence: true, uniqueness: { scope: [:entity_id, :parent_id] }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, allow_blank: true }
  
  before_validation :set_default_color
  before_save :update_position
  
  scope :root, -> { where(parent_id: nil) }
  scope :roots, -> { root }  # Alias for convenience
  scope :smart_folders, -> { where(is_smart_folder: true) }
  scope :regular_folders, -> { where(is_smart_folder: false) }
  scope :ordered, -> { order(:position, :name) }
  
  # Counter cache is handled by the association
  
  # Get full path from root
  def full_path
    ancestors.map(&:name).join(' / ') + ' / ' + name
  end
  
  # Get all ancestors
  def ancestors
    parent ? parent.ancestors + [parent] : []
  end
  
  # Get all descendants
  def descendants
    children.flat_map { |child| [child] + child.descendants }
  end
  
  # Check if document matches smart folder rules
  def matches_document?(document)
    return false unless is_smart_folder
    return true if rules.blank?
    
    evaluate_rules(document)
  end
  
  # Move to a new parent
  def move_to(new_parent)
    self.parent = new_parent
    save
  end
  
  # Default icon based on type
  def display_icon
    return icon if icon.present?
    
    if is_smart_folder
      'filter'
    elsif parent_id.nil?
      'folder'
    else
      'folder-open'
    end
  end
  
  # Default color if not set
  def display_color
    color.presence || '#6366F1'
  end
  
  private
  
  def set_default_color
    self.color ||= generate_color_from_name
  end
  
  def generate_color_from_name
    # Generate a consistent color based on the name
    colors = ['#6366F1', '#8B5CF6', '#EC4899', '#10B981', '#F59E0B', '#EF4444', '#3B82F6']
    colors[name.hash % colors.length]
  end
  
  def update_position
    if position.nil? || position.zero?
      max_position = entity.document_subjects
                          .where(parent_id: parent_id)
                          .where.not(id: id)
                          .maximum(:position) || 0
      self.position = max_position + 1
    end
  end
  
  def evaluate_rules(document)
    # Example rules structure:
    # {
    #   "tags": ["contract", "legal"],
    #   "date_range": "last_30_days",
    #   "content_type": ["pdf", "docx"],
    #   "min_size": 1048576
    # }
    
    # Check tags
    if rules['tags'].present?
      required_tags = Array(rules['tags'])
      document_tags = document.document_tags.pluck(:name)
      return false unless (required_tags - document_tags).empty?
    end
    
    # Check date range
    if rules['date_range'].present?
      date_range = parse_date_range(rules['date_range'])
      return false unless date_range.cover?(document.created_at)
    end
    
    # Check content type
    if rules['content_type'].present?
      allowed_types = Array(rules['content_type'])
      return false unless allowed_types.any? { |type| document.content_type&.include?(type) }
    end
    
    # Check file size
    if rules['min_size'].present?
      return false if document.file_size_bytes < rules['min_size'].to_i
    end
    
    if rules['max_size'].present?
      return false if document.file_size_bytes > rules['max_size'].to_i
    end
    
    true
  end
  
  def parse_date_range(range_string)
    case range_string
    when 'today'
      Date.current.beginning_of_day..Date.current.end_of_day
    when 'yesterday'
      1.day.ago.beginning_of_day..1.day.ago.end_of_day
    when 'last_7_days'
      7.days.ago.beginning_of_day..Time.current
    when 'last_30_days'
      30.days.ago.beginning_of_day..Time.current
    when 'last_90_days'
      90.days.ago.beginning_of_day..Time.current
    when 'this_month'
      Date.current.beginning_of_month..Date.current.end_of_month
    when 'last_month'
      1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when 'this_year'
      Date.current.beginning_of_year..Date.current.end_of_year
    else
      # Assume it's a custom range like "2024-01-01..2024-12-31"
      dates = range_string.split('..')
      Date.parse(dates[0])..Date.parse(dates[1])
    end
  end
end
