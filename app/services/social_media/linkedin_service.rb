module SocialMedia
  class LinkedinService < BaseService
    LINKEDIN_API_URL = "https://api.linkedin.com/v2".freeze

    def initialize(user)
      super
      @client = Faraday.new(url: LINKEDIN_API_URL) do |conn|
        conn.headers["Authorization"] = "Bearer #{access_token}"
        conn.headers["Content-Type"] = "application/json"
        conn.headers["X-Restli-Protocol-Version"] = "2.0.0"
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
      end
    end

    def publish_post(post)
      begin
        # Create the share content
        share_data = create_share_data(post)

        # Make the API request to LinkedIn
        response = @client.post("ugcPosts", share_data)

        if response.status == 201
          post_id = JSON.parse(response.body)["id"]
          post_url = "https://www.linkedin.com/feed/update/#{post_id}"

          update_post_status(post, "published", post_url)
          collect_analytics(post)

          true
        else
          raise StandardError, "LinkedIn API returned status #{response.status}: #{response.body}"
        end
      rescue StandardError => e
        update_post_status(post, "failed")
        Rails.logger.error("LinkedIn post failed: #{e.message}")
        false
      end
    end

    def collect_analytics(post)
      return unless post.published? && post.post_url.present?

      begin
        post_id = extract_post_id(post.post_url)

        # Get social actions (likes, comments)
        social_actions = get_social_actions(post_id)

        # Get share statistics
        stats = get_share_statistics(post_id)

        metrics = {
          likes: social_actions[:likes] || 0,
          comments: social_actions[:comments] || 0,
          shares: social_actions[:shares] || 0,
          views: stats[:impressions] || 0,
          reach: stats[:unique_impressions] || 0
        }

        create_analytics(post, metrics)
      rescue StandardError => e
        Rails.logger.error("Failed to collect LinkedIn analytics: #{e.message}")
      end
    end

    private

    def access_token
      # TODO: Implement access token retrieval from your configuration system
      ENV["LINKEDIN_ACCESS_TOKEN"]
    end

    def create_share_data(post)
      data = {
        author: "urn:li:person:#{user_linkedin_id}",
        lifecycleState: "PUBLISHED",
        specificContent: {
          'com.linkedin.ugc.ShareContent': {
            shareCommentary: {
              text: format_content(post)
            },
            shareMediaCategory: post.image? ? "IMAGE" : "NONE"
          }
        },
        visibility: {
          'com.linkedin.ugc.MemberNetworkVisibility': "PUBLIC"
        }
      }

      # Add image if present
      if post.image?
        # First, upload the image to LinkedIn
        upload_url = upload_image(post.image_url)

        if upload_url
          data[:specificContent]["com.linkedin.ugc.ShareContent"][:media] = [
            {
              status: "READY",
              description: {
                text: post.title
              },
              media: upload_url,
              title: {
                text: post.title
              }
            }
          ]
        end
      end

      data
    end

    def upload_image(image_url)
      # Download the image
      image_response = Faraday.get(image_url)

      if image_response.status != 200
        Rails.logger.error("Failed to download image from #{image_url}")
        return nil
      end

      # Get image binary data and type
      image_data = image_response.body
      content_type = image_response.headers["content-type"]

      # Step 1: Register the image
      register_response = @client.post("assets?action=registerUpload", {
        registerUploadRequest: {
          recipes: [ "urn:li:digitalmediaRecipe:feedshare-image" ],
          owner: "urn:li:person:#{user_linkedin_id}",
          serviceRelationships: [
            {
              relationshipType: "OWNER",
              identifier: "urn:li:userGeneratedContent"
            }
          ]
        }
      })

      if register_response.status != 200
        Rails.logger.error("Failed to register image upload with LinkedIn: #{register_response.body}")
        return nil
      end

      register_data = JSON.parse(register_response.body)
      upload_url = register_data["value"]["uploadMechanism"]["com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest"]["uploadUrl"]
      asset_id = register_data["value"]["asset"]

      # Step 2: Upload the image to the provided URL
      upload_client = Faraday.new do |conn|
        conn.adapter Faraday.default_adapter
      end

      upload_response = upload_client.put(upload_url, image_data) do |req|
        req.headers["Content-Type"] = content_type
      end

      if upload_response.status < 200 || upload_response.status >= 300
        Rails.logger.error("Failed to upload image to LinkedIn: #{upload_response.body}")
        return nil
      end

      # Return the asset ID
      asset_id
    end

    def format_content(post)
      content = post.content
      content = "#{post.title}\n\n#{content}" if post.title.present?
      content
    end

    def extract_post_id(post_url)
      post_url.split("update/").last
    end

    def get_social_actions(post_id)
      response = @client.get("socialActions/#{post_id}")

      if response.status == 200
        data = JSON.parse(response.body)
        {
          likes: data.dig("likesSummary", "count") || 0,
          comments: data.dig("commentsSummary", "count") || 0,
          shares: data.dig("sharesSummary", "count") || 0
        }
      else
        { likes: 0, comments: 0, shares: 0 }
      end
    end

    def get_share_statistics(post_id)
      response = @client.get("socialMetrics/#{post_id}")

      if response.status == 200
        data = JSON.parse(response.body)
        {
          impressions: data.dig("totalShareStatistics", "impressionCount") || 0,
          unique_impressions: data.dig("totalShareStatistics", "uniqueImpressionsCount") || 0
        }
      else
        { impressions: 0, unique_impressions: 0 }
      end
    end

    def user_linkedin_id
      # TODO: Implement retrieval of the user's LinkedIn ID from your configuration system
      ENV["LINKEDIN_USER_ID"]
    end
  end
end
