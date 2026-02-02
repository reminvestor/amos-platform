# frozen_string_literal: true

module Build
  class BaseController < ApplicationController
    layout 'build'
    
    # Build portal can be accessed without authentication
    # but some actions require a connected wallet
    skip_before_action :authenticate_user!, raise: false
    
    before_action :set_portal_context
    
    private
    
    def set_portal_context
      @portal = :build
      @portal_name = "Amos Build"
      @portal_description = "Contribute to Amos Labs and earn rewards"
    end
    
    def require_wallet_connection!
      # TODO: Check for connected Solana wallet
      # redirect_to build_root_path, alert: "Please connect your wallet" unless wallet_connected?
    end
    
    def wallet_connected?
      session[:solana_wallet].present?
    end
    
    def current_wallet
      session[:solana_wallet]
    end
    helper_method :wallet_connected?, :current_wallet
  end
end
