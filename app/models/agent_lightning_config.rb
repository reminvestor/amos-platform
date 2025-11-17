class AgentLightningConfig < ApplicationRecord
  belongs_to :entity

  validates :mode, presence: true, inclusion: { in: %w[observing optimizing training] }
  validates :training_strategy, presence: true, inclusion: { in: %w[prompt_optimization supervised_finetuning rl_training] }
  validates :trace_retention_days, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :min_traces_for_training, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :enabled, -> { where(enabled: true) }
  scope :by_mode, ->(mode) { where(mode: mode) }

  # Is Agent Lightning enabled
  def enabled?
    enabled
  end

  # Should training run now
  def should_retrain?
    return false unless enabled?
    return true if last_training_at.nil?
    last_training_at < retrain_frequency_hours.hours.ago
  end

  # Get available traces for training
  def available_traces_for_training
    entity.agent_lightning_traces
      .completed
      .with_reward
      .where("created_at > ?", trace_retention_days.days.ago)
      .where(included_in_training: false)
  end

  # Can we start training with current traces
  def ready_for_training?
    available_traces_for_training.count >= min_traces_for_training
  end

  # Mark training completed
  def mark_training_completed
    update!(last_training_at: Time.current)
  end

  # Get optimization targets
  def optimization_targets
    super.with_indifferent_access
  end

  # Get learning parameters
  def learning_parameters
    super.with_indifferent_access
  end
end
