# frozen_string_literal: true

module Sell
  class EarningsController < Sell::BaseController
    def index
      @earnings = []
      @summary = {
        total: 0,
        pending: 0,
        paid: 0,
        this_month: 0
      }
    end
    
    def pending
      @pending_earnings = []
    end
    
    def history
      @earnings_history = []
    end
  end
end
