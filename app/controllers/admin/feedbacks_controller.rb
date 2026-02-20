# frozen_string_literal: true

module Admin
  # Admin::FeedbacksController - Dashboard for viewing and analyzing user feedback
  #
  # Provides insights into user satisfaction, feature usage, and pain points.
  # Displays statistics, trends, and recent feedback from users.
  class FeedbacksController < Admin::BaseController
    before_action :set_date_range, only: [:index]

    def index
      # Fetch all feedbacks within date range
      @feedbacks = current_entity.user_feedbacks
                                  .where(created_at: @start_date..@end_date)

      # Calculate statistics
      @total_count = @feedbacks.count
      @positive_count = @feedbacks.where(rating: 1).count
      @neutral_count = @feedbacks.where(rating: 0).count
      @negative_count = @feedbacks.where(rating: -1).count
      @with_comments_count = @feedbacks.where.not(comment: [nil, '']).count

      # Calculate satisfaction score (% of positive ratings)
      @satisfaction_score = if @total_count > 0
                              (@positive_count.to_f / @total_count * 100).round(1)
                            else
                              50.0  # Default to neutral when no data
                            end

      # Group by feedbackable_type
      @by_type = @feedbacks.group(:feedbackable_type).count

      # Satisfaction by type (single query instead of N+1)
      positive_by_type = @feedbacks.where(rating: 1).group(:feedbackable_type).count
      @satisfaction_by_type = {}
      @by_type.each do |type, total|
        type_positive = positive_by_type[type] || 0
        @satisfaction_by_type[type] = if total > 0
                                        (type_positive.to_f / total * 100).round(1)
                                      else
                                        50.0
                                      end
      end

      # Daily trend data
      @daily_positive = @feedbacks.where(rating: 1)
                                   .group("DATE_TRUNC('day', created_at)")
                                   .count

      @daily_negative = @feedbacks.where(rating: -1)
                                   .group("DATE_TRUNC('day', created_at)")
                                   .count

      # Recent feedbacks (last 10)
      @recent_feedbacks = @feedbacks.includes(:user)
                                     .order(created_at: :desc)
                                     .limit(10)

      # Recent negative comments
      @negative_comments = @feedbacks.where(rating: -1)
                                      .where.not(comment: [nil, ''])
                                      .includes(:user)
                                      .order(created_at: :desc)
                                      .limit(10)
    end

    private

    def set_date_range
      @start_date = params[:start_date]&.to_date || 30.days.ago
      @end_date = params[:end_date]&.to_date || Date.today

      # Ensure start_date is before end_date
      @start_date, @end_date = @end_date, @start_date if @start_date > @end_date
    rescue ArgumentError
      # Invalid date format - use defaults
      @start_date = 30.days.ago
      @end_date = Date.today
    end
  end
end
