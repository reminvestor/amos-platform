# frozen_string_literal: true

module Tools
  class GetApiDocumentationTool < BaseTool
    # Context7 API endpoint for fetching library documentation
    CONTEXT7_API_BASE = "https://api.context7.com"
    
    def self.metadata
      {
        name: "get_api_documentation",
        description: <<~DESC.strip,
          Fetch up-to-date API documentation for a library or service using Context7.
          
          This tool helps you:
          - Get current API documentation for any popular library or service
          - Find authentication methods, endpoints, and request/response formats
          - Stay up-to-date with API changes and deprecations
          
          **Use cases:**
          - Setting up a new integration: Get the official API docs
          - Fixing an integration: Check if the API has changed
          - Understanding auth requirements: Find correct headers, tokens, etc.
          
          **Examples:**
          - library_name: "shopify" → Get Shopify API docs
          - library_name: "stripe" → Get Stripe API docs
          - library_name: "quickbooks" → Get QuickBooks API docs
          - topic: "authentication" → Focus on auth-related docs
          - topic: "webhooks" → Focus on webhook configuration
        DESC
        category: "research",
        input_schema: {
          type: "object",
          properties: {
            library_name: {
              type: "string",
              description: "Name of the library/API to get documentation for (e.g., 'shopify', 'stripe', 'quickbooks')"
            },
            topic: {
              type: "string",
              description: "Optional: Focus on a specific topic (e.g., 'authentication', 'oauth', 'webhooks', 'orders')"
            },
            page: {
              type: "integer",
              description: "Page number for pagination (1-10). Use higher pages if initial results aren't sufficient.",
              default: 1
            }
          },
          required: ["library_name"]
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      library_name = get_arg(args, :library_name)
      topic = get_arg(args, :topic)
      page = get_arg(args, :page, 1)

      return error_response("library_name is required") if library_name.blank?

      begin
        # Step 1: Resolve library name to Context7 ID
        library_id = resolve_library_id(library_name)
        
        unless library_id
          # Fallback to web search if Context7 doesn't have the library
          return fallback_to_web_search(library_name, topic)
        end

        # Step 2: Fetch documentation
        docs = fetch_library_docs(library_id, topic: topic, page: page)
        
        if docs
          success_response(
            library_name: library_name,
            library_id: library_id,
            topic: topic,
            page: page,
            documentation: docs[:content],
            sections: docs[:sections],
            source: "context7",
            next_page_available: docs[:has_more]
          )
        else
          fallback_to_web_search(library_name, topic)
        end

      rescue => e
        Rails.logger.error "GetApiDocumentationTool error: #{e.message}"
        # Fallback to web search on any error
        fallback_to_web_search(library_name, topic)
      end
    end

    private

    def resolve_library_id(library_name)
      # Common library mappings for faster resolution
      known_libraries = {
        "shopify" => "/shopify/shopify-api",
        "stripe" => "/stripe/stripe-node",
        "quickbooks" => "/intuit/intuit-oauth",
        "twilio" => "/twilio/twilio-node",
        "sendgrid" => "/sendgrid/sendgrid-nodejs",
        "mailgun" => "/mailgun/mailgun-js",
        "slack" => "/slackapi/node-slack-sdk",
        "github" => "/octokit/rest.js",
        "google" => "/googleapis/google-api-nodejs-client",
        "aws" => "/aws/aws-sdk-js-v3",
        "firebase" => "/firebase/firebase-admin-node",
        "mongodb" => "/mongodb/node-mongodb-native",
        "postgresql" => "/brianc/node-postgres",
        "redis" => "/redis/node-redis",
        "elasticsearch" => "/elastic/elasticsearch-js",
        "hubspot" => "/hubspot/hubspot-api-nodejs",
        "salesforce" => "/jsforce/jsforce",
        "zendesk" => "/zendesk/zendesk_api_client_rb",
        "intercom" => "/intercom/intercom-node",
        "mailchimp" => "/mailchimp/mailchimp-marketing-node",
        "notion" => "/makenotion/notion-sdk-js",
        "airtable" => "/airtable/airtable.js",
        "trello" => "/norberteder/trello",
        "asana" => "/asana/node-asana",
        "jira" => "/atlassian/jira.js",
        "linear" => "/linear/linear",
        "plaid" => "/plaid/plaid-node",
        "square" => "/square/square-nodejs-sdk"
      }

      # Check known libraries first
      normalized_name = library_name.to_s.downcase.strip
      return known_libraries[normalized_name] if known_libraries[normalized_name]

      # Try to resolve via Context7 API
      begin
        response = HTTParty.get(
          "#{CONTEXT7_API_BASE}/v1/libraries/search",
          query: { q: library_name, limit: 5 },
          headers: context7_headers,
          timeout: 10
        )

        if response.success? && response.parsed_response["results"]&.any?
          # Return the best match
          response.parsed_response["results"].first["id"]
        else
          nil
        end
      rescue => e
        Rails.logger.warn "Context7 library search failed: #{e.message}"
        nil
      end
    end

    def fetch_library_docs(library_id, topic: nil, page: 1)
      begin
        params = { page: page }
        params[:topic] = topic if topic.present?

        response = HTTParty.get(
          "#{CONTEXT7_API_BASE}/v1/libraries#{library_id}/docs",
          query: params,
          headers: context7_headers,
          timeout: 30
        )

        if response.success?
          data = response.parsed_response
          {
            content: data["content"] || data["documentation"],
            sections: data["sections"] || extract_sections(data["content"]),
            has_more: data["hasMore"] || data["has_more"] || (page < 10)
          }
        else
          nil
        end
      rescue => e
        Rails.logger.warn "Context7 docs fetch failed: #{e.message}"
        nil
      end
    end

    def context7_headers
      headers = {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => "AMOS-Integration-Agent/1.0"
      }
      
      # Add API key if configured
      api_key = ENV["CONTEXT7_API_KEY"] || Rails.application.credentials.dig(:context7, :api_key)
      headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
      
      headers
    end

    def extract_sections(content)
      return [] unless content.present?
      
      # Extract markdown headers as sections
      content.scan(/^#{1,3}\s+(.+)$/).flatten.first(20)
    end

    def fallback_to_web_search(library_name, topic)
      # Build a helpful search query
      search_query = "#{library_name} API"
      search_query += " #{topic}" if topic.present?
      search_query += " documentation official"

      # Return suggestion to use web_search
      success_response(
        library_name: library_name,
        topic: topic,
        source: "fallback",
        message: "Context7 documentation not available for '#{library_name}'. Use web_search for research.",
        suggested_search: search_query,
        suggested_queries: [
          "#{library_name} API authentication",
          "#{library_name} API reference",
          "#{library_name} REST API endpoints",
          "#{library_name} OAuth2 setup",
          "#{library_name} API changelog"
        ]
      )
    end
  end
end

