class WorkflowVariable < ApplicationRecord
  belongs_to :workflow_execution
  belongs_to :source, polymorphic: true, optional: true

  # Validations
  validates :name, presence: true, uniqueness: { scope: :workflow_execution_id }

  # Scopes
  scope :by_name, ->(name) { where(name: name) }
  scope :by_prefix, ->(prefix) { where("name LIKE ?", "#{prefix}%") }
  scope :from_step, ->(step_id) { where("name LIKE ?", "#{step_id}.%") }

  # Callbacks
  before_save :set_data_type

  # Get typed value
  def typed_value
    return nil if value.nil?

    case data_type
    when "integer"
      value.to_i
    when "float"
      value.to_f
    when "boolean"
      ActiveModel::Type::Boolean.new.cast(value)
    when "string"
      value.to_s
    else
      value # Return as-is for array, object, etc.
    end
  end

  # Check if variable is from a specific step
  def from_step?(step_id)
    name.start_with?("#{step_id}.")
  end

  # Get the step this variable came from
  def source_step_id
    name.split(".").first if name.include?(".")
  end

  private

  def set_data_type
    self.data_type ||= detect_data_type(value)
  end

  def detect_data_type(val)
    case val
    when String then "string"
    when Integer then "integer"
    when Float then "float"
    when TrueClass, FalseClass then "boolean"
    when Array then "array"
    when Hash then "object"
    when NilClass then "null"
    else "unknown"
    end
  end
end
