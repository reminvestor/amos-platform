# frozen_string_literal: true

# ContributionRewardCalculator - Simple Pool-Based Token Distribution
#
# THE MODEL (ORGANIC ECONOMICS):
# 1. Daily pool of tokens available (16,000 AMOS, decreasing via halving)
# 2. Contributors earn "points" for their work
# 3. Your tokens = (your points / total points today) × daily pool
# 4. Decay is DYNAMIC based on platform costs (see PlatformEconomicsService)
#
# EARNING POINTS:
# - Referrals: 1 user invited = 1 point, 1 user CONVERTED = 10 points
# - Sales: 1 user signed up = 1 point per user on their account
# - Code/Community: Bounty value = points (50 AMOS bounty = 50 points)
#
# NO FIXED TOKEN AMOUNTS. Your share depends on:
# - How much you contributed relative to everyone else
# - The daily emission pool (decreases via halving)
#
# This ensures the treasury is never overspent and rewards scale organically.
#
class ContributionRewardCalculator
  # Daily emission pool from treasury (decreases via halving schedule)
  # Year 0-2: 16,000/day, Year 2-4: 8,000/day, etc.
  BASE_DAILY_EMISSION = 16_000

  # Referral points structure (at class level for visibility)
  REFERRAL_POINTS = {
    email_sent: 1,           # 1 point per referral email sent (incentivize action)
    signup: 5,               # 5 points when referral signs up (free account)
    conversion: 10,          # 10 points when referral converts to paid
    active_month: 2          # 2 points per month the referred user stays active
  }.freeze

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

    # === REFERRAL REWARDS ===
    
    # Calculate referral reward - points based on outcomes
    #
    # @param emails_sent [Integer] Number of referral emails sent
    # @param signups [Integer] Number of referrals who signed up
    # @param conversions [Integer] Number of referrals who converted to paid
    # @param total_referral_points_today [Integer] Total referral points today
    # @return [Hash] Reward details
    def calculate_referral_reward(emails_sent: 0, signups: 0, conversions: 0, total_referral_points_today: nil)
      your_points = (emails_sent * REFERRAL_POINTS[:email_sent]) +
                    (signups * REFERRAL_POINTS[:signup]) +
                    (conversions * REFERRAL_POINTS[:conversion])
      
      if total_referral_points_today.nil?
        return {
          points: your_points,
          breakdown: {
            emails: emails_sent * REFERRAL_POINTS[:email_sent],
            signups: signups * REFERRAL_POINTS[:signup],
            conversions: conversions * REFERRAL_POINTS[:conversion]
          },
          tokens: nil,
          note: "Tokens calculated at end of period based on pool share"
        }
      end
      
      result = calculate_pool_share(
        your_points: your_points,
        total_points_today: total_referral_points_today
      )
      
      result[:breakdown] = {
        emails: emails_sent * REFERRAL_POINTS[:email_sent],
        signups: signups * REFERRAL_POINTS[:signup],
        conversions: conversions * REFERRAL_POINTS[:conversion]
      }
      
      result
    end
    
    # === SALES POINTS ===

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

    # === REVIEW REWARDS ===
    
    # Reviewers earn points for reviewing AI-generated work
    # Default: 10% of bounty points, with quality multipliers
    REVIEW_POINTS = {
      base_percentage: 10,      # 10% of bounty points as base review reward
      excellent_multiplier: 1.5, # 95%+ accuracy, 50+ reviews
      good_multiplier: 1.2,      # 90%+ accuracy, 20+ reviews
      poor_multiplier: 0.5       # < 80% accuracy
    }.freeze

    # Calculate review reward for reviewing a bounty
    #
    # @param bounty_points [Numeric] Points of the bounty being reviewed
    # @param quality_multiplier [Numeric] Quality multiplier based on reviewer history
    # @param total_review_points_today [Numeric] Total review points earned today
    # @return [Hash] Reward details
    def calculate_review_reward(bounty_points:, quality_multiplier: 1.0, total_review_points_today: nil)
      base_points = bounty_points * REVIEW_POINTS[:base_percentage] / 100.0
      your_points = (base_points * quality_multiplier).round(2)
      
      if total_review_points_today.nil?
        return {
          points: your_points,
          base_points: base_points,
          multiplier: quality_multiplier,
          tokens: nil,
          note: "Tokens calculated at end of period based on pool share"
        }
      end
      
      result = calculate_pool_share(
        your_points: your_points,
        total_points_today: total_review_points_today
      )
      
      result[:base_points] = base_points
      result[:multiplier] = quality_multiplier
      result
    end

    # Get quality multiplier for a reviewer
    #
    # @param total_reviews [Integer] Total reviews completed
    # @param accuracy [Numeric] Percentage of reviews upheld (0-100)
    # @return [Numeric] Quality multiplier
    def review_quality_multiplier(total_reviews:, accuracy:)
      if total_reviews >= 50 && accuracy >= 95
        REVIEW_POINTS[:excellent_multiplier]
      elsif total_reviews >= 20 && accuracy >= 90
        REVIEW_POINTS[:good_multiplier]
      elsif accuracy < 80
        REVIEW_POINTS[:poor_multiplier]
      else
        1.0
      end
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
        model: "pool_based_organic",
        current_decay_rate: PlatformEconomicsService.current_decay_rate,
        rules: {
          referrals: "1 email = #{REFERRAL_POINTS[:email_sent]} pt, 1 signup = #{REFERRAL_POINTS[:signup]} pts, 1 conversion = #{REFERRAL_POINTS[:conversion]} pts",
          sales: "1 user signed up = 1 point",
          bounties: "Bounty value = points",
          reviews: "#{REVIEW_POINTS[:base_percentage]}% of bounty points × quality multiplier",
          tokens: "Your points / Total points × Daily pool"
        },
        review_multipliers: {
          excellent: "#{REVIEW_POINTS[:excellent_multiplier]}x (50+ reviews, 95%+ accuracy)",
          good: "#{REVIEW_POINTS[:good_multiplier]}x (20+ reviews, 90%+ accuracy)",
          standard: "1.0x (base rate)",
          poor: "#{REVIEW_POINTS[:poor_multiplier]}x (< 80% accuracy)"
        },
        note: "Token decay adjusts based on platform economics. See PlatformEconomicsService."
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
