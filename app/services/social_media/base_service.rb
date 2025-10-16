module SocialMedia
  class BaseService
    def initialize(user)
      @user = user
    end

    def publish_post(post)
      raise NotImplementedError, "#{self.class} must implement publish_post"
    end

    def collect_analytics(post)
      raise NotImplementedError, "#{self.class} must implement collect_analytics"
    end

    private

    attr_reader :user

    def create_analytics(post, metrics)
      post.social_post_analytics.create!(
        likes: metrics[:likes] || 0,
        comments: metrics[:comments] || 0,
        shares: metrics[:shares] || 0,
        views: metrics[:views] || 0,
        reach: metrics[:reach] || 0,
        collected_at: Time.current
      )
    end

    def update_post_status(post, status, post_url = nil)
      post.update!(
        status: status,
        post_url: post_url,
        published_at: status == "published" ? Time.current : nil
      )
    end
  end
end
