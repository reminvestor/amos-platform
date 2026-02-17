# == Schema Information
#
# Table name: agent_tools
#
#  id               :bigint           not null, primary key
#  agent_plugin_id  :bigint           not null
#  tool_name        :string           not null
#  required         :boolean          default(FALSE)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class AgentTool < ApplicationRecord
  # Associations
  belongs_to :agent_plugin

  # Validations
  validates :tool_name, presence: true, uniqueness: { scope: :agent_plugin_id }
  validate :validate_tool_exists

  # Scopes
  scope :required, -> { where(required: true) }
  scope :optional, -> { where(required: false) }

  # Instance methods
  def tool_definition
    Tools::ToolCatalog.instance.get_tool_definition(tool_name)
  end

  def tool_available?
    Tools::ToolCatalog.instance.tool_exists?(tool_name)
  end

  private

  def validate_tool_exists
    return if tool_name.blank?

    unless Tools::ToolCatalog.instance.tool_exists?(tool_name)
      # Log a warning but don't block creation — tools may be dynamic,
      # entity-scoped, or registered in V3::ToolRegistry
      Rails.logger.warn "[AgentTool] Tool '#{tool_name}' not found in ToolCatalog (may be dynamic or V3 tool)"
    end
  rescue => e
    # If ToolCatalog isn't available (e.g., during migrations), skip validation
    Rails.logger.warn "Could not validate tool existence: #{e.message}"
  end
end
