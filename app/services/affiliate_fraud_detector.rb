# frozen_string_literal: true

# Service to detect suspicious affiliate activity and potential fraud
# Checks for patterns like multiple signups from same IP, unusually high conversion rates, and rapid clicks
class AffiliateFraudDetector
  # Check for suspicious activity patterns
  #
  # @param affiliate [Affiliate] The affiliate to check
  # @return [Array<String>] Array of fraud flag descriptions
  def self.check_suspicious_activity(affiliate)
    flags = []

    # Check for multiple signups from same IP within 7 days
    flags.concat(check_duplicate_ips(affiliate))

    # Check for unusually high conversion rate (>50%)
    flags.concat(check_high_conversion_rate(affiliate))

    # Check for rapid-fire clicks (>100 clicks per hour)
    flags.concat(check_rapid_clicks(affiliate))

    # Check for pattern of immediate conversions (suspicious timing)
    flags.concat(check_suspicious_timing(affiliate))

    Rails.logger.warn "Fraud flags detected for affiliate #{affiliate.id}: #{flags.join(', ')}" if flags.any?

    flags
  end

  class << self
    private

    # Check for multiple signups from the same IP address
    def check_duplicate_ips(affiliate)
      flags = []

      recent_referrals = affiliate.referrals.where('created_at > ?', 7.days.ago)
      return flags if recent_referrals.count < 3

      # Extract IP addresses from cookie_data
      ip_addresses = recent_referrals.pluck(:cookie_data).map { |data| data['ip'] }.compact

      # Group by IP and find duplicates
      ip_counts = ip_addresses.group_by(&:itself).transform_values(&:count)
      duplicate_ips = ip_counts.select { |_ip, count| count > 3 }

      if duplicate_ips.any?
        max_count = duplicate_ips.values.max
        flags << "Multiple signups from same IP (#{max_count} signups from #{duplicate_ips.keys.first})"
      end

      flags
    end

    # Check for abnormally high conversion rate
    def check_high_conversion_rate(affiliate)
      flags = []

      # Check last 30 days
      clicks = affiliate.affiliate_clicks.where('landed_at > ?', 30.days.ago).count
      conversions = affiliate.referrals.converted.where('created_at > ?', 30.days.ago).count

      return flags if clicks < 10 # Need minimum data to make assessment

      conversion_rate = conversions.to_f / clicks

      if conversion_rate > 0.5
        flags << "Unusually high conversion rate (#{(conversion_rate * 100).round(1)}%)"
      end

      flags
    end

    # Check for rapid-fire clicking pattern
    def check_rapid_clicks(affiliate)
      flags = []

      # Check for any 1-hour window with >100 clicks
      recent_clicks = affiliate.affiliate_clicks.where('landed_at > ?', 24.hours.ago)

      # Group clicks by hour and count
      hourly_groups = recent_clicks.group_by { |click| click.landed_at.beginning_of_hour }

      max_hourly_clicks = hourly_groups.map { |_hour, clicks| clicks.count }.max || 0

      if max_hourly_clicks > 100
        flags << "Abnormally high click volume (#{max_hourly_clicks} clicks in one hour)"
      end

      flags
    end

    # Check for suspicious timing patterns (e.g., immediate conversions)
    def check_suspicious_timing(affiliate)
      flags = []

      # Check if referrals are converting too quickly (within 5 minutes of signup)
      recent_referrals = affiliate.referrals.converted.where('created_at > ?', 7.days.ago)

      quick_conversions = recent_referrals.select do |referral|
        next false unless referral.converted_at && referral.created_at
        time_diff = referral.converted_at - referral.created_at
        time_diff < 5.minutes
      end

      if quick_conversions.count > 2
        flags << "Multiple immediate conversions (#{quick_conversions.count} conversions within 5 minutes of signup)"
      end

      flags
    end
  end
end
