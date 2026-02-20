# frozen_string_literal: true

class Admin::FeedbacksController < Admin::BaseController
  def index
    @date_range = parse_date_range
    @feedbacks = current_entity.user_feedbacks.where(created_at: @date_range)

    # Aggregations
    @total_count = @feedbacks.count
    @positive_count = @feedbacks.positive.count
    @negative_count = @feedbacks.negative.count
    @neutral_count = @feedbacks.neutral.count
    @satisfaction_score = @feedbacks.satisfaction_score
    @with_comments_count = @feedbacks.with_comments.count

    # Daily trend data (for chart) - use raw SQL grouping since groupdate gem is not available
    @daily_positive = @feedbacks.positive
                        .group("DATE_TRUNC('day', created_at)")
                        .order(Arel.sql("DATE_TRUNC('day', created_at)"))
                        .count
    @daily_negative = @feedbacks.negative
                        .group("DATE_TRUNC('day', created_at)")
                        .order(Arel.sql("DATE_TRUNC('day', created_at)"))
                        .count

    # By feedbackable type (single grouped query instead of N+1)
    @by_type = @feedbacks.group(:feedbackable_type).count
    positive_by_type = @feedbacks.positive.group(:feedbackable_type).count
    @satisfaction_by_type = {}
    @by_type.each do |type, total|
      next if total.zero?
      positive = positive_by_type[type] || 0
      @satisfaction_by_type[type] = (positive.to_f / total * 100).round(1)
    end

    # Recent negative feedback with comments
    @negative_comments = @feedbacks.negative.with_comments.recent.includes(:user).limit(20)

    # Recent feedback list
    @recent_feedbacks = @feedbacks.recent.includes(:user).limit(50)
  end

  private

  def parse_date_range
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]).beginning_of_day : 30.days.ago
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]).end_of_day : Time.current
    start_date..end_date
  rescue Date::Error
    30.days.ago..Time.current
  end
end
