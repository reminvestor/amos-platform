module Api
  module V1
    class AnalyticsController < BaseController
      def dashboard
        # Overall stats for the entity
        campaigns = current_entity.campaigns
        contacts = current_entity.contacts
        landing_pages = current_entity.landing_pages

        render json: {
          summary: {
            total_campaigns: campaigns.count,
            active_campaigns: campaigns.where(status: 'in_progress').count,
            total_contacts: contacts.count,
            active_contacts: contacts.where(status: 'active').count,
            total_landing_pages: landing_pages.count,
            published_landing_pages: landing_pages.where(status: 'published').count
          },
          campaigns: campaign_stats(campaigns),
          landing_pages: landing_page_stats(landing_pages),
          recent_activity: recent_activity
        }
      end

      def campaigns
        campaigns = current_entity.campaigns.order(created_at: :desc).limit(params[:limit] || 10)

        render json: {
          data: campaigns.map { |c| campaign_analytics(c) }
        }
      end

      def landing_pages
        pages = current_entity.landing_pages.order(created_at: :desc).limit(params[:limit] || 10)

        render json: {
          data: pages.map { |p| landing_page_analytics(p) }
        }
      end

      private

      def campaign_stats(campaigns)
        completed = campaigns.where(status: 'completed')

        {
          total_sent: completed.sum(:sent_count).to_i,
          avg_open_rate: completed.average(:open_rate)&.round(1) || 0,
          avg_click_rate: completed.average(:click_rate)&.round(1) || 0,
          avg_bounce_rate: completed.average(:bounce_rate)&.round(1) || 0
        }
      end

      def landing_page_stats(pages)
        {
          total_views: pages.sum(:view_count).to_i,
          total_submissions: pages.sum(:submission_count).to_i,
          conversion_rate: calculate_conversion_rate(pages)
        }
      end

      def calculate_conversion_rate(pages)
        total_views = pages.sum(:view_count).to_i
        total_submissions = pages.sum(:submission_count).to_i

        return 0 if total_views.zero?
        ((total_submissions.to_f / total_views) * 100).round(1)
      end

      def recent_activity
        # Get recent campaign sends and landing page submissions
        activities = []

        # Recent campaigns
        current_entity.campaigns.where(status: ['completed', 'in_progress'])
                     .order(updated_at: :desc)
                     .limit(5)
                     .each do |c|
          activities << {
            type: 'campaign',
            title: c.name,
            description: "#{c.status == 'completed' ? 'Sent to' : 'Sending to'} #{c.contact_count || 0} contacts",
            timestamp: c.updated_at.iso8601
          }
        end

        # Recent landing page submissions
        current_entity.landing_pages
                     .where('submission_count > 0')
                     .order(updated_at: :desc)
                     .limit(5)
                     .each do |p|
          activities << {
            type: 'landing_page',
            title: p.title,
            description: "#{p.submission_count} submissions",
            timestamp: p.updated_at.iso8601
          }
        end

        # Sort by timestamp and limit
        activities.sort_by { |a| a[:timestamp] }.reverse.first(10)
      end

      def campaign_analytics(campaign)
        {
          id: campaign.id,
          name: campaign.name,
          status: campaign.status,
          contact_count: campaign.contact_count,
          sent_count: campaign.sent_count,
          open_rate: campaign.open_rate,
          click_rate: campaign.click_rate,
          bounce_rate: campaign.bounce_rate,
          created_at: campaign.created_at.iso8601
        }
      end

      def landing_page_analytics(page)
        {
          id: page.id,
          title: page.title,
          slug: page.slug,
          status: page.status,
          view_count: page.view_count || 0,
          submission_count: page.submission_count || 0,
          conversion_rate: page.view_count&.positive? ?
            ((page.submission_count.to_f / page.view_count) * 100).round(1) : 0,
          created_at: page.created_at.iso8601
        }
      end
    end
  end
end
