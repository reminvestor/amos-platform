# frozen_string_literal: true

module Gov
  class ProposalsController < Gov::BaseController
    def index
      @proposals = [] # Placeholder - will sync from Solana governance program
      @active_count = 0
      @passed_count = 0
    end
    
    def show
      @proposal = nil # Placeholder
      @votes = []
    end
    
    def new
      @proposal = {}
    end
    
    def create
      redirect_to gov_proposals_path, notice: "Proposal created!"
    end
    
    def vote
      redirect_to gov_proposal_path(params[:id]), notice: "Vote recorded on-chain!"
    end
    
    def withdraw_vote
      redirect_to gov_proposal_path(params[:id]), notice: "Vote withdrawn!"
    end
    
    def active
      @proposals = []
    end
    
    def passed
      @proposals = []
    end
  end
end
