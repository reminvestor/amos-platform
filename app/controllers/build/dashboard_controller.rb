# frozen_string_literal: true

module Build
  class DashboardController < Build::BaseController
    def index
      @stats = {
        open_bounties: Bounty.open_bounties.count,
        total_rewards: Bounty.open_bounties.sum(:points),
        completed_bounties: Bounty.completed.count,
        contributors: Bounty.completed.select(:claimed_by_id).distinct.count,
        total_paid: Bounty.completed.sum(Arel.sql('COALESCE(final_points, points)'))
      }

      @featured_bounties = Bounty.available
                                  .order(Arel.sql('COALESCE(priority_rank, 999) ASC, points DESC'))
                                  .limit(6)

      @recent_completions = Bounty.completed
                                   .order(approved_at: :desc)
                                   .limit(5)

      @top_contributors = Contribution.select(:user_id)
                                       .where('created_at > ?', 90.days.ago)
                                       .group(:user_id)
                                       .order(Arel.sql('SUM(stake_value) DESC'))
                                       .limit(10)
                                       .map do |c|
        user = User.find_by(id: c.user_id)
        next unless user
        {
          name: user.display_name,
          total_earned: Contribution.where(user_id: c.user_id).where('created_at > ?', 90.days.ago).sum(:stake_value),
          bounties_completed: Bounty.completed.where(claimed_by_id: c.user_id).count
        }
      end.compact

      @sprint_labels = Bounty.available
                              .where.not(sprint_label: [nil, ''])
                              .group(:sprint_label)
                              .count
                              .sort_by { |_, count| -count }
    rescue => e
      Rails.logger.error "[Build::Dashboard] Error: #{e.message}"
      @stats = { open_bounties: 0, total_rewards: 0, completed_bounties: 0, contributors: 0, total_paid: 0 }
      @featured_bounties = []
      @recent_completions = []
      @top_contributors = []
      @sprint_labels = []
    end
  end
end
