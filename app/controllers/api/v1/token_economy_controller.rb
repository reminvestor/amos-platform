# frozen_string_literal: true

module Api
  module V1
    # API endpoints for the token economy transparency dashboard
    # Provides public access to ownership distribution and economy stats
    class TokenEconomyController < Api::V1::BaseController
      skip_before_action :authenticate_user!, only: [:stats, :distribution, :leaderboard]

      # GET /api/v1/token_economy/stats
      # Public endpoint showing economy-wide statistics
      def stats
        stats = TokenEconomyService.economy_stats

        render json: {
          success: true,
          data: {
            total_supply: stats[:total_supply],
            active_stakes: stats[:active_stakes],
            total_stakeholders: stats[:total_stakeholders],
            supply_by_type: stats[:supply_by_type],
            ownership_concentration: stats[:ownership_concentration],
            decay_stats: stats[:decay_stats],
            revenue_allocation: TokenEconomyService::REVENUE_ALLOCATION,
            updated_at: Time.current.iso8601
          }
        }
      end

      # GET /api/v1/token_economy/distribution
      # Public endpoint showing ownership distribution
      def distribution
        distribution = TokenEconomyService.public_ownership_distribution

        render json: {
          success: true,
          data: {
            stakeholders: distribution,
            total_supply: TokenStake.total_supply,
            total_stakeholders: distribution.length,
            updated_at: Time.current.iso8601
          }
        }
      end

      # GET /api/v1/token_economy/leaderboard
      # Public endpoint showing top stakeholders
      def leaderboard
        limit = [params[:limit]&.to_i || 20, 100].min
        top_stakeholders = TokenStake.top_stakeholders(limit: limit)

        render json: {
          success: true,
          data: {
            leaderboard: top_stakeholders.map do |row|
              {
                rank: nil, # Will be set below
                display_name: row.first_name || "User #{row.user_id}",
                total_stake: row.total_stake.round(2),
                ownership_percentage: calculate_ownership_percentage(row.total_stake)
              }
            end.each_with_index.map { |item, idx| item.merge(rank: idx + 1) },
            updated_at: Time.current.iso8601
          }
        }
      end

      # GET /api/v1/token_economy/my_profile
      # Authenticated endpoint for user's own token economy profile
      def my_profile
        profile = TokenEconomyService.user_profile(current_user)

        render json: {
          success: true,
          data: {
            total_stake: profile[:total_stake],
            ownership_percentage: profile[:ownership_percentage],
            stakes_by_type: profile[:stakes_by_type],
            stake_count: profile[:stake_count],
            total_earned: profile[:total_earned],
            total_decayed: profile[:total_decayed],
            contributions_count: profile[:contributions],
            projected_monthly_revenue: profile[:projected_monthly_revenue],
            recent_stakes: profile[:recent_stakes].map { |s| serialize_stake(s) },
            updated_at: Time.current.iso8601
          }
        }
      end

      # GET /api/v1/token_economy/my_stakes
      # Authenticated endpoint for user's stakes
      def my_stakes
        stakes = TokenStake.for_user(current_user)
                           .active
                           .order(earned_at: :desc)
                           .page(params[:page])
                           .per(params[:per_page] || 20)

        render json: {
          success: true,
          data: {
            stakes: stakes.map { |s| serialize_stake(s) },
            pagination: {
              current_page: stakes.current_page,
              total_pages: stakes.total_pages,
              total_count: stakes.total_count
            }
          }
        }
      end

      # GET /api/v1/token_economy/my_contributions
      # Authenticated endpoint for user's contributions
      def my_contributions
        contributions = Contribution.for_user(current_user)
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

        render json: {
          success: true,
          data: {
            contributions: contributions.map { |c| serialize_contribution(c) },
            stats: Contribution.for_user(current_user).contribution_stats,
            pagination: {
              current_page: contributions.current_page,
              total_pages: contributions.total_pages,
              total_count: contributions.total_count
            }
          }
        }
      end

      # POST /api/v1/token_economy/contributions
      # Submit a new contribution
      def create_contribution
        contribution = Contribution.new(contribution_params)
        contribution.user = current_user
        contribution.entity = current_user.entity

        if contribution.save
          render json: {
            success: true,
            data: serialize_contribution(contribution),
            message: 'Contribution submitted for review'
          }, status: :created
        else
          render json: {
            success: false,
            errors: contribution.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def contribution_params
        params.require(:contribution).permit(
          :contribution_type,
          :title,
          :description,
          :external_reference,
          :external_url,
          :complexity_multiplier
        )
      end

      def serialize_stake(stake)
        {
          id: stake.id,
          stake_type: stake.stake_type,
          category: stake.category,
          initial_amount: stake.initial_amount.to_f,
          current_amount: stake.current_amount.to_f,
          decay_rate: stake.decay_rate.to_f,
          decay_percentage: stake.decay_percentage,
          earned_at: stake.earned_at&.iso8601,
          projected_value_30d: stake.projected_value_at(30.days.from_now),
          projected_value_90d: stake.projected_value_at(90.days.from_now),
          half_life_days: stake.half_life_days.round(1)
        }
      end

      def serialize_contribution(contribution)
        {
          id: contribution.id,
          contribution_type: contribution.contribution_type,
          title: contribution.title,
          description: contribution.description,
          status: contribution.status,
          stake_value: contribution.stake_value&.to_f,
          external_reference: contribution.external_reference,
          external_url: contribution.external_url,
          created_at: contribution.created_at.iso8601,
          reviewed_at: contribution.reviewed_at&.iso8601,
          stake_awarded: contribution.stake_awarded?
        }
      end

      def calculate_ownership_percentage(stake_amount)
        total = TokenStake.total_supply
        return 0 if total.zero?
        (stake_amount / total * 100).round(4)
      end
    end
  end
end
