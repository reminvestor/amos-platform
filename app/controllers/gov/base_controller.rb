# frozen_string_literal: true

module Gov
  class BaseController < ApplicationController
    layout 'gov'
    
    # Governance portal can be accessed without authentication
    # but voting requires a connected wallet with AMOS tokens
    skip_before_action :authenticate_user!, raise: false
    
    before_action :set_portal_context
    
    private
    
    def set_portal_context
      @portal = :gov
      @portal_name = "Amos Governance"
      @portal_description = "Shape the future of the platform"
    end
    
    def require_wallet_connection!
      unless wallet_connected?
        redirect_to gov_root_path, alert: "Please connect your wallet to participate"
      end
    end
    
    def require_token_balance!
      require_wallet_connection!
      # TODO: Check AMOS token balance on Solana
      # unless has_amos_tokens?
      #   redirect_to gov_root_path, alert: "You need AMOS tokens to vote"
      # end
    end
    
    def wallet_connected?
      session[:solana_wallet].present?
    end
    
    def current_wallet
      session[:solana_wallet]
    end
    
    def amos_balance
      # TODO: Fetch from Solana
      0
    end
    helper_method :wallet_connected?, :current_wallet, :amos_balance
  end
end
