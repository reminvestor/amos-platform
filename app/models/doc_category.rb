# frozen_string_literal: true

class DocCategory < ApplicationRecord
  has_many :doc_pages, dependent: :nullify
  
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  
  before_validation :generate_slug, on: :create
  
  scope :capability_categories, -> { where(capability_docs: true) }
  scope :ordered, -> { order(:position, :name) }
  
  private
  
  def generate_slug
    self.slug ||= name&.parameterize
  end
end
