# frozen_string_literal: true

module Sell
  class ProfileController < Sell::BaseController
    def show
      @affiliate = current_user.affiliate
      @profile = {
        email: current_user.email,
        name: current_user.full_name,
        affiliate_code: @affiliate&.affiliate_code || 'Not set',
        payment_method: 'Not set',
        payout_threshold: 50
      }
    end
    
    def update
      # Update profile
      redirect_to sell_profile_path, notice: "Profile updated!"
    end
  end
end
