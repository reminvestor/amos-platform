class PolicyRule < ApplicationRecord
  belongs_to :entity, optional: true  # nil for global rules

  # Validations
  validates :name, presence: true
  validates :resource_type, inclusion: { in: %w[Connection Integration Operation Global Tool] }
  validates :action, inclusion: { in: %w[read write delete execute all] }
  validates :is_active, inclusion: { in: [ true, false ] }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :global, -> { where(entity_id: nil) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_role, ->(role) { where("agent_role = ? OR agent_role IS NULL", role) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  def applies_to?(resource)
    case resource_type
    when "Connection"
      resource.is_a?(Connection) && (resource_id.nil? || resource_id == resource.id.to_s)
    when "Integration"
      integration = resource.is_a?(Integration) ? resource : resource.try(:integration)
      integration && (resource_id.nil? || resource_id == integration.id.to_s)
    when "Operation"
      resource_id.nil? || resource_id == resource.to_s
    when "Tool"
      resource_id.nil? || resource_id == resource.to_s
    when "Global"
      true
    else
      false
    end
  end

  def description
    parts = [ name ]

    if agent_role.present?
      parts << "for #{agent_role} agents"
    end

    if resource_type.present? && resource_id.present?
      parts << "on #{resource_type} #{resource_id}"
    end

    if conditions.present?
      case conditions["type"]
      when "allow_list"
        parts << "allowing: #{conditions['operations']&.join(', ')}"
      when "deny_list"
        parts << "denying: #{conditions['operations']&.join(', ')}"
      when "time_window"
        parts << "during: #{conditions['start']} - #{conditions['end']}"
      when "budget_check"
        parts << "with limits"
      end
    end

    parts.join(" ")
  end

  private

  def set_defaults
    self.is_active = true if is_active.nil?
    self.conditions ||= {}
    self.action ||= "read"
    self.requires_confirmation ||= false
  end
end
