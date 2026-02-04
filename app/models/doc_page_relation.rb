# frozen_string_literal: true

class DocPageRelation < ApplicationRecord
  belongs_to :doc_page
  belongs_to :related_page, class_name: 'DocPage'
  
  validates :relation_type, presence: true
  validates :doc_page_id, uniqueness: { scope: :related_page_id }
  
  RELATION_TYPES = %w[related prerequisite see_also parent child].freeze
  
  validates :relation_type, inclusion: { in: RELATION_TYPES }
end
