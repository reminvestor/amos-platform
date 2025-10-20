module Analytics
  class ActivityService
    # Get recent activities for the activity feed
    def self.recent_activities(entity, limit: 20)
      activities = []

      # Email opens
      if defined?(EmailDelivery)
        email_opens = EmailDelivery.joins(:campaign, :contact)
                                   .where(campaigns: { entity_id: entity.id })
                                   .where.not(opened_at: nil)
                                   .order(opened_at: :desc)
                                   .limit(limit)
                                   .select('email_deliveries.*, campaigns.name as campaign_name, contacts.email as contact_email, contacts.first_name, contacts.last_name')

        email_opens.each do |delivery|
          activities << {
            type: 'email_open',
            timestamp: delivery.opened_at,
            description: "#{delivery.first_name} #{delivery.last_name} opened email from campaign '#{delivery.campaign_name}'",
            contact_email: delivery.contact_email,
            campaign_name: delivery.campaign_name,
            icon: '📧'
          }
        end
      end

      # Email clicks
      if defined?(EmailDelivery)
        email_clicks = EmailDelivery.joins(:campaign, :contact)
                                    .where(campaigns: { entity_id: entity.id })
                                    .where.not(clicked_at: nil)
                                    .order(clicked_at: :desc)
                                    .limit(limit)
                                    .select('email_deliveries.*, campaigns.name as campaign_name, contacts.email as contact_email, contacts.first_name, contacts.last_name')

        email_clicks.each do |delivery|
          activities << {
            type: 'email_click',
            timestamp: delivery.clicked_at,
            description: "#{delivery.first_name} #{delivery.last_name} clicked link in '#{delivery.campaign_name}'",
            contact_email: delivery.contact_email,
            campaign_name: delivery.campaign_name,
            icon: '🖱️'
          }
        end
      end

      # Landing page submissions
      if defined?(LandingPageSubmission)
        submissions = LandingPageSubmission.joins(:landing_page)
                                          .where(landing_pages: { entity_id: entity.id })
                                          .order(created_at: :desc)
                                          .limit(limit)
                                          .select('landing_page_submissions.*, landing_pages.title as page_title')

        submissions.each do |submission|
          activities << {
            type: 'landing_page_submission',
            timestamp: submission.created_at,
            description: "New submission on landing page '#{submission.page_title}'",
            email: submission.email,
            page_title: submission.page_title,
            icon: '📄'
          }
        end
      end

      # Sort all activities by timestamp and limit
      activities.sort_by { |a| a[:timestamp] }
                .reverse
                .first(limit)
                .map do |activity|
                  activity[:timestamp] = activity[:timestamp].iso8601
                  activity[:relative_time] = time_ago_in_words(activity[:timestamp])
                  activity
                end
    end

    private

    def self.time_ago_in_words(timestamp)
      time = Time.parse(timestamp)
      seconds = Time.current - time

      case seconds
      when 0..60
        "just now"
      when 61..3600
        "#{(seconds / 60).to_i}m ago"
      when 3601..86400
        "#{(seconds / 3600).to_i}h ago"
      else
        "#{(seconds / 86400).to_i}d ago"
      end
    end
  end
end
