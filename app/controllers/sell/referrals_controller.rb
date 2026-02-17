# frozen_string_literal: true

module Sell
  class ReferralsController < Sell::BaseController
    def index
      @referrals = affiliate_referrals
                     .order(created_at: :desc)
                     .page(params[:page])
                     .per(25)
    rescue
      @referrals = []
    end
    
    def show
      @referral = affiliate_referrals.find(params[:id])
    end
    
    def stats
      @stats = {
        total: affiliate_referrals.count,
        by_status: affiliate_referrals.group(:status).count,
        by_month: affiliate_referrals
                    .where("created_at > ?", 12.months.ago)
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
      @referral_code = current_affiliate&.affiliate_code || generate_affiliate_code
      @referral_link = "#{request.base_url}?ref=#{@referral_code}"
      
      respond_to do |format|
        format.html
        format.json { render json: { code: @referral_code, link: @referral_link } }
      end
    end
    
    private

    def current_affiliate
      @current_affiliate ||= current_user.affiliate
    end

    def affiliate_referrals
      current_affiliate&.referrals || Referral.none
    end
    
    def generate_affiliate_code
      affiliate = current_user.affiliate || current_user.create_affiliate!(
        affiliate_code: SecureRandom.alphanumeric(8).upcase,
        commission_rate: 0.10,
        status: :active
      )
      affiliate.affiliate_code
    rescue => e
      Rails.logger.error "Failed to generate affiliate code: #{e.message}"
      SecureRandom.hex(4).upcase
    end
  end
end
