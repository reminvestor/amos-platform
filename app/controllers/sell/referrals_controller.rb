# frozen_string_literal: true

module Sell
  class ReferralsController < Sell::BaseController
    def index
      @referrals = current_user.referrals
                               .order(created_at: :desc)
                               .page(params[:page])
                               .per(25)
    rescue
      @referrals = []
    end
    
    def show
      @referral = current_user.referrals.find(params[:id])
    end
    
    def stats
      @stats = {
        total: current_user.referrals.count,
        by_status: current_user.referrals.group(:status).count,
        by_month: current_user.referrals
                              .where('created_at > ?', 12.months.ago)
                              .group_by_month(:created_at)
                              .count
      }
      
      respond_to do |format|
        format.html
        format.json { render json: @stats }
      end
    rescue => e
      @stats = { error: e.message }
    end
    
    def link
      @referral_code = current_user.referral_code || generate_referral_code
      @referral_link = "#{root_url}?ref=#{@referral_code}"
      
      respond_to do |format|
        format.html
        format.json { render json: { code: @referral_code, link: @referral_link } }
      end
    end
    
    private
    
    def generate_referral_code
      code = SecureRandom.hex(4).upcase
      current_user.update(referral_code: code) if current_user.respond_to?(:referral_code=)
      code
    end
  end
end
