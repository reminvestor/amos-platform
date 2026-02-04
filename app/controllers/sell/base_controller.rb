# frozen_string_literal: true

module Sell
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_affiliate
    
    layout 'sell'
    
    private
    
    def ensure_affiliate
      # Allow any authenticated user to access the sell portal
      # In production, you might want to check for affiliate approval
      true
    end
    
    def current_affiliate
      @current_affiliate ||= current_user.affiliate_profile
    end
    helper_method :current_affiliate
  end
end
