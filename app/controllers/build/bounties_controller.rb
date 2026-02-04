# frozen_string_literal: true

module Build
  class BountiesController < Build::BaseController
    before_action :set_bounty, only: [:show, :claim, :submit_work]
    
    def index
      @bounties = Bounty.where(status: ['open', 'claimed', 'in_progress'])
                        .order(created_at: :desc)
                        .page(params[:page])
                        .per(20)
      
      @categories = Bounty.distinct.pluck(:category).compact
      @total_rewards = Bounty.where(status: 'open').sum(:token_reward)
    rescue => e
      Rails.logger.error "Error loading bounties: #{e.message}"
      @bounties = []
      @categories = []
      @total_rewards = 0
    end
    
    def show
      @can_claim = can_claim_bounty?(@bounty)
    end
    
    def claim
      if @bounty.status != 'open'
        redirect_to build_bounty_path(@bounty), alert: "This bounty is no longer available."
        return
      end
      
      @bounty.update!(
        status: 'claimed',
        claimed_by: current_user,
        claimed_at: Time.current
      )
      
      redirect_to build_bounty_path(@bounty), notice: "Bounty claimed! You have 7 days to complete it."
    rescue => e
      redirect_to build_bounty_path(@bounty), alert: "Could not claim bounty: #{e.message}"
    end
    
    def submit_work
      unless @bounty.claimed_by == current_user
        redirect_to build_bounty_path(@bounty), alert: "You haven't claimed this bounty."
        return
      end
      
      @bounty.update!(
        status: 'pending_review',
        work_submitted_at: Time.current,
        work_evidence: params[:work_evidence]
      )
      
      redirect_to build_bounty_path(@bounty), notice: "Work submitted for review!"
    rescue => e
      redirect_to build_bounty_path(@bounty), alert: "Could not submit work: #{e.message}"
    end
    
    private
    
    def set_bounty
      @bounty = Bounty.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to build_bounties_path, alert: "Bounty not found."
    end
    
    def can_claim_bounty?(bounty)
      bounty.status == 'open' && !current_user.nil?
    end
  end
end
