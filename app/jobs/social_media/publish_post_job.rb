module SocialMedia
  class PublishPostJob < ApplicationJob
    queue_as :default

    def perform(post_id)
      post = SocialPost.find(post_id)
      service = ServiceFactory.create_service(post.platform, post.user)
      service.publish_post(post)
    end
  end
end
