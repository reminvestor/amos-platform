# frozen_string_literal: true

# ExternalAgentDailyStat - Daily activity tracking for rate limiting
#
# Each external agent has one record per day tracking:
# - Bounties claimed/completed/rejected
# - Tool calls made
# - Tokens earned
#
# Used for enforcing daily limits and generating reports.
#
class ExternalAgentDailyStat < ApplicationRecord
  # Rails naming convention expects "external_agent_daily_stats" table
  self.table_name = 'external_agent_daily_stats'

  # Associations
  belongs_to :external_agent_registration

  # Validations
  validates :stat_date, presence: true
  validates :stat_date, uniqueness: { scope: :external_agent_registration_id }

  # Scopes
  scope :for_date, ->(date) { where(stat_date: date) }
  scope :recent, -> { where('stat_date >= ?', 30.days.ago).order(stat_date: :desc) }

  # Class methods
  class << self
    def for_agent_today(agent)
      find_or_create_by!(
        external_agent_registration: agent,
        stat_date: Date.current
      )
    end

    def weekly_summary(agent)
      stats = where(external_agent_registration: agent)
              .where('stat_date >= ?', 7.days.ago)
      
      {
        total_claimed: stats.sum(:bounties_claimed),
        total_completed: stats.sum(:bounties_completed),
        total_rejected: stats.sum(:bounties_rejected),
        total_tool_calls: stats.sum(:tool_calls),
        total_tokens: stats.sum(:tokens_earned).to_f,
        daily_breakdown: stats.order(:stat_date).map do |s|
          {
            date: s.stat_date,
            claimed: s.bounties_claimed,
            completed: s.bounties_completed,
            tokens: s.tokens_earned.to_f
          }
        end
      }
    end
  end
end
