# frozen_string_literal: true

module Build
  class BountiesController < Build::BaseController
    before_action :set_bounty, only: [:show, :claim, :submit_work]

    def index
      @bounties = Bounty.available

      # Filter by type
      if params[:type].present? && Bounty::BOUNTY_TYPES.include?(params[:type])
        @bounties = @bounties.by_type(params[:type])
      end

      # Filter by sprint
      if params[:sprint].present?
        @bounties = @bounties.where(sprint_label: params[:sprint])
      end

      # Sort
      case params[:sort]
      when 'points'
        @bounties = @bounties.by_points
      when 'urgency'
        @bounties = @bounties.by_urgency
      when 'newest'
        @bounties = @bounties.recent
      when 'priority'
        @bounties = @bounties.order(Arel.sql('COALESCE(priority_rank, 999) ASC'))
      else
        # Default: priority rank first, then points
        @bounties = @bounties.order(Arel.sql('COALESCE(priority_rank, 999) ASC, points DESC'))
      end

      @bounties = @bounties.page(params[:page]).per(20)

      @types = Bounty.available.distinct.pluck(:bounty_type).compact.sort
      @sprints = Bounty.available.where.not(sprint_label: [nil, '']).distinct.pluck(:sprint_label).compact
      @total_points = Bounty.available.sum(:points)
      @bounty_count = Bounty.available.count

      @stats = {
        open: Bounty.open_bounties.count,
        claimed: Bounty.claimed.count,
        completed_30d: Bounty.completed.where('approved_at > ?', 30.days.ago).count,
        total_paid_30d: Bounty.completed.where('approved_at > ?', 30.days.ago).sum(:final_points)
      }
    rescue => e
      Rails.logger.error "[Build::Bounties] Error loading bounties: #{e.message}"
      @bounties = Bounty.none.page(1)
      @types = []
      @sprints = []
      @total_points = 0
      @bounty_count = 0
      @stats = { open: 0, claimed: 0, completed_30d: 0, total_paid_30d: 0 }
    end

    def show
      @can_claim = @bounty.can_claim? && current_user.present?
      @is_claimer = current_user.present? && @bounty.claimed_by == current_user
      @acceptance_criteria = @bounty.metadata&.dig('acceptance_criteria') || []
      @suggested_approach = @bounty.metadata&.dig('suggested_approach')
      @scope = @bounty.metadata&.dig('scope')
    end

    def claim
      unless current_user
        redirect_to bounty_path(@bounty), alert: "Please sign in to claim bounties."
        return
      end

      unless @bounty.can_claim?
        redirect_to bounty_path(@bounty), alert: "This bounty is no longer available."
        return
      end

      @bounty.claim!(current_user)
      redirect_to bounty_path(@bounty), notice: "Bounty claimed! Good luck."
    rescue => e
      redirect_to bounty_path(@bounty), alert: "Could not claim bounty: #{e.message}"
    end

    def submit_work
      unless current_user && @bounty.claimed_by == current_user
        redirect_to bounty_path(@bounty), alert: "You haven't claimed this bounty."
        return
      end

      @bounty.submit!(
        notes: params[:submission_notes],
        pr_url: params[:pr_url],
        work_url: params[:work_url]
      )

      redirect_to bounty_path(@bounty), notice: "Work submitted for review!"
    rescue => e
      redirect_to bounty_path(@bounty), alert: "Could not submit work: #{e.message}"
    end

    private

    def set_bounty
      @bounty = Bounty.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to bounties_path, alert: "Bounty not found."
    end
  end
end
