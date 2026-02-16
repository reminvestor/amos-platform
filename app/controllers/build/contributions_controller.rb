# frozen_string_literal: true

module Build
  class ContributionsController < Build::BaseController
    def index
      @contributions = Contribution.joins(:user)
                                    .accepted
                                    .order(created_at: :desc)
                                    .page(params[:page])
                                    .per(25)

      @stats = {
        total: Contribution.accepted.count,
        total_value: Contribution.accepted.sum(:stake_value),
        this_month: Contribution.accepted.where('created_at > ?', 30.days.ago).count,
        contributors: Contribution.accepted.select(:user_id).distinct.count
      }
    rescue => e
      Rails.logger.error "[Build::Contributions] Error: #{e.message}"
      @contributions = Contribution.none.page(1)
      @stats = { total: 0, total_value: 0, this_month: 0, contributors: 0 }
    end

    def show
      @contribution = Contribution.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to contributions_path, alert: "Contribution not found."
    end

    def my_contributions
      unless current_user
        redirect_to build_root_path, alert: "Please sign in to view your contributions."
        return
      end

      @contributions = Contribution.where(user: current_user)
                                    .order(created_at: :desc)
                                    .page(params[:page])
                                    .per(25)

      @stats = {
        total: Contribution.where(user: current_user).accepted.count,
        total_earned: Contribution.where(user: current_user).accepted.sum(:stake_value),
        pending: Contribution.where(user: current_user).pending_review.count
      }
    end
  end
end
