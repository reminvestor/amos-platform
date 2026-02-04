# frozen_string_literal: true

class DocPage < ApplicationRecord
  belongs_to :doc_category, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :last_edited_by, class_name: 'User', optional: true
  
  has_many :revisions, class_name: 'DocPageRevision', dependent: :destroy
  has_many :suggestions, class_name: 'DocSuggestion', dependent: :destroy
  
  has_many :doc_page_relations, dependent: :destroy
  has_many :related_pages, through: :doc_page_relations, source: :related_page
  
  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  
  before_validation :generate_slug, on: :create
  
  scope :published, -> { where(published: true) }
  scope :featured, -> { where(featured: true) }
  scope :recent, -> { order(updated_at: :desc) }
  
  # For AMOS capability queries
  scope :capabilities, -> { joins(:doc_category).where(doc_categories: { capability_docs: true }) }
  
  def to_param
    slug
  end
  
  def increment_view!
    increment!(:view_count)
  end
  
  # Search method
  def self.search(query)
    where("title ILIKE :q OR content ILIKE :q OR summary ILIKE :q OR :q = ANY(keywords)",
          q: "%#{query}%")
  end
  
  private
  
  def generate_slug
    self.slug ||= title&.parameterize
  end
end
