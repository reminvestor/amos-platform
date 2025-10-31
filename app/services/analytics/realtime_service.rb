module Analytics
  class RealtimeService
    # Get current real-time metrics for an entity
    def self.current_metrics(entity)
      # Use Rails cache to avoid hitting DB every second
      Rails.cache.fetch("analytics_metrics_#{entity.id}", expires_in: 5.seconds) do
        calculate_metrics(entity)
      end
    end

    def self.calculate_metrics(entity)
      now = Time.current
      today_start = now.beginning_of_day
      hour_ago = 1.hour.ago

      # Campaign metrics
      campaigns_active = Campaign.where(entity: entity, status: 'active').count
      campaigns_scheduled = Campaign.where(entity: entity, status: 'scheduled').count

      # Email delivery metrics (today)
      emails_sent_today = if defined?(EmailDelivery)
        EmailDelivery.joins(:campaign)
                    .where(campaigns: { entity_id: entity.id })
                    .where(sent_at: today_start..now)
                    .count
      else
        0
      end

      # Email engagement metrics (last hour)
      opens_last_hour = if defined?(EmailDelivery)
        EmailDelivery.joins(:campaign)
                    .where(campaigns: { entity_id: entity.id })
                    .where(opened_at: hour_ago..now)
                    .count
      else
        0
      end

      clicks_last_hour = if defined?(EmailDelivery)
        EmailDelivery.joins(:campaign)
                    .where(campaigns: { entity_id: entity.id })
                    .where(clicked_at: hour_ago..now)
                    .count
      else
        0
      end

      # Landing page metrics (today)
      landing_page_visits_today = if defined?(LandingPageSubmission)
        LandingPageSubmission.joins(:landing_page)
                            .where(landing_pages: { entity_id: entity.id })
                            .where(created_at: today_start..now)
                            .count
      else
        0
      end

      landing_page_conversions_today = if defined?(LandingPageSubmission)
        LandingPageSubmission.joins(:landing_page)
                            .where(landing_pages: { entity_id: entity.id })
                            .where(created_at: today_start..now)
                            .where.not(contact_id: nil)
                            .count
      else
        0
      end

      # Contact metrics
      total_contacts = Contact.where(entity: entity).count
      active_contacts = Contact.where(entity: entity)
                              .where("metadata->>'last_engagement_at' > ?", 7.days.ago.to_s)
                              .count

      # Recent activity count
      recent_activities_count = calculate_recent_activities_count(entity)

      {
        # Campaign stats
        campaigns_active: campaigns_active,
        campaigns_scheduled: campaigns_scheduled,

        # Email stats
        emails_sent_today: emails_sent_today,
        opens_last_hour: opens_last_hour,
        clicks_last_hour: clicks_last_hour,

        # Engagement rates
        open_rate_last_hour: calculate_rate(opens_last_hour, emails_sent_today),
        click_rate_last_hour: calculate_rate(clicks_last_hour, opens_last_hour),

        # Landing page stats
        landing_page_visits_today: landing_page_visits_today,
        landing_page_conversions_today: landing_page_conversions_today,
        conversion_rate_today: calculate_rate(landing_page_conversions_today, landing_page_visits_today),

        # Contact stats
        total_contacts: total_contacts,
        active_contacts: active_contacts,

        # Activity
        recent_activities: recent_activities_count,

        # Timestamp
        timestamp: now.iso8601,
        entity_id: entity.id
      }
    end

    def self.calculate_rate(numerator, denominator)
      return 0 if denominator.zero?
      ((numerator.to_f / denominator) * 100).round(2)
    end

    def self.calculate_recent_activities_count(entity)
      # Count recent activities across different models
      count = 0

      if defined?(EmailDelivery)
        count += EmailDelivery.joins(:campaign)
                             .where(campaigns: { entity_id: entity.id })
                             .where(created_at: 1.hour.ago..Time.current)
                             .count
      end

      if defined?(LandingPageSubmission)
        count += LandingPageSubmission.joins(:landing_page)
                                      .where(landing_pages: { entity_id: entity.id })
                                      .where(created_at: 1.hour.ago..Time.current)
                                      .count
      end

      count
    end
  end
end
