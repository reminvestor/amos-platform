module SocialMedia
  class InstagramService < BaseService
    # Instagram posting via Facebook Graph API
    # Requires Instagram Business Account linked to Facebook Page

    def initialize(connection)
      @connection = connection
      validate_connection!
    end

    def publish_post(content:, image_url: nil, hashtags: [], post: nil)
      begin
        # Note: Instagram Basic Display API doesn't support direct posting
        # We'll need to use the Instagram Graph API (through Facebook) for posting
        # This is a more complex setup requiring a Facebook Business account

        # For now, we'll use the Facebook Graph API through Koala
        fb_graph = Koala::Facebook::API.new(facebook_access_token)

        # First, we need to get the Instagram Business Account ID
        instagram_account_id = get_instagram_account_id(fb_graph)

        response = if post.image.present?
          # For Instagram, we need to first create a media container
          media = fb_graph.put_connections(
            instagram_account_id,
            "media",
            {
              image_url: post.image.url,
              caption: format_content(post)
            }
          )

          # Then publish it
          fb_graph.put_connections(
            instagram_account_id,
            "media_publish",
            { creation_id: media["id"] }
          )
        else
          raise StandardError, "Instagram posts require an image"
        end

        post_url = "https://instagram.com/p/#{response['id']}"
        update_post_status(post, "published", post_url)
        collect_analytics(post)

        true
      rescue StandardError => e
        update_post_status(post, "failed")
        Rails.logger.error("Instagram post failed: #{e.message}")
        false
      end
    end

    def collect_analytics(post)
      return unless post.published? && post.post_url.present?

      begin
        media_id = extract_media_id(post.post_url)

        # Using Facebook Graph API to get Instagram insights
        fb_graph = Koala::Facebook::API.new(facebook_access_token)
        instagram_account_id = get_instagram_account_id(fb_graph)

        insights = fb_graph.get_object(
          "#{instagram_account_id}/media/#{media_id}/insights",
          metric: "engagement,impressions,reach"
        )

        metrics = {
          likes: get_likes_count(media_id),
          comments: get_comments_count(media_id),
          shares: 0, # Instagram doesn't provide shares count
          views: get_views_count(insights),
          reach: get_reach_count(insights)
        }

        create_analytics(post, metrics)
      rescue StandardError => e
        Rails.logger.error("Failed to collect Instagram analytics: #{e.message}")
      end
    end

    private

    def access_token
      # TODO: Implement access token retrieval from your configuration system
      ENV["INSTAGRAM_ACCESS_TOKEN"]
    end

    def facebook_access_token
      # TODO: Implement Facebook access token retrieval from your configuration system
      ENV["FACEBOOK_ACCESS_TOKEN"]
    end

    def format_content(post)
      content = post.content
      content = "#{post.title}\n\n#{content}" if post.title.present?
      content
    end

    def get_instagram_account_id(fb_graph)
      # Get Instagram Business Account ID through Facebook Graph API
      accounts = fb_graph.get_connections("me", "accounts")
      page_id = accounts.first["id"] # Assuming the first page is the one we want

      instagram_accounts = fb_graph.get_connections(
        page_id,
        "instagram_accounts"
      )

      instagram_accounts.first["id"]
    end

    def extract_media_id(post_url)
      # Extract the media ID from Instagram URL
      post_url.split("/p/").last.split("/").first
    end

    def get_likes_count(media_id)
      response = @client.media(media_id)
      response["like_count"] rescue 0
    end

    def get_comments_count(media_id)
      response = @client.media(media_id)
      response["comments_count"] rescue 0
    end

    def get_views_count(insights)
      return 0 unless insights

      impression_data = insights.find { |i| i["name"] == "impressions" }
      impression_data["values"].first["value"] rescue 0
    end

    def get_reach_count(insights)
      return 0 unless insights

      reach_data = insights.find { |i| i["name"] == "reach" }
      reach_data["values"].first["value"] rescue 0
    end
  end
end
