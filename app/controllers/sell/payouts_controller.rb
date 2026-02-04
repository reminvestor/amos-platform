# frozen_string_literal: true

module Sell
  class PayoutsController < Sell::BaseController
    def index
      @payouts = []
      @pending_amount = 0
      @minimum_payout = 50
    end
    
    def show
      @payout = nil # Placeholder
    end
    
    def create
      # Handle payout request
      redirect_to sell_payouts_path, notice: "Payout requested successfully!"
    end
    
    def status
      render json: { status: 'pending' }
    end
  end
end
