# frozen_string_literal: true

module Gov
  class DashboardController < Gov::BaseController
    def index
      @stats = {
        total_proposals: 0,
        active_votes: 0,
        treasury_balance: 0,
        total_staked: 0
      }
      
      # TODO: Fetch real data from Solana governance program
      # @active_proposals = GovernanceProposal.voting_open.limit(5)
      # @recent_passed = GovernanceProposal.passed.recent.limit(5)
      # @treasury = TreasuryService.current_balance
    end
  end
end
