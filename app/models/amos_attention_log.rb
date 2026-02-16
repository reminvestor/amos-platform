# frozen_string_literal: true

# AmosAttentionLog - Records what AMOS chose to focus on and why
#
# This is the meta-cognition trail: AMOS's decisions about what to think about.
# Useful for understanding AMOS's decision patterns, detecting blind spots,
# and improving the attention system over time.
#
class AmosAttentionLog < ApplicationRecord
  belongs_to :entity
  belongs_to :amos_thinking_session, optional: true

  OUTCOMES = %w[acted deferred delegated noted skipped].freeze

  validates :focus_area, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :acted_on, -> { where(outcome: 'acted') }
  scope :deferred, -> { where(outcome: 'deferred') }

  def cost_summary
    {
      tokens: token_cost,
      duration_ms: duration_ms,
      cost_usd: (token_cost / 1_000_000.0 * 3.0).round(4) # Sonnet 4.5 input approximation
    }
  end
end
