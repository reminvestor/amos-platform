module SocialMedia
  class PostToAccountJob < ApplicationJob
    queue_as :default

    def perform(post_id, account_id)
      post = SocialPost.find(post_id)
      account = SocialMediaAccount.find(account_id)

      begin
        # Check if account is connected and token is valid
        if account.status != "connected"
          raise "Account is not connected"
        end

        if account.expired?
          account.update_expiration_status
          raise "Account token has expired"
        end

        # Use the account's API client to post
        result = post_to_platform(post, account)

        if result[:success]
          # Create a record of the successful post
          post.update_settings("posts", {
            "#{account.platform}_#{account.id}" => {
              posted_at: Time.current,
              success: true,
              external_post_id: result[:post_id],
              external_post_url: result[:post_url]
            }
          })

          Rails.logger.info("Successfully posted to #{account.platform} account: #{account.username}")
        else
          # Log the failure
          post.update_settings("posts", {
            "#{account.platform}_#{account.id}" => {
              posted_at: Time.current,
              success: false,
              error: result[:error]
            }
          })

          Rails.logger.error("Failed to post to #{account.platform} account: #{account.username} - #{result[:error]}")
        end
      rescue => e
        Rails.logger.error("Error posting to #{account.platform}: #{e.message}")

        # Log the error in the post settings
        post.update_settings("posts", {
          "#{account.platform}_#{account.id}" => {
            posted_at: Time.current,
            success: false,
            error: e.message
          }
        })
      end
    end

    private

    def post_to_platform(post, account)
      case account.platform
      when "facebook"
        post_to_facebook(post, account)
      when "instagram"
        post_to_instagram(post, account)
      when "linkedin"
        post_to_linkedin(post, account)
      when "twitter"
        post_to_twitter(post, account)
      else
        { success: false, error: "Unsupported platform: #{account.platform}" }
      end
    end

    def post_to_facebook(post, account)
      graph = Koala::Facebook::API.new(account.access_token)

      begin
        if post.image?
          # Post with image
          result = graph.put_picture(
            post.image_url,
            { message: post.content },
            "me" # or a specific page ID if posting to a page
          )
        else
          # Text-only post
          result = graph.put_wall_post(post.content)
        end

        post_id = result["id"]
        post_url = "https://facebook.com/#{post_id}"

        { success: true, post_id: post_id, post_url: post_url }
      rescue => e
        { success: false, error: e.message }
      end
    end

    def post_to_instagram(post, account)
      # Instagram requires an image
      unless post.image?
        return { success: false, error: "Instagram posts require an image" }
      end

      # Instagram posting is generally done through the Facebook Graph API
      # This is simplified - real implementation would handle the multistep process
      graph = Koala::Facebook::API.new(account.access_token)

      begin
        # In real implementation, you would:
        # 1. Upload the image
        # 2. Create a container
        # 3. Publish the container

        # Simplified response for demonstration
        post_id = "placeholder_#{Time.now.to_i}"
        post_url = "https://instagram.com/p/#{post_id}"

        { success: true, post_id: post_id, post_url: post_url }
      rescue => e
        { success: false, error: e.message }
      end
    end

    def post_to_linkedin(post, account)
      # Simplified for demonstration - would use LinkedIn API
      client = Faraday.new(url: "https://api.linkedin.com") do |conn|
        conn.headers["Authorization"] = "Bearer #{account.access_token}"
        conn.headers["Content-Type"] = "application/json"
        conn.request :json
      end

      begin
        # Simplified response for demonstration
        post_id = "placeholder_#{Time.now.to_i}"
        post_url = "https://linkedin.com/feed/update/#{post_id}"

        { success: true, post_id: post_id, post_url: post_url }
      rescue => e
        { success: false, error: e.message }
      end
    end

    def post_to_twitter(post, account)
      # Simplified for demonstration - would use Twitter API
      client = Faraday.new(url: "https://api.twitter.com") do |conn|
        conn.headers["Authorization"] = "Bearer #{account.access_token}"
        conn.headers["Content-Type"] = "application/json"
        conn.request :json
      end

      begin
        # Simplified response for demonstration
        post_id = "placeholder_#{Time.now.to_i}"
        post_url = "https://twitter.com/user/status/#{post_id}"

        { success: true, post_id: post_id, post_url: post_url }
      rescue => e
        { success: false, error: e.message }
      end
    end
  end
end
