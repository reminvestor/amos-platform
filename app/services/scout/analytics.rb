module Scout
  class Analytics
    def initialize(entity:, user:)
      @entity = entity
      @user = user
    end

    # Calculate average open rate across all campaigns
    def calculate_avg_open_rate
      campaigns_with_stats = entity.campaigns.where.not(mailgun_stats: nil)
      return 0 if campaigns_with_stats.empty?

      total_sent = 0
      total_opened = 0

      campaigns_with_stats.each do |campaign|
        sent = campaign.mailgun_stats&.dig("sent") || 0
        opened = campaign.mailgun_stats&.dig("opened") || 0
        total_sent += sent
        total_opened += opened
      end

      return 0 if total_sent == 0
      ((total_opened.to_f / total_sent) * 100).round(1)
    end

    # Load form submissions data with filtering and stats
    def load_form_submissions_data(filters = {})
      # Base query for submissions from user's landing pages
      base_query = LandingPageSubmission.joins(:landing_page)
                                        .where(landing_pages: { user: user, entity: entity })
                                        .includes(:contact, :landing_page)

      # Apply filters
      if filters[:landing_page_id]
        base_query = base_query.where(landing_page_id: filters[:landing_page_id])
      end

      if filters[:form_type].present?
        base_query = base_query.where(form_type: filters[:form_type])
      end

      if filters[:status].present?
        base_query = base_query.where(status: filters[:status])
      end

      case filters[:time_range]
      when "today"
        base_query = base_query.today
      when "week"
        base_query = base_query.this_week
      when "month"
        base_query = base_query.this_month
      end

      # Get submissions with pagination
      submissions = base_query.recent.limit(50)

      # Calculate stats
      stats = calculate_submission_stats(base_query)

      # Format submissions for display
      formatted_submissions = submissions.map do |submission|
        {
          id: submission.id,
          form_type: submission.form_type,
          status: submission.status,
          submitted_at: submission.submitted_at.iso8601,
          processed_at: submission.processed_at&.iso8601,
          contact_info: submission.contact_info,
          utm_params: submission.utm_params,
          source_ip: submission.source_ip,
          referrer: submission.referrer,
          landing_page: {
            id: submission.landing_page.id,
            title: submission.landing_page.title,
            slug: submission.landing_page.slug
          },
          submission_data: submission.submission_data
        }
      end

      {
        submissions: formatted_submissions,
        stats: stats,
        landing_page: filters[:landing_page_id] ?
          LandingPage.find_by(id: filters[:landing_page_id], user: user) : nil,
        pagination: {
          current_count: formatted_submissions.length,
          total_count: base_query.count,
          has_previous: false, # TODO: Implement pagination
          has_next: formatted_submissions.length >= 50
        }
      }
    end

    # Calculate submission statistics
    def calculate_submission_stats(base_query)
      total = base_query.count
      processed = base_query.where(status: [ "processed", "duplicate" ]).count
      pending = base_query.where(status: "pending").count
      failed = base_query.where(status: "failed").count
      spam = base_query.where(status: "spam").count

      conversion_rate = total > 0 ? (processed.to_f / total * 100).round(1) : 0.0

      {
        total: total,
        processed: processed,
        pending: pending,
        failed: failed,
        spam: spam,
        conversion_rate: conversion_rate
      }
    end

    # Load workflow analytics data
    def load_workflow_analytics_data(options = {})
      period = (options[:period] || 30).to_i.days

      # Get analytics from ObservabilityService
      observability = ObservabilityService.instance

      {
        workflow_analytics: observability.workflow_analytics(period),
        tool_analytics: observability.tool_analytics(period),
        user_analytics: observability.user_analytics(period),
        ai_metrics: observability.ai_metrics(period),
        performance_metrics: observability.performance_metrics(period),
        period_days: period.to_i / 1.day,
        generated_at: Time.current
      }
    end

    private

    attr_reader :entity, :user
  end
end
