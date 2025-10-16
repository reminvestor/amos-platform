module SocialMedia
  class CollectAnalyticsJob < ApplicationJob
    queue_as :default

    def perform(post_id)
      post = SocialPost.find(post_id)
      service = ServiceFactory.create_service(post.platform, post.user)
      service.collect_analytics(post)
    end
  end
end
