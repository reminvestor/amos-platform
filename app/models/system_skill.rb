# frozen_string_literal: true

# SystemSkill - Database-backed skills that AMOS uses and evolves
#
# Skills are knowledge/expertise content injected into AMOS's context.
# Unlike code changes (which need bounties), skills are pure knowledge
# that AMOS can update directly based on execution data and user feedback.
#
# Types:
#   - integration: API-specific knowledge (Stripe, GoDaddy, etc.)
#   - task: Task-pattern knowledge (debugging, TDD, etc.)
#   - custom: User-uploaded SKILL.md files
#
# Sources:
#   - built-in: Seeded from hardcoded defaults
#   - evolution: Auto-improved by AMOS during Evolution Cycle
#   - admin: Manually edited by an admin
#   - custom: Uploaded by a user
#
class SystemSkill < ApplicationRecord
  belongs_to :entity, optional: true
  has_many :skill_revisions, dependent: :destroy
  has_many :skill_injection_logs, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :content, presence: true
  validates :skill_type, presence: true, inclusion: { in: %w[integration task custom] }
  validates :source, presence: true, inclusion: { in: %w[built-in evolution admin custom] }
  validates :status, presence: true, inclusion: { in: %w[active inactive archived] }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :integration_skills, -> { where(skill_type: 'integration') }
  scope :task_skills, -> { where(skill_type: 'task') }
  scope :custom_skills, -> { where(skill_type: 'custom') }
  scope :global, -> { where(entity_id: nil) }
  scope :for_entity, ->(entity) { where(entity_id: [nil, entity.id]) }
  scope :for_integration, ->(name) { where(integration_name: name) }

  # Find a skill by integration name
  def self.find_integration_skill(integration_name)
    active.for_integration(integration_name).first
  end

  # Find skills matching keywords in a message
  def self.matching_message(message)
    return none if message.blank?

    msg_lower = message.downcase
    active.select do |skill|
      skill.keywords.any? { |kw| msg_lower.include?(kw.downcase) }
    end
  end

  # Update skill content with version tracking
  def evolve!(new_content, source:, reason:, author: nil, details: {})
    return false if new_content.blank? || new_content == content

    transaction do
      # Create revision record
      skill_revisions.create!(
        version: version + 1,
        content: new_content,
        previous_content: content,
        change_source: source,
        change_reason: reason,
        change_details: details,
        author_type: author&.class&.name,
        author_id: author&.id,
        status: 'applied'
      )

      # Update the skill
      update!(
        content: new_content,
        version: version + 1,
        last_evolved_at: Time.current,
        last_evolved_by: source
      )
    end

    true
  end

  # Revert to a specific version
  def revert_to!(target_version)
    revision = skill_revisions.find_by!(version: target_version)

    evolve!(
      revision.content,
      source: 'admin',
      reason: "Reverted to version #{target_version}",
      details: { reverted_from: version, reverted_to: target_version }
    )
  end

  # Record an injection and track the outcome
  def record_injection!(entity:, user:, session_id:, reason:)
    increment!(:injection_count)

    skill_injection_logs.create!(
      entity: entity,
      user: user,
      session_id: session_id,
      injection_reason: reason
    )
  end

  # Record whether the injection led to positive or negative outcomes
  def record_outcome!(positive:)
    if positive
      increment!(:positive_outcomes)
    else
      increment!(:negative_outcomes)
    end

    recalculate_effectiveness!
  end

  # Effectiveness = positive / (positive + negative), with Bayesian smoothing
  def recalculate_effectiveness!
    total = positive_outcomes + negative_outcomes
    return update!(effectiveness_score: nil) if total < 5

    # Wilson score lower bound (more conservative than simple ratio)
    z = 1.96 # 95% confidence
    n = total.to_f
    p_hat = positive_outcomes.to_f / n
    score = (p_hat + z * z / (2 * n) - z * Math.sqrt((p_hat * (1 - p_hat) + z * z / (4 * n)) / n)) / (1 + z * z / n)

    update!(effectiveness_score: (score * 100).round(1))
  end

  # Human-readable effectiveness
  def effectiveness_label
    return 'insufficient data' if effectiveness_score.nil?
    return 'excellent' if effectiveness_score >= 80
    return 'good' if effectiveness_score >= 60
    return 'fair' if effectiveness_score >= 40
    return 'poor' if effectiveness_score >= 20

    'needs improvement'
  end
end
