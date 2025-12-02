# == Schema Information
#
# Table name: agent_capabilities
#
#  id                    :bigint           not null, primary key
#  agent_plugin_id       :bigint           not null
#  capability_name       :string           not null
#  contract_schema       :jsonb            default({})
#  implementation_notes  :text
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
class AgentCapability < ApplicationRecord
  # Associations
  belongs_to :agent_plugin

  # Validations
  validates :capability_name, presence: true, uniqueness: { scope: :agent_plugin_id }
  validates :contract_schema, presence: true
  validate :validate_contract_schema_format

  # Scopes
  scope :by_capability, ->(name) { where(capability_name: name) }

  # Instance methods
  def has_valid_contract?
    contract_schema.is_a?(Hash) &&
      contract_schema.key?('inputs') &&
      contract_schema.key?('outputs')
  end

  def input_schema
    contract_schema.dig('inputs') || []
  end

  def output_schema
    contract_schema.dig('outputs') || []
  end

  private

  def validate_contract_schema_format
    return if contract_schema.blank?

    unless contract_schema.is_a?(Hash)
      errors.add(:contract_schema, "must be a valid JSON object")
      return
    end

    # Basic structure validation
    unless contract_schema.key?('inputs') && contract_schema.key?('outputs')
      errors.add(:contract_schema, "must define both 'inputs' and 'outputs'")
    end

    # Validate inputs/outputs are arrays
    unless contract_schema['inputs'].is_a?(Array) || contract_schema['inputs'].is_a?(Hash)
      errors.add(:contract_schema, "'inputs' must be an array or object")
    end

    unless contract_schema['outputs'].is_a?(Array) || contract_schema['outputs'].is_a?(Hash)
      errors.add(:contract_schema, "'outputs' must be an array or object")
    end
  rescue => e
    errors.add(:contract_schema, "Invalid JSON: #{e.message}")
  end
end
