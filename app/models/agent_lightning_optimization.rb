# Tracks optimization applications for Agent Lightning
# Records which prompts were optimized, the improvements gained, and supports rollback
class AgentLightningOptimization < ApplicationRecord
  belongs_to :entity
  belongs_to :agent_training_job, optional: true

  # Validations
  validates :entity_id, presence: true
  validates :optimization_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending applied rolled_back failed] }
  validates :improvement_percentage, numericality: { greater_than_or_equal_to: -100, less_than_or_equal_to: 100 }

  # Scopes for querying optimizations
  scope :applied, -> { where(status: "applied") }
  scope :rolled_back, -> { where(status: "rolled_back") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :with_improvement, -> { where("improvement_percentage > ?", 0) }

  # Callbacks
  before_create :generate_optimization_id

  def generate_optimization_id
    self.optimization_id = SecureRandom.uuid
  end

  # Mark optimization as applied
  def mark_applied!(templates_count = 0)
    update!(
      status: "applied",
      applied_at: Time.current,
      templates_updated: templates_count
    )
  end

  # Mark optimization as rolled back
  def mark_rolled_back!
    update!(
      status: "rolled_back",
      rolled_back_at: Time.current,
      rollback_count: rollback_count + 1
    )
  end

  # Mark optimization as failed
  def mark_failed!(error_msg)
    update!(
      status: "failed",
      error_message: error_msg
    )
  end

  # Check if optimization can be rolled back (must be in applied state)
  def can_rollback?
    status == "applied"
  end

  # Get a summary of this optimization
  def summary
    {
      optimization_id: optimization_id,
      status: status,
      improvement_percentage: improvement_percentage.to_f,
      templates_updated: templates_updated,
      prompts_optimized: prompts_optimized,
      templates_modified: templates_modified,
      context_types: context_types_optimized,
      applied_at: applied_at,
      rolled_back_at: rolled_back_at,
      rollback_count: rollback_count
    }
  end

  # Check if this optimization resulted in improvement
  def improved?
    improvement_percentage > 0
  end

  # Get improvement description
  def improvement_description
    case improvement_percentage
    when 0
      "No change"
    when 0..5
      "Minor improvement"
    when 5..15
      "Moderate improvement"
    when 15..50
      "Significant improvement"
    else
      "Major improvement"
    end
  end
end
