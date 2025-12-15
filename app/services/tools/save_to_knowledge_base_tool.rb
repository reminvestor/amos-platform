# frozen_string_literal: true

module Tools
  class SaveToKnowledgeBaseTool < BaseTool
    def self.metadata
      {
        name: 'save_to_knowledge_base',
        description: <<~DESC.strip,
          Save information to your personal knowledge base for future reference. Use this when you:
          - Learn something useful from web research
          - Discover an important fact about the user's business
          - Find documentation or best practices for your domain
          - Want to remember context for future tasks
          
          Your knowledge base persists across conversations, so anything you save here
          will be available to you in future tasks. This makes you more knowledgeable over time.
          
          Examples:
          - Save API documentation you looked up
          - Save the user's business-specific requirements
          - Save solutions to common problems
          - Save integration details or configuration patterns
        DESC
        category: 'knowledge',
        input_schema: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'A clear, searchable title for this knowledge (e.g., "QuickBooks API - Invoice Creation")'
            },
            content: {
              type: 'string',
              description: 'The actual knowledge content to save. Be detailed - include code examples, steps, or explanations as needed.'
            },
            source: {
              type: 'string',
              description: 'Optional: URL or reference where this information came from'
            },
            tags: {
              type: 'array',
              items: { type: 'string' },
              description: 'Optional: Tags to help categorize this knowledge (e.g., ["api", "invoices", "quickbooks"])'
            },
            importance: {
              type: 'string',
              enum: %w[low medium high critical],
              description: 'How important is this knowledge? Higher importance = more likely to be retrieved'
            }
          },
          required: %w[title content]
        }
      }
    end

    def execute(args)
      log_execution(args)

      title = get_arg(args, :title)
      content = get_arg(args, :content)
      source = get_arg(args, :source)
      tags = get_arg(args, :tags, [])
      importance = get_arg(args, :importance, 'medium')

      # Validate required args
      if title.blank?
        return error_response('Title is required')
      end

      if content.blank?
        return error_response('Content is required')
      end

      # Get the agent from context
      agent = @context[:agent_plugin]
      unless agent
        return error_response('No agent context - this tool can only be used by agents')
      end

      # Save to the agent's knowledge base
      doc = agent.add_to_knowledge(
        title: title,
        content: content,
        source: source,
        metadata: {
          tags: tags,
          importance: importance,
          saved_by: 'agent',
          context: {
            task: @context[:execution]&.input&.dig('task_description'),
            session_id: @context[:session_id]
          }
        }
      )

      if doc
        success_response(
          saved: true,
          document_id: doc.id,
          title: title,
          message: "Successfully saved '#{title}' to your knowledge base. This information will be available in future tasks."
        )
      else
        error_response('Failed to save to knowledge base')
      end
    rescue => e
      Rails.logger.error "[SaveToKnowledgeBaseTool] Error: #{e.message}"
      error_response("Failed to save: #{e.message}")
    end
  end
end
