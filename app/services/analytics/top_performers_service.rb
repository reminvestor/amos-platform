module Analytics
  class TopPerformersService
    # Get top performing campaigns, emails, or landing pages
    def self.top_performers(entity, metric: 'open_rate', limit: 10)
      case metric
      when 'open_rate'
        top_campaigns_by_open_rate(entity, limit)
      when 'click_rate'
        top_campaigns_by_click_rate(entity, limit)
      when 'conversion_rate'
        top_landing_pages_by_conversion_rate(entity, limit)
      when 'total_opens'
        top_campaigns_by_total_opens(entity, limit)
      when 'total_clicks'
        top_campaigns_by_total_clicks(entity, limit)
      else
        { error: "Unknown metric: #{metric}" }
      end
    end

    private

    def self.top_campaigns_by_open_rate(entity, limit)
      return [] unless defined?(EmailDelivery)

      campaigns = Campaign.where(entity: entity)
                         .joins(:email_deliveries)
                         .select('campaigns.id, campaigns.name,
                                 COUNT(email_deliveries.id) as total_sent,
                                 COUNT(CASE WHEN email_deliveries.opened_at IS NOT NULL THEN 1 END) as total_opens')
                         .group('campaigns.id, campaigns.name')
                         .having('COUNT(email_deliveries.id) >= 10') # Minimum 10 sends
                         .order('CAST(COUNT(CASE WHEN email_deliveries.opened_at IS NOT NULL THEN 1 END) AS FLOAT) / COUNT(email_deliveries.id) DESC')
                         .limit(limit)

      campaigns.map do |campaign|
        open_rate = (campaign.total_opens.to_f / campaign.total_sent * 100).round(2)
        {
          type: 'campaign',
          id: campaign.id,
          name: campaign.name,
          metric: 'open_rate',
          value: open_rate,
          value_formatted: "#{open_rate}%",
          total_sent: campaign.total_sent,
          total_opens: campaign.total_opens
        }
      end
    end

    def self.top_campaigns_by_click_rate(entity, limit)
      return [] unless defined?(EmailDelivery)

      campaigns = Campaign.where(entity: entity)
                         .joins(:email_deliveries)
                         .select('campaigns.id, campaigns.name,
                                 COUNT(CASE WHEN email_deliveries.opened_at IS NOT NULL THEN 1 END) as total_opens,
                                 COUNT(CASE WHEN email_deliveries.clicked_at IS NOT NULL THEN 1 END) as total_clicks')
                         .group('campaigns.id, campaigns.name')
                         .having('COUNT(CASE WHEN email_deliveries.opened_at IS NOT NULL THEN 1 END) >= 10')
                         .order('CAST(COUNT(CASE WHEN email_deliveries.clicked_at IS NOT NULL THEN 1 END) AS FLOAT) / COUNT(CASE WHEN email_deliveries.opened_at IS NOT NULL THEN 1 END) DESC')
                         .limit(limit)

      campaigns.map do |campaign|
        click_rate = campaign.total_opens > 0 ? (campaign.total_clicks.to_f / campaign.total_opens * 100).round(2) : 0
        {
          type: 'campaign',
          id: campaign.id,
          name: campaign.name,
          metric: 'click_rate',
          value: click_rate,
          value_formatted: "#{click_rate}%",
          total_opens: campaign.total_opens,
          total_clicks: campaign.total_clicks
        }
      end
    end

    def self.top_campaigns_by_total_opens(entity, limit)
      return [] unless defined?(EmailDelivery)

      campaigns = Campaign.where(entity: entity)
                         .joins(:email_deliveries)
                         .select('campaigns.id, campaigns.name,
                                 COUNT(email_deliveries.id) as total_sent,
                                 COUNT(CASE WHEN email_deliveries.opened_at IS NOT NULL THEN 1 END) as total_opens')
                         .group('campaigns.id, campaigns.name')
                         .order('total_opens DESC')
                         .limit(limit)

      campaigns.map do |campaign|
        {
          type: 'campaign',
          id: campaign.id,
          name: campaign.name,
          metric: 'total_opens',
          value: campaign.total_opens,
          value_formatted: campaign.total_opens.to_s,
          total_sent: campaign.total_sent
        }
      end
    end

    def self.top_campaigns_by_total_clicks(entity, limit)
      return [] unless defined?(EmailDelivery)

      campaigns = Campaign.where(entity: entity)
                         .joins(:email_deliveries)
                         .select('campaigns.id, campaigns.name,
                                 COUNT(CASE WHEN email_deliveries.clicked_at IS NOT NULL THEN 1 END) as total_clicks')
                         .group('campaigns.id, campaigns.name')
                         .order('total_clicks DESC')
                         .limit(limit)

      campaigns.map do |campaign|
        {
          type: 'campaign',
          id: campaign.id,
          name: campaign.name,
          metric: 'total_clicks',
          value: campaign.total_clicks,
          value_formatted: campaign.total_clicks.to_s
        }
      end
    end

    def self.top_landing_pages_by_conversion_rate(entity, limit)
      return [] unless defined?(LandingPageSubmission)

      pages = LandingPage.where(entity: entity)
                        .joins(:landing_page_submissions)
                        .select('landing_pages.id, landing_pages.title,
                                COUNT(landing_page_submissions.id) as total_visits,
                                COUNT(CASE WHEN landing_page_submissions.email IS NOT NULL THEN 1 END) as total_conversions')
                        .group('landing_pages.id, landing_pages.title')
                        .having('COUNT(landing_page_submissions.id) >= 10')
                        .order('CAST(COUNT(CASE WHEN landing_page_submissions.email IS NOT NULL THEN 1 END) AS FLOAT) / COUNT(landing_page_submissions.id) DESC')
                        .limit(limit)

      pages.map do |page|
        conversion_rate = (page.total_conversions.to_f / page.total_visits * 100).round(2)
        {
          type: 'landing_page',
          id: page.id,
          name: page.title,
          metric: 'conversion_rate',
          value: conversion_rate,
          value_formatted: "#{conversion_rate}%",
          total_visits: page.total_visits,
          total_conversions: page.total_conversions
        }
      end
    end
  end
end
