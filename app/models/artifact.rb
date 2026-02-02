class Artifact < ApplicationRecord
  belongs_to :entity
  belongs_to :user

  validates :name, presence: true
  validates :source, presence: true

  # Returns sample rows as an array of hashes
  # Sample is stored as JSON
  def sample_rows
    return [] unless sample.present?
    sample.is_a?(Array) ? sample : []
  end

  # Build a basic schema from an array of hashes
  def self.infer_schema(rows)
    return {} unless rows.is_a?(Array) && rows.first.is_a?(Hash)
    first = rows.first
    first.keys.index_with do |k|
      v = first[k]
      case v
      when Integer then "integer"
      when Float then "float"
      when TrueClass, FalseClass then "boolean"
      when Hash then "object"
      when Array then "array"
      else "string"
      end
    end
  end
end
