module Analytics
  class HeatmapService
    # Get engagement data by hour for heatmap visualization
    def self.engagement_by_hour(entity, days: 7)
      start_date = days.days.ago.beginning_of_day
      end_date = Time.current

      # Initialize 24-hour buckets
      hour_buckets = Array.new(24) { |i| { hour: i, opens: 0, clicks: 0, submissions: 0 } }

      # Count email opens by hour
      if defined?(EmailDelivery)
        opens = EmailDelivery.joins(:campaign)
                            .where(campaigns: { entity_id: entity.id })
                            .where(opened_at: start_date..end_date)
                            .group("EXTRACT(HOUR FROM opened_at)")
                            .count

        opens.each do |hour, count|
          hour_buckets[hour.to_i][:opens] = count
        end

        # Count email clicks by hour
        clicks = EmailDelivery.joins(:campaign)
                             .where(campaigns: { entity_id: entity.id })
                             .where(clicked_at: start_date..end_date)
                             .group("EXTRACT(HOUR FROM clicked_at)")
                             .count

        clicks.each do |hour, count|
          hour_buckets[hour.to_i][:clicks] = count
        end
      end

      # Count landing page submissions by hour
      if defined?(LandingPageSubmission)
        submissions = LandingPageSubmission.joins(:landing_page)
                                          .where(landing_pages: { entity_id: entity.id })
                                          .where(created_at: start_date..end_date)
                                          .group("EXTRACT(HOUR FROM created_at)")
                                          .count

        submissions.each do |hour, count|
          hour_buckets[hour.to_i][:submissions] = count
        end
      end

      # Calculate total engagement per hour
      hour_buckets.each do |bucket|
        bucket[:total_engagement] = bucket[:opens] + bucket[:clicks] + bucket[:submissions]
        bucket[:hour_label] = format_hour_label(bucket[:hour])
      end

      {
        days_analyzed: days,
        start_date: start_date.iso8601,
        end_date: end_date.iso8601,
        hourly_data: hour_buckets,
        peak_hour: hour_buckets.max_by { |b| b[:total_engagement] }[:hour],
        total_engagement: hour_buckets.sum { |b| b[:total_engagement] }
      }
    end

    private

    def self.format_hour_label(hour)
      time = Time.current.beginning_of_day + hour.hours
      time.strftime("%l %p").strip # "9 AM", "3 PM", etc.
    end
  end
end
