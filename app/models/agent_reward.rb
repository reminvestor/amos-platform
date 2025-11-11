class AgentReward < ApplicationRecord
  belongs_to :entity
  belongs_to :agent_lightning_trace
  belongs_to :user, optional: true

  validates :reward_type, presence: true, inclusion: { in: %w[completion quality efficiency user_feedback validation] }
  validates :reward_value, presence: true, numericality: true
  validates :source, presence: true, inclusion: { in: %w[user automated validation_engine] }

  scope :by_type, ->(type) { where(reward_type: type) }
  scope :by_source, ->(source) { where(source: source) }
  scope :recent, -> { order(assigned_at: :desc) }
  scope :positive, -> { where("reward_value > 0") }
  scope :negative, -> { where("reward_value < 0") }

  # Calculate average reward for a type
  def self.average_by_type(type, since: 7.days.ago)
    by_type(type).where("assigned_at >= ?", since).average(:reward_value).to_f
  end
end
