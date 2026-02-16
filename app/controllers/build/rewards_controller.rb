# frozen_string_literal: true

module Build
  class RewardsController < Build::BaseController
    def index
      unless current_user
        redirect_to build_root_path, alert: "Please sign in to view your rewards."
        return
      end

      @total_earned = Contribution.where(user: current_user).accepted.sum(:stake_value)
      @pending = Contribution.where(user: current_user).pending_review.sum(:stake_value)

      @recent_rewards = Contribution.where(user: current_user)
                                     .accepted
                                     .order(created_at: :desc)
                                     .limit(20)

      @bounties_completed = Bounty.completed.where(claimed_by: current_user).count
      @bounties_in_progress = Bounty.claimed.where(claimed_by: current_user).count

      # Token balance (if available)
      @token_balance = TokenStake.for_user(current_user).active.sum(:current_amount) rescue 0
    end
  end
end
