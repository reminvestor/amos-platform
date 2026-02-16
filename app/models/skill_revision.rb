# frozen_string_literal: true

# SkillRevision - Version history for SystemSkill changes
#
# Tracks every change to a skill's content, whether by:
# - AMOS evolution (autonomous improvement)
# - Admin manual edit
# - User upload
#
# change_source values:
#   - evolution: AMOS self-improved based on execution data
#   - admin: Admin manually edited
#   - seed: Initial seed from hardcoded defaults
#   - revert: Reverted to a previous version
#
class SkillRevision < ApplicationRecord
  belongs_to :system_skill
  belongs_to :reviewed_by, class_name: 'User', optional: true

  validates :version, presence: true, uniqueness: { scope: :system_skill_id }
  validates :content, presence: true
  validates :change_source, presence: true, inclusion: { in: %w[evolution admin seed revert custom] }
  validates :status, presence: true, inclusion: { in: %w[applied pending rejected] }

  scope :applied, -> { where(status: 'applied') }
  scope :pending, -> { where(status: 'pending') }
  scope :by_evolution, -> { where(change_source: 'evolution') }
  scope :recent, -> { order(created_at: :desc) }

  def content_diff
    return nil unless previous_content.present?

    {
      added_lines: (content.lines - previous_content.lines).count,
      removed_lines: (previous_content.lines - content.lines).count,
      total_before: previous_content.lines.count,
      total_after: content.lines.count
    }
  end
end
