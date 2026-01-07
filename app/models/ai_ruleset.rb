# AI Ruleset - Defines behavioral constraints for Scout AI
#
# Rulesets are injected into the system prompt to control AI behavior.
# Global rulesets (entity_id: nil) apply to all entities.
# Entity-specific rulesets apply only to that entity.
#
# Categories:
#   - safety: Security and data protection rules
#   - tone: Communication style and language rules
#   - compliance: Regulatory and legal compliance rules
#   - domain: Industry-specific best practices
#   - custom: User-defined rules
#
class AiRuleset < ApplicationRecord
  belongs_to :entity, optional: true

  CATEGORIES = %w[safety tone compliance domain custom].freeze

  validates :name, presence: true, length: { maximum: 100 }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :rules, presence: true
  validate :rules_must_be_array_of_strings

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :global, -> { where(entity_id: nil) }
  scope :system_presets, -> { where(is_system: true) }
  scope :custom_rules, -> { where(is_system: false) }
  scope :for_entity, ->(entity) { where(entity_id: [nil, entity&.id]) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :by_category, ->(category) { where(category: category) }

  # Prevent deletion of system presets
  before_destroy :prevent_system_preset_deletion

  # Format rules as numbered list for prompt injection
  def to_prompt
    return "" if rules.blank?
    rules.map.with_index(1) { |rule, i| "#{i}. #{rule}" }.join("\n")
  end

  # Human-readable scope description
  def scope_description
    entity_id.nil? ? "All Entities (Global)" : entity&.name || "Entity ##{entity_id}"
  end

  # Check if this ruleset is global
  def global?
    entity_id.nil?
  end

  private

  def rules_must_be_array_of_strings
    unless rules.is_a?(Array) && rules.all? { |r| r.is_a?(String) }
      errors.add(:rules, "must be an array of strings")
    end

    if rules.is_a?(Array) && rules.any?(&:blank?)
      errors.add(:rules, "cannot contain empty strings")
    end
  end

  def prevent_system_preset_deletion
    if is_system?
      errors.add(:base, "System presets cannot be deleted")
      throw :abort
    end
  end
end
