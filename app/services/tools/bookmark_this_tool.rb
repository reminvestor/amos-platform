# frozen_string_literal: true

module Tools
  class BookmarkThisTool < BaseTool
    def self.read_only?
      false
    end

    def self.metadata
      {
        name: 'bookmark_this',
        description: 'Saves content as a bookmark for the user to reference later. Use when user says "save this", "remember this", "bookmark this", or wants to save a conversation, insight, context, or response for later. NOTE: Documents and file exports go to Work Items, not bookmarks.',
        category: 'memory',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'A clear, descriptive title for the bookmark'
            },
            content_type: {
              type: 'string',
              enum: ['conversation', 'context_block', 'insight', 'response', 'visualization'],
              description: 'Type of content being bookmarked. conversation=chat exchange, context_block=saved info/data, insight=important learning, response=scout output, visualization=chart/graph'
            },
            content: {
              type: 'object',
              description: 'The content to save. Structure depends on content_type.',
              properties: {
                text: { type: 'string', description: 'Text content' },
                data: { type: 'object', description: 'Structured data' },
                visualization: { type: 'object', description: 'Visualization config' },
                summary: { type: 'string', description: 'Brief summary' }
              }
            },
            description: {
              type: 'string',
              description: 'Optional description explaining what this bookmark contains'
            },
            tags: {
              type: 'array',
              items: { type: 'string' },
              description: 'Optional tags for organization (e.g., ["marketing", "q4-2024"])'
            },
            shareable: {
              type: 'boolean',
              description: 'Whether this bookmark should be shareable via link. Default: false'
            }
          },
          required: ['title', 'content_type', 'content']
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      content_type = get_arg(args, :content_type, 'response')
      content = get_arg(args, :content, {})
      description = get_arg(args, :description)
      tags = get_arg(args, :tags, [])
      shareable = get_arg(args, :shareable, false)

      return error_response("Title is required") if title.blank?
      return error_response("Content is required") if content.blank?

      begin
        # Find the most recent assistant message to attach to (if any)
        recent_message = ScoutMessage.where(
          user: @user,
          entity: @entity,
          role: 'assistant'
        ).order(created_at: :desc).first

        # Create the bookmark
        bookmark = MemoryBookmark.create!(
          user: @user,
          entity: @entity,
          scout_message: recent_message,  # Optional, may be nil
          title: title,
          description: description,
          content_type: content_type,
          bookmark_type: 'saved',
          source: 'tool',
          content: content.is_a?(Hash) ? content : { text: content.to_s },
          tags: Array(tags),
          shareable: shareable
        )

        response_data = {
          bookmark_id: bookmark.id,
          title: bookmark.title,
          content_type: bookmark.content_type,
          icon: bookmark.icon,
          message: "✅ Saved '#{title}' to your bookmarks!"
        }

        # Include share URL if shareable
        if shareable && bookmark.share_url
          response_data[:share_url] = bookmark.share_url
          response_data[:message] += " Shareable link: #{bookmark.share_url}"
        end

        success_response(response_data)
      rescue => e
        Rails.logger.error "Bookmark creation failed: #{e.message}"
        error_response("Failed to create bookmark: #{e.message}")
      end
    end
  end
end
