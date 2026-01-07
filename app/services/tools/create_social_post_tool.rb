# frozen_string_literal: true

module Tools
  class CreateSocialPostTool < BaseTool
    def self.metadata
      {
        name: "create_social_post",
        description: "Create a social media post with optional AI-generated image. Supports Facebook, Instagram, LinkedIn, and Twitter. Can automatically generate images for posts using Gemini AI.",
        category: "social_media",
        input_schema: {
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Internal title for the post (for organization)"
            },
            content: {
              type: "string",
              description: "The text content of the social media post"
            },
            platform: {
              type: "string",
              enum: ["facebook", "instagram", "linkedin", "twitter"],
              description: "Target social media platform"
            },
            generate_image: {
              type: "boolean",
              description: "Whether to generate an AI image for the post using Gemini. Defaults to false."
            },
            image_prompt: {
              type: "string",
              description: "Custom prompt for AI image generation. If not provided, will generate based on post content."
            },
            image_style: {
              type: "string",
              description: "Style for generated image: 'photorealistic', 'illustration', 'minimal', 'vibrant'. Defaults to 'photorealistic'."
            },
            image_url: {
              type: "string",
              description: "URL of an existing image to use (alternative to generate_image)"
            },
            scheduled_at: {
              type: "string",
              description: "ISO 8601 datetime to schedule the post (e.g., '2024-01-15T10:00:00Z'). Leave empty for draft."
            },
            hashtags: {
              type: "array",
              items: { type: "string" },
              description: "List of hashtags to append to the post"
            }
          },
          required: ["content", "platform"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      content = get_arg(args, :content)
      platform = get_arg(args, :platform)
      title = get_arg(args, :title, content.truncate(50))
      generate_image = get_arg(args, :generate_image, false)
      image_prompt = get_arg(args, :image_prompt)
      image_style = get_arg(args, :image_style, "photorealistic")
      image_url = get_arg(args, :image_url)
      scheduled_at = get_arg(args, :scheduled_at)
      hashtags = get_arg(args, :hashtags, [])

      return error_response("Content is required") if content.blank?
      return error_response("Platform is required") if platform.blank?

      # Validate platform
      valid_platforms = %w[facebook instagram linkedin twitter]
      unless valid_platforms.include?(platform.downcase)
        return error_response("Invalid platform. Must be one of: #{valid_platforms.join(', ')}")
      end

      # Instagram requires an image
      if platform.downcase == "instagram" && !generate_image && image_url.blank?
        generate_image = true  # Auto-enable image generation for Instagram
      end

      begin
        # Generate image if requested
        if generate_image
          image_url = generate_post_image(
            content: content,
            platform: platform,
            custom_prompt: image_prompt,
            style: image_style
          )
        end

        # Append hashtags to content
        full_content = content
        if hashtags.any?
          hashtag_text = hashtags.map { |h| h.start_with?("#") ? h : "##{h}" }.join(" ")
          full_content = "#{content}\n\n#{hashtag_text}"
        end

        # Determine status
        status = if scheduled_at.present?
          "scheduled"
        else
          "draft"
        end

        # Create the social post
        social_post = SocialPost.create!(
          user: user,
          title: title,
          content: full_content,
          platform: platform.downcase,
          status: status,
          scheduled_at: scheduled_at.present? ? Time.parse(scheduled_at) : nil,
          image_url: image_url
        )

        Rails.logger.info "[CreateSocialPostTool] Created social post #{social_post.id} for #{platform}"

        response_data = {
          message: "Social post created successfully for #{platform.capitalize}",
          post_id: social_post.id,
          platform: platform,
          status: status,
          title: title,
          content_preview: full_content.truncate(100),
          has_image: image_url.present?
        }

        if image_url.present?
          response_data[:image_url] = image_url
          response_data[:message] += " with AI-generated image"
        end

        if scheduled_at.present?
          response_data[:scheduled_at] = scheduled_at
          response_data[:message] += " (scheduled for #{Time.parse(scheduled_at).strftime('%B %d, %Y at %l:%M %p')})"
        end

        success_response(**response_data)
      rescue => e
        Rails.logger.error "[CreateSocialPostTool] Failed: #{e.message}"
        error_response("Failed to create social post: #{e.message}")
      end
    end

    private

    def generate_post_image(content:, platform:, custom_prompt: nil, style: "photorealistic")
      # Determine optimal size for platform
      size = case platform.downcase
             when "instagram" then "1080x1080"  # Square for feed
             when "facebook" then "1200x630"    # Facebook link preview
             when "linkedin" then "1200x627"    # LinkedIn recommended
             when "twitter" then "1200x675"     # Twitter card
             else "1024x1024"
             end

      # Build prompt
      prompt = if custom_prompt.present?
        "#{custom_prompt}. Style: #{style}. High-quality social media image. No text in image."
      else
        build_auto_prompt(content, platform, style)
      end

      Rails.logger.info "[CreateSocialPostTool] Generating image: #{prompt.truncate(100)}"

      # Generate image with Gemini
      service = ImageGenerationService.new(provider: :gemini)
      asset = service.generate_and_store!(
        user: user,
        entity: entity,
        title: "Social Post Image - #{platform.capitalize}",
        description: prompt,
        size: size,
        tags: ["ai-generated", "social-media", platform.downcase]
      )

      if asset&.file&.attached?
        host = ENV.fetch("APP_HOST", "localhost:3000")
        Rails.application.routes.url_helpers.rails_blob_url(asset.file, host: host)
      else
        nil
      end
    rescue => e
      Rails.logger.error "[CreateSocialPostTool] Image generation failed: #{e.message}"
      nil  # Continue without image
    end

    def build_auto_prompt(content, platform, style)
      # Extract key themes from content
      clean_content = content.gsub(/#\w+/, "").strip  # Remove hashtags

      base_prompt = "Professional #{style} social media image for #{platform}. "
      base_prompt += "Visual representation of: #{clean_content.truncate(150)}. "
      base_prompt += "Modern, engaging, suitable for #{platform} feed. "
      base_prompt += "High quality, vibrant colors, professional composition. "
      base_prompt += "No text overlays or watermarks."

      base_prompt
    end
  end
end
