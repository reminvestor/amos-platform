# frozen_string_literal: true

# ContributionRewardCalculator - Simple Pool-Based Token Distribution
#
# THE MODEL:
# 1. Daily pool of tokens available (16,000 AMOS, decreasing via halving)
# 2. Contributors earn "points" for their work
# 3. Your tokens = (your points / total points today) × daily pool
#
# EARNING POINTS:
# - Sales: 1 user signed up = 1 point
# - Code/Community: Bounty value = points (50 AMOS bounty = 50 points)
#
# THAT'S IT. No multipliers, no complexity scales, no confusion.
# A token is a token is a token.
#
class ContributionRewardCalculator
  # Daily emission pool from treasury (decreases via halving schedule)
  # Year 0-2: 16,000/day, Year 2-4: 8,000/day, etc.
  BASE_DAILY_EMISSION = 16_000

  class << self
    # Calculate reward based on your share of today's pool
    #
    # @param your_points [Numeric] Points you earned (users signed up OR bounty value)
    # @param total_points_today [Numeric] Total points earned by everyone today
    # @return [Hash] Reward details
    def calculate_pool_share(your_points:, total_points_today:)
      return zero_reward if your_points <= 0
      return zero_reward if total_points_today <= 0

      daily_pool = current_daily_emission
      your_share = your_points.to_f / total_points_today
      tokens = (daily_pool * your_share).round(4)

      {
        tokens: tokens,
        points: your_points,
        share_percentage: (your_share * 100).round(2),
        daily_pool: daily_pool,
        total_points_today: total_points_today
      }
    end

    # Calculate sales reward - simple: 1 user = 1 point
    #
    # @param users_signed_up [Integer] Number of users the seller signed up
    # @param total_users_today [Integer] Total users signed up by all sellers today
    # @return [Hash] Reward details
    def calculate_sales_reward(users_signed_up:, total_users_today: nil)
      # If we don't have total, return points only (tokens calculated at end of day)
      if total_users_today.nil?
        return {
          points: users_signed_up,
          tokens: nil,
          note: "Tokens calculated at end of period based on pool share"
        }
      end

      calculate_pool_share(
        your_points: users_signed_up,
        total_points_today: total_users_today
      )
    end

    # Calculate bounty reward - bounty value IS the points
    #
    # @param bounty_points [Numeric] The bounty value in points
    # @param total_bounty_points_today [Numeric] Total bounty points claimed today
    # @return [Hash] Reward details
    def calculate_bounty_reward(bounty_points:, total_bounty_points_today: nil)
      # If we don't have total, return points only
      if total_bounty_points_today.nil?
        return {
          points: bounty_points,
          tokens: nil,
          note: "Tokens calculated at end of period based on pool share"
        }
      end

      calculate_pool_share(
        your_points: bounty_points,
        total_points_today: total_bounty_points_today
      )
    end

    # Calculate combined reward (sales + bounties in same pool)
    #
    # @param your_points [Numeric] Your total points (users + bounties)
    # @param total_points_today [Numeric] Everyone's total points today
    # @return [Hash] Reward details
    def calculate_combined_reward(your_points:, total_points_today:)
      calculate_pool_share(
        your_points: your_points,
        total_points_today: total_points_today
      )
    end

    # Get current daily emission (with halving applied)
    def current_daily_emission
      BASE_DAILY_EMISSION * current_halving_multiplier
    end

    # Halving schedule - emission decreases over time
    def current_halving_multiplier
      TokenStake.current_halving_multiplier
    rescue
      # Fallback if TokenStake not available
      years_active = platform_years_active
      case years_active
      when 0..2 then 1.0
      when 2..4 then 0.5
      when 4..6 then 0.25
      when 6..8 then 0.125
      else 0.0625
      end
    end

    # Stats for transparency
    def stats
      {
        daily_emission: current_daily_emission,
        halving_multiplier: current_halving_multiplier,
        model: "pool_based",
        rules: {
          sales: "1 user signed up = 1 point",
          bounties: "Bounty value = points",
          tokens: "Your points / Total points × Daily pool"
        }
      }
    end

    # Estimate tokens per point at current activity levels
    def estimate_tokens_per_point(average_daily_points: 1000)
      current_daily_emission / average_daily_points.to_f
    end

    private

    def zero_reward
      {
        tokens: 0,
        points: 0,
        share_percentage: 0,
        daily_pool: current_daily_emission,
        total_points_today: 0
      }
    end

    def platform_years_active
      launch_date = Date.new(2026, 2, 1) # Approximate launch
      ((Date.current - launch_date) / 365.0).floor
    rescue
      0
    end
  end
end
