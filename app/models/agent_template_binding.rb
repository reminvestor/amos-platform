# == Schema Information
#
# Table name: agent_template_bindings
#
#  id                    :bigint           not null, primary key
#  workflow_template_id  :bigint           not null
#  agent_plugin_id       :bigint           not null
#  phase                 :string
#  required              :boolean          default(FALSE)
#  execution_order       :integer          default(0)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
class AgentTemplateBinding < ApplicationRecord
  # Associations
  belongs_to :workflow_template
  belongs_to :agent_plugin

  # Validations
  validates :agent_plugin_id, uniqueness: { scope: [:workflow_template_id, :phase] }
  validates :phase, inclusion: { in: %w[gather_context execute_goal validate_result], allow_blank: true }
  validates :execution_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  scope :for_phase, ->(phase) { where(phase: phase) }
  scope :required, -> { where(required: true) }
  scope :by_execution_order, -> { order(execution_order: :asc) }

  # Instance methods
  def agent_active?
    agent_plugin.status == 'active'
  end

  def validate_binding
    errors.add(:agent_plugin, "must be active") unless agent_active?
    errors.add(:phase, "is not supported by template") unless template_supports_phase?
  end

  private

  def template_supports_phase?
    return true if phase.blank?

    # Check if the workflow template has this phase defined
    # This would need to parse the template's YAML configuration
    true  # Simplified for now
  end
end
