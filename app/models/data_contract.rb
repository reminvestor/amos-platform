class DataContract < ApplicationRecord
  # Versioned data contracts for analytics ingestion
  
  validates :name, presence: true
  validates :version, presence: true
  validates :entity_type, presence: true
  validates :schema_definition, presence: true
  
  # Composite unique constraint
  validates :name, uniqueness: { scope: :version }
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_entity_type, ->(type) { where(entity_type: type) }
  scope :latest_version, -> { 
    select('DISTINCT ON (name) *')
      .order('name, version DESC')
  }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  # Get latest version of a contract
  def self.latest_for(contract_name)
    where(name: contract_name, is_active: true)
      .order(version: :desc)
      .first
  end
  
  # Validate data against this contract
  def validate_data(data)
    validator = Analytics::ContractValidator.new(self)
    validator.validate(data)
  end
  
  # Check if contract has PII fields
  def has_pii?
    privacy_rules.present? && privacy_rules['pii_fields'].present?
  end
  
  # Get PII fields
  def pii_fields
    privacy_rules&.dig('pii_fields') || []
  end
  
  private
  
  def set_defaults
    self.is_active = true if is_active.nil?
    self.privacy_rules ||= {}
    self.metadata ||= {}
  end
end

