# frozen_string_literal: true

module Build
  class LeaderboardController < Build::BaseController
    def index
      @stats = fetch_economy_stats
      @stakeholders = fetch_top_stakeholders
      @contributors = fetch_top_contributors
    end

    private

    def fetch_economy_stats
      stats = TokenEconomyService.economy_stats
      {
        total_staked: stats[:total_supply] || 0,
        active_stakeholders: stats[:total_stakeholders] || 0,
        daily_emission: ContributionRewardCalculator.current_daily_emission,
        concentration: stats.dig(:ownership_concentration, :top_10_percent) || 0
      }
    rescue => e
      Rails.logger.error "[Build::Leaderboard] Failed to fetch economy stats: #{e.message}"
      { total_staked: 0, active_stakeholders: 0, daily_emission: 0, concentration: 0 }
    end

    def fetch_top_stakeholders
      TokenStake.top_stakeholders(limit: 50).map.with_index(1) do |row, rank|
        total = TokenStake.total_supply
        ownership = total.positive? ? (row.total_stake / total * 100).round(4) : 0

        {
          rank: rank,
          display_name: row.first_name.presence || "User #{row.user_id}",
          total_stake: row.total_stake.round(2),
          ownership_percentage: ownership
        }
      end
    rescue => e
      Rails.logger.error "[Build::Leaderboard] Failed to fetch stakeholders: #{e.message}"
      []
    end

    def fetch_top_contributors
      Contribution.leaderboard(limit: 50).map.with_index(1) do |row, rank|
        {
          rank: rank,
          display_name: row.first_name.presence || "User #{row.user_id}",
          contribution_count: row.contribution_count,
          total_stake: row.total_stake.round(2)
        }
      end
    rescue => e
      Rails.logger.error "[Build::Leaderboard] Failed to fetch contributors: #{e.message}"
      []
    end
  end
end
