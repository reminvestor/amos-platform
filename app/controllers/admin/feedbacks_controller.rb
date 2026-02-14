# frozen_string_literal: true

class Admin::FeedbacksController < Admin::BaseController
  def index
    @date_range = parse_date_range
    @feedbacks = UserFeedback.where(created_at: @date_range)

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

    # By feedbackable type
    @by_type = @feedbacks.group(:feedbackable_type).count
    @satisfaction_by_type = {}
    UserFeedback::VALID_FEEDBACKABLE_TYPES.each do |type|
      type_feedbacks = @feedbacks.where(feedbackable_type: type)
      @satisfaction_by_type[type] = type_feedbacks.satisfaction_score if type_feedbacks.any?
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
