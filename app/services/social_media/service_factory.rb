module SocialMedia
  class ServiceFactory
    PLATFORM_SERVICES = {
      "facebook" => FacebookService,
      "instagram" => InstagramService,
      "linkedin" => LinkedinService,
      "twitter" => TwitterService
      # Add other platforms as they are implemented
      # 'tiktok' => TikTokService
    }.freeze

    def self.create_service(platform, user)
      service_class = PLATFORM_SERVICES[platform.downcase]
      raise ArgumentError, "Unsupported platform: #{platform}" unless service_class

      service_class.new(user)
    end
  end
end
