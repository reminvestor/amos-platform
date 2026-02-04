# frozen_string_literal: true

module Sell
  class LeaderboardController < Sell::BaseController
    def index
      @leaderboard = []
      @current_rank = nil
    end
  end
end
