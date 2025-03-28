module SocialMedia
  class FacebookService < BaseService
    def initialize(user)
      super
      @graph = Koala::Facebook::API.new(access_token)
    end

    def publish_post(post)
      begin
        response = if post.image.present?
          @graph.put_picture(
            post.image.url,
            { message: format_content(post) }
          )
        else
          @graph.put_wall_post(format_content(post))
        end

        post_url = "https://facebook.com/#{response['id']}"
        update_post_status(post, 'published', post_url)
        collect_analytics(post)
        
        true
      rescue Koala::Facebook::APIError => e
        update_post_status(post, 'failed')
        Rails.logger.error("Facebook post failed: #{e.message}")
        false
      end
    end

    def collect_analytics(post)
      return unless post.published? && post.post_url.present?

      begin
        post_id = extract_post_id(post.post_url)
        insights = @graph.get_object(
          post_id,
          fields: ['insights.metric(post_impressions,post_reactions_by_type,post_clicks)']
        )

        metrics = {
          likes: count_reactions(insights),
          comments: get_comments_count(post_id),
          shares: get_shares_count(post_id),
          views: get_views_count(insights),
          reach: get_reach_count(insights)
        }

        create_analytics(post, metrics)
      rescue Koala::Facebook::APIError => e
        Rails.logger.error("Failed to collect Facebook analytics: #{e.message}")
      end
    end

    private

    def access_token
      # TODO: Implement access token retrieval from your configuration system
      ENV['FACEBOOK_ACCESS_TOKEN']
    end

    def format_content(post)
      content = post.content
      content = "#{post.title}\n\n#{content}" if post.title.present?
      content
    end

    def extract_post_id(post_url)
      post_url.split('/').last
    end

    def count_reactions(insights)
      return 0 unless insights['insights']
      
      reactions = insights['insights']['data'].find { |d| d['name'] == 'post_reactions_by_type' }
      return 0 unless reactions && reactions['values'].any?

      values = reactions['values'].first['value']
      values.values.sum
    end

    def get_comments_count(post_id)
      comments = @graph.get_connections(post_id, 'comments', summary: true)
      comments['summary']['total_count'] rescue 0
    end

    def get_shares_count(post_id)
      shares = @graph.get_object(post_id, fields: ['shares'])
      shares['shares']['count'] rescue 0
    end

    def get_views_count(insights)
      return 0 unless insights['insights']
      
      views = insights['insights']['data'].find { |d| d['name'] == 'post_impressions' }
      return 0 unless views && views['values'].any?

      views['values'].first['value']
    end

    def get_reach_count(insights)
      return 0 unless insights['insights']
      
      reach = insights['insights']['data'].find { |d| d['name'] == 'post_impressions_unique' }
      return 0 unless reach && reach['values'].any?

      reach['values'].first['value']
    end
  end
end 