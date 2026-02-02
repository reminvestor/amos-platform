# frozen_string_literal: true

module Build
  class DashboardController < Build::BaseController
    def index
      @stats = {
        open_bounties: 0,
        total_rewards: 0,
        active_proposals: 0,
        contributors: 0
      }
      
      # TODO: Fetch real data from Solana governance program
      # @bounties = Bounty.open.limit(10)
      # @proposals = GovernanceProposal.active.limit(5)
      # @leaderboard = Contribution.top_contributors(10)
    end
  end
end
