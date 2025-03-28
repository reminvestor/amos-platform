module SocialMedia
  class TwitterService < BaseService
    TWITTER_API_URL = 'https://api.twitter.com/2'.freeze
    
    def initialize(user)
      super
      @client = Faraday.new(url: TWITTER_API_URL) do |conn|
        conn.headers['Authorization'] = "Bearer #{access_token}"
        conn.headers['Content-Type'] = 'application/json'
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
      end
    end

    def publish_post(post)
      begin
        # For tweeting with media, we need to use a different authorization (OAuth 1.0a)
        if post.image?
          tweet_with_media(post)
        else
          tweet_text_only(post)
        end
      rescue StandardError => e
        update_post_status(post, 'failed')
        Rails.logger.error("Twitter post failed: #{e.message}")
        false
      end
    end

    def collect_analytics(post)
      return unless post.published? && post.post_url.present?

      begin
        tweet_id = extract_tweet_id(post.post_url)
        
        # Get public metrics for the tweet
        response = @client.get("tweets/#{tweet_id}?tweet.fields=public_metrics,non_public_metrics,organic_metrics")
        
        if response.status == 200
          data = JSON.parse(response.body)
          tweet_data = data['data']
          
          metrics = {
            likes: tweet_data.dig('public_metrics', 'like_count') || 0,
            comments: tweet_data.dig('public_metrics', 'reply_count') || 0,
            shares: tweet_data.dig('public_metrics', 'retweet_count') || 0,
            views: tweet_data.dig('public_metrics', 'impression_count') || 0,
            reach: tweet_data.dig('organic_metrics', 'impression_count') || 0
          }

          create_analytics(post, metrics)
        else
          Rails.logger.error("Failed to get Twitter metrics: #{response.body}")
        end
      rescue StandardError => e
        Rails.logger.error("Failed to collect Twitter analytics: #{e.message}")
      end
    end

    private

    def access_token
      # TODO: Implement access token retrieval from your configuration system
      ENV['TWITTER_BEARER_TOKEN']
    end

    def oauth_client
      # For tweet creation, we need OAuth 1.0a
      # This is a simplified placeholder - in a real implementation, you would set up proper OAuth 1.0a
      {
        consumer_key: ENV['TWITTER_API_KEY'],
        consumer_secret: ENV['TWITTER_API_SECRET'],
        token: ENV['TWITTER_ACCESS_TOKEN'],
        token_secret: ENV['TWITTER_ACCESS_SECRET']
      }
    end

    def tweet_text_only(post)
      tweet_text = format_content(post)
      
      response = @client.post('tweets', {
        text: tweet_text
      })
      
      if response.status == 201
        data = JSON.parse(response.body)
        tweet_id = data['data']['id']
        post_url = "https://twitter.com/user/status/#{tweet_id}"
        
        update_post_status(post, 'published', post_url)
        collect_analytics(post)
        true
      else
        raise StandardError, "Twitter API returned status #{response.status}: #{response.body}"
      end
    end

    def tweet_with_media(post)
      # Step 1: Upload media
      media_id = upload_media(post.image_url)
      
      # Step 2: Create tweet with media
      tweet_text = format_content(post)
      
      response = @client.post('tweets', {
        text: tweet_text,
        media: {
          media_ids: [media_id]
        }
      })
      
      if response.status == 201
        data = JSON.parse(response.body)
        tweet_id = data['data']['id']
        post_url = "https://twitter.com/user/status/#{tweet_id}"
        
        update_post_status(post, 'published', post_url)
        collect_analytics(post)
        true
      else
        raise StandardError, "Twitter API returned status #{response.status}: #{response.body}"
      end
    end

    def upload_media(image_url)
      # Download the image
      image_response = Faraday.get(image_url)
      
      if image_response.status != 200
        Rails.logger.error("Failed to download image from #{image_url}")
        raise StandardError, "Failed to download image from #{image_url}"
      end
      
      # Get image binary data
      image_data = image_response.body
      
      # Create a multipart upload client (uses v1.1 API)
      upload_client = Faraday.new(url: 'https://upload.twitter.com/1.1/') do |conn|
        # Here we would add OAuth 1.0a authentication
        # This is simplified for demonstration
        conn.request :multipart
        conn.adapter Faraday.default_adapter
      end
      
      # Step 1: INIT
      init_response = upload_client.post('media/upload.json', {
        command: 'INIT',
        total_bytes: image_data.bytesize,
        media_type: image_response.headers['content-type'],
        media_category: 'tweet_image'
      })
      
      if init_response.status != 200
        raise StandardError, "Failed to init media upload: #{init_response.body}"
      end
      
      media_id = JSON.parse(init_response.body)['media_id_string']
      
      # Step 2: APPEND
      # Twitter requires chunked uploads for larger media
      chunk_size = 5 * 1024 * 1024 # 5MB chunks
      chunks = (image_data.bytesize / chunk_size.to_f).ceil
      
      chunks.times do |i|
        start_byte = i * chunk_size
        end_byte = [(i + 1) * chunk_size, image_data.bytesize].min - 1
        chunk = image_data[start_byte..end_byte]
        
        append_response = upload_client.post('media/upload.json', {
          command: 'APPEND',
          media_id: media_id,
          segment_index: i,
          media: Faraday::Multipart::FilePart.new(
            StringIO.new(chunk),
            image_response.headers['content-type']
          )
        })
        
        if append_response.status != 200
          raise StandardError, "Failed to append media chunk: #{append_response.body}"
        end
      end
      
      # Step 3: FINALIZE
      finalize_response = upload_client.post('media/upload.json', {
        command: 'FINALIZE',
        media_id: media_id
      })
      
      if finalize_response.status != 200
        raise StandardError, "Failed to finalize media upload: #{finalize_response.body}"
      end
      
      # Return the media ID
      media_id
    end

    def format_content(post)
      # Twitter has a character limit of 280
      content = post.content
      if post.title.present?
        title_and_content = "#{post.title}\n\n#{content}"
        if title_and_content.length <= 280
          content = title_and_content
        elsif (post.title.length + 3 + content.length) > 280
          # If we can't fit both, prioritize content but add title if there's room
          available_chars = 280 - (content.length + 3) # 3 for "\n\n"
          if available_chars > 10 # Only add title if we can show at least 10 chars
            truncated_title = post.title[0..available_chars-1]
            content = "#{truncated_title}...\n\n#{content}"
          end
        end
      end
      
      # Ensure content is within 280 characters
      content.length > 280 ? content[0..276] + '...' : content
    end

    def extract_tweet_id(post_url)
      post_url.split('/status/').last
    end
  end
end 