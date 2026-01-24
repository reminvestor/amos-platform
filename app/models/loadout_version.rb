# frozen_string_literal: true

# LoadoutVersion - Tracks changes to loadout prompts and tools
#
# Enables A/B testing of loadout variations and rollback if needed
#
class LoadoutVersion < ApplicationRecord
  belongs_to :agent_plugin
  belongs_to :changed_by, polymorphic: true, optional: true

  validates :version_number, presence: true, uniqueness: { scope: :agent_plugin_id }

  scope :active, -> { where(is_active: true) }
  scope :for_loadout, ->(agent_plugin_id) { where(agent_plugin_id: agent_plugin_id) }

  before_create :set_version_number

  def activate!
    transaction do
      agent_plugin.loadout_versions.update_all(is_active: false)
      update!(is_active: true, activated_at: Time.current)
    end
  end

  def rollback_to!
    activate!
    agent_plugin.update!(
      system_prompt: JSON.parse(system_prompt_snapshot),
      # Tools would need to be re-synced from tools_snapshot
    )
  end

  private

  def set_version_number
    return if version_number.present?
    max = agent_plugin.loadout_versions.maximum(:version_number) || 0
    self.version_number = max + 1
  end
end
