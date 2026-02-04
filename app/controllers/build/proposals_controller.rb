# frozen_string_literal: true

module Build
  class ProposalsController < Build::BaseController
    def index
      @proposals = [] # Placeholder - will come from governance program
    end
    
    def show
      @proposal = nil # Placeholder
    end
    
    def new
      @proposal = {}
    end
    
    def create
      redirect_to build_proposals_path, notice: "Proposal submitted!"
    end
    
    def vote
      redirect_to build_proposal_path(params[:id]), notice: "Vote recorded!"
    end
  end
end
