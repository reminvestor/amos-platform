# frozen_string_literal: true

# IpGeolocationService - Fast IP-based location lookup
#
# Uses ip-api.com (free, no API key, ~50ms response time)
# Falls back gracefully if lookup fails
#
# Usage:
#   geo = IpGeolocationService.lookup("8.8.8.8")
#   geo[:city]     # "Mountain View"
#   geo[:region]   # "California"
#   geo[:country]  # "United States"
#   geo[:timezone] # "America/Los_Angeles"
#
class IpGeolocationService
  # Cache results for 24 hours (IPs don't change location often)
  CACHE_TTL = 24.hours
  
  # Timeout fast - we don't want to slow down the request
  REQUEST_TIMEOUT = 2.seconds
  
  class << self
    def lookup(ip_address)
      if ip_address.blank?
        Rails.logger.debug "[IpGeo] No IP provided, using default"
        return default_location
      end
      
      if private_ip?(ip_address)
        Rails.logger.debug "[IpGeo] Private IP detected (#{ip_address}), using default"
        return default_location
      end
      
      cache_key = "ip_geo:#{ip_address}"
      
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        Rails.logger.info "[IpGeo] Looking up public IP: #{ip_address}"
        fetch_location(ip_address)
      end
    rescue => e
      Rails.logger.warn "[IpGeo] Lookup failed for #{ip_address}: #{e.message}"
      default_location
    end
    
    private
    
    def fetch_location(ip_address)
      # ip-api.com is free (up to 45 requests/minute) and fast
      uri = URI("http://ip-api.com/json/#{ip_address}?fields=status,city,regionName,country,timezone")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = REQUEST_TIMEOUT
      http.read_timeout = REQUEST_TIMEOUT
      
      response = http.get(uri.request_uri)
      
      if response.code == '200'
        data = JSON.parse(response.body)
        
        if data['status'] == 'success'
          {
            city: data['city'],
            region: data['regionName'],
            country: data['country'],
            timezone: data['timezone'],
            source: :ip_lookup
          }
        else
          Rails.logger.debug "[IpGeo] API returned non-success for #{ip_address}"
          default_location
        end
      else
        Rails.logger.debug "[IpGeo] API returned #{response.code} for #{ip_address}"
        default_location
      end
    rescue Net::OpenTimeout, Net::ReadTimeout
      Rails.logger.debug "[IpGeo] Timeout for #{ip_address}"
      default_location
    end
    
    def private_ip?(ip_address)
      return true if ip_address == '127.0.0.1' || ip_address == '::1'
      
      # Check for private IP ranges
      ip = IPAddr.new(ip_address) rescue nil
      return true unless ip
      
      private_ranges = [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('fc00::/7')  # IPv6 private
      ]
      
      private_ranges.any? { |range| range.include?(ip) }
    end
    
    def default_location
      {
        city: nil,
        region: nil,
        country: nil,
        timezone: nil,
        source: :default
      }
    end
  end
end
