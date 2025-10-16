# Amos AI Service with configurable AI providers
#
# CONFIGURATION:
# To use Grok 4 (default): export AI_PROVIDER=grok && export XAI_API_KEY=your_key
# To use Claude:           export AI_PROVIDER=claude && export ANTHROPIC_API_KEY=your_key
# To use OpenAI GPT-5:     export AI_PROVIDER=openai && export OPENAI_API_KEY=your_key
#
# Easy switching:
# - Development: Add to .env file
# - Production: Set environment variables
# - Runtime: ScoutGenericToolsService::AI_PROVIDER = 'claude'

class ScoutGenericToolsService
  # AI Provider Configuration - Easy to switch between providers
  AI_PROVIDER = ENV["AI_PROVIDER"] || "grok" # Options: 'grok', 'claude', 'openai'

  def initialize(user, entity, session_id = nil, agent_loadout = nil)
    @user = user
    @entity = entity
    @session_id = session_id
    @saved_message_content = Set.new  # Track saved messages to prevent duplicates
    @context = nil  # Current canvas/page context
    @agent_loadout = agent_loadout  # Optional agent loadout for governance

    # Use the centralized AI service configuration
    @ai_service = AiServiceHelper.get_service

    # Get the provider name from the configured service
    @ai_provider_name = case Rails.application.config.ai_service
    when :grok then "Grok"
    when :claude then "Claude"
    when :openai then "OpenAI GPT-5"
    when :bedrock then "AWS Bedrock"
    else Rails.application.config.ai_service.to_s
    end

    Rails.logger.info "🤖 Scout using AI provider: #{Rails.application.config.ai_service}"
  end

  # Generic function calling tools for AI providers
  TOOLS = [
    {
      name: "get_data",
      description: "Query any data model with filters and options",
      input_schema: {
        type: "object",
        properties: {
          object_type: {
            type: "string",
            description: "The type of object to query (e.g., 'campaign', 'contact', 'landing_page')"
          },
          filters: {
            type: "object",
            description: "Filters to apply (e.g., {status: 'sent', date_range: 'last_30_days'})"
          },
          options: {
            type: "object",
            description: "Query options (e.g., {limit: 20, order_by: 'created_at desc', include_metrics: true})"
          }
        },
        required: [ "object_type" ]
      }
    },
    {
      name: "create_object",
      description: "Create a new object of any type",
      input_schema: {
        type: "object",
        properties: {
          object_type: {
            type: "string",
            description: "The type of object to create (e.g., 'campaign', 'contact', 'landing_page')"
          },
          data: {
            type: "object",
            description: "The data for the new object"
          }
        },
        required: [ "object_type", "data" ]
      }
    },
    {
      name: "get_schema",
      description: "Get the schema and field information for any data model (use this before creating/updating records to ensure you use the right fields).",
      input_schema: {
        type: "object",
        properties: {
          object_type: {
            type: "string",
            description: "The type of object to get schema for (e.g., 'contact', 'campaign', 'landing_page')"
          }
        },
        required: [ "object_type" ]
      }
    },
    {
      name: "list_connections",
      description: "List available external integrations and their connection status",
      input_schema: {
        type: "object",
        properties: {
          category: {
            type: "string",
            description: "Filter by category (payment, ecommerce, crm, etc.)"
          }
        },
        required: []
      }
    },
    {
      name: "describe_connection",
      description: "Get details about a specific integration connection including available operations",
      input_schema: {
        type: "object",
        properties: {
          connection_id: {
            type: "integer",
            description: "The ID of the connection to describe"
          }
        },
        required: [ "connection_id" ]
      }
    },
    {
      name: "test_connection",
      description: "Test an existing integration connection to verify it's working properly",
      input_schema: {
        type: "object",
        properties: {
          connection_id: {
            type: "integer",
            description: "The ID of the connection to test"
          }
        },
        required: [ "connection_id" ]
      }
    },
    {
      name: "invoke_operation",
      description: "Execute an operation on an external integration (e.g., fetch Stripe customers, create Shopify product)",
      input_schema: {
        type: "object",
        properties: {
          connection_id: {
            type: "integer",
            description: "The ID of the connection to use"
          },
          operation_id: {
            type: "string",
            description: "The operation to execute (e.g., 'stripe.list_customers.v2020-08-27')"
          },
          params: {
            type: "object",
            description: "Query parameters for the operation"
          },
          body: {
            type: "object",
            description: "Request body for POST/PUT operations"
          }
        },
        required: [ "connection_id", "operation_id" ]
      }
    },
    {
      name: "dry_run_operation",
      description: "Preview what an operation would do without executing it",
      input_schema: {
        type: "object",
        properties: {
          connection_id: {
            type: "integer",
            description: "The ID of the connection to use"
          },
          operation_id: {
            type: "string",
            description: "The operation to preview"
          },
          params: {
            type: "object",
            description: "Query parameters for the operation"
          },
          body: {
            type: "object",
            description: "Request body for POST/PUT operations"
          }
        },
        required: [ "connection_id", "operation_id" ]
      }
    },
    {
      name: "confirm_operation",
      description: "Execute a previously dry-run operation using its confirmation token",
      input_schema: {
        type: "object",
        properties: {
          token: {
            type: "string",
            description: "The confirmation token from dry_run_operation"
          }
        },
        required: [ "token" ]
      }
    },
      {
        name: "discover_api_schema",
        description: "Discover available API endpoints and operations for an integration",
        input_schema: {
          type: "object",
          properties: {
            integration: {
              type: "string",
              description: "The integration slug to discover (e.g., 'stripe', 'shopify')"
            }
          },
          required: [ "integration" ]
        }
      },
      {
        name: "configure_integration",
        description: "Update integration settings, endpoints, or authentication configuration. Admin-only for global integrations, allowed for user-owned custom integrations.",
        input_schema: {
          type: "object",
          properties: {
            connection_id: {
              type: "integer",
              description: "The ID of the connection to configure"
            },
            updates: {
              type: "object",
              description: "Configuration updates to apply",
              properties: {
                api_base_url: {
                  type: "string",
                  description: "Update the API base URL"
                },
                auth_config: {
                  type: "object",
                  description: "Update authentication configuration (OAuth URLs, scopes, etc.)"
                },
                allowed_hosts: {
                  type: "array",
                  items: { type: "string" },
                  description: "Update allowed host patterns"
                },
                rate_limits: {
                  type: "object",
                  description: "Update rate limit configuration"
                },
                custom_headers: {
                  type: "object",
                  description: "Add or update custom headers"
                }
              }
            },
            operation_updates: {
              type: "array",
              description: "Updates to specific operations",
              items: {
                type: "object",
                properties: {
                  operation_id: {
                    type: "string",
                    description: "The operation to update"
                  },
                  path_template: {
                    type: "string",
                    description: "Update the endpoint path"
                  },
                  request_schema: {
                    type: "object",
                    description: "Update the request schema"
                  },
                  pagination_strategy: {
                    type: "string",
                    description: "Update pagination strategy"
                  }
                }
              }
            }
          },
          required: [ "connection_id" ]
      }
    },
    {
      name: "generate_ai_landing_page",
      description: "Generate a complete AI-powered landing page using sophisticated multi-agent system (PREFERRED for landing pages)",
      input_schema: {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "Title/name for the landing page"
          },
          description: {
            type: "string",
            description: "Detailed description of what the landing page should accomplish"
          },
          page_type: {
            type: "string",
            description: "Type of landing page to generate",
            enum: [ "lead_generation", "product_launch", "event_registration", "newsletter_signup", "free_trial", "demo_request" ]
          },
          campaign_id: {
            type: "integer",
            description: "Optional campaign ID to associate with this landing page"
          }
        },
        required: [ "title", "description" ]
      }
    },
    {
      name: "update_landing_page_status",
      description: "Update the status of a landing page (publish, unpublish, archive)",
      input_schema: {
        type: "object",
        properties: {
          landing_page_id: {
            type: "integer",
            description: "ID of the landing page to update"
          },
          status: {
            type: "string",
            description: "New status for the landing page",
            enum: [ "draft", "published", "archived" ]
          }
        },
        required: [ "landing_page_id", "status" ]
      }
    },
    {
      name: "update_landing_page_content",
      description: "Update the content of an existing landing page with AI assistance",
      input_schema: {
        type: "object",
        properties: {
          landing_page_id: {
            type: "integer",
            description: "ID of the landing page to update"
          },
          instruction: {
            type: "string",
            description: "Detailed instruction for how to modify the landing page content"
          },
          create_backup: {
            type: "boolean",
            description: "Whether to create a backup version for rollback (default: true)",
            default: true
          }
        },
        required: [ "landing_page_id", "instruction" ]
      }
    },
    {
      name: "revert_landing_page_to_version",
      description: "Revert a landing page to a previous version",
      input_schema: {
        type: "object",
        properties: {
          landing_page_id: {
            type: "integer",
            description: "ID of the landing page to revert"
          },
          version_id: {
            type: "integer",
            description: "ID of the version to revert to (optional - if not provided, reverts to most recent backup)"
          }
        },
        required: [ "landing_page_id" ]
      }
    },
    {
      name: "link_template_to_campaign",
      description: "Link an email template to a campaign",
      input_schema: {
        type: "object",
        properties: {
          campaign_id: {
            type: "integer",
            description: "The ID of the campaign to update"
          },
          template_id: {
            type: "integer",
            description: "The ID of the email template to link"
          }
        },
        required: [ "campaign_id", "template_id" ]
      }
    },
    {
      name: "create_dynamic_visualization",
      description: "Create a custom HTML visualization or report to display data insights",
      input_schema: {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "Title for the visualization"
          },
          subtitle: {
            type: "string",
            description: "Optional subtitle or description"
          },
          html_content: {
            type: "string",
            description: "Custom HTML content with data visualizations, charts, metrics, insights. Use Bootstrap classes and the provided AI styles (ai-metric-card, ai-chart-container, ai-insight-box, ai-recommendation, ai-warning)"
          },
          canvas_type: {
            type: "string",
            description: "Always set to 'dynamic_canvas'",
            default: "dynamic_canvas"
          }
        },
        required: [ "title", "html_content" ]
      }
    },
    {
      name: "manage_task_list",
      description: "Create or update a task list to track progress on multi-step operations. Use this for complex tasks like creating campaigns, landing pages, or multi-step workflows.",
      input_schema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: [ "create", "update", "add_task", "complete_task", "fail_task" ],
            description: "Action to perform on the task list"
          },
          title: {
            type: "string",
            description: "Title for the task list (required for 'create' action)"
          },
          tasks: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: {
                  type: "string",
                  description: "Unique identifier for the task"
                },
                description: {
                  type: "string",
                  description: "Clear description of what needs to be done"
                },
                status: {
                  type: "string",
                  enum: [ "pending", "in_progress", "completed", "failed", "skipped" ],
                  description: "Current status of the task"
                },
                details: {
                  type: "string",
                  description: "Additional details or results from completing the task"
                }
              },
              required: [ "id", "description", "status" ]
            },
            description: "List of tasks with their status (required for 'create' and 'update' actions)"
          },
          task_id: {
            type: "string",
            description: "ID of specific task to update (required for 'complete_task', 'fail_task', 'add_task' actions)"
          },
          task_description: {
            type: "string",
            description: "Description for new task (required for 'add_task' action)"
          },
          details: {
            type: "string",
            description: "Additional details about the task completion or failure"
          }
        },
        required: [ "action" ]
      }
    },
    {
      name: "aggregate_artifact_data",
      description: "Perform aggregation operations on artifact data (group_by, count, sum, avg). Use this for analytics on previously fetched data.",
      input_schema: {
        type: "object",
        properties: {
          artifact_id: {
            type: "integer",
            description: "The ID of the artifact containing the data to aggregate"
          },
          operation: {
            type: "string",
            enum: [ "group_by_field", "group_by_time", "top_k", "simple_stats" ],
            description: "The type of aggregation to perform"
          },
          field: {
            type: "string",
            description: "Field to group by (for group_by_field) or analyze (for top_k)"
          },
          time_field: {
            type: "string",
            description: "Time field for group_by_time operations"
          },
          time_bucket: {
            type: "string",
            enum: [ "hour", "day", "week", "month", "quarter", "year" ],
            description: "Time bucket size for group_by_time"
          },
          aggregations: {
            type: "array",
            description: "List of aggregation functions to apply",
            items: {
              type: "object",
              properties: {
                function: {
                  type: "string",
                  enum: [ "count", "sum", "avg", "min", "max", "distinct" ]
                },
                field: { type: "string" },
                alias: { type: "string" }
              }
            }
          },
          k: {
            type: "integer",
            description: "Number of top results to return (for top_k)"
          }
        },
        required: [ "artifact_id", "operation" ]
      }
    },
    {
      name: "fetch_next_page",
      description: "Fetch the next page of data for a paginated artifact. Use when an artifact has more data available.",
      input_schema: {
        type: "object",
        properties: {
          artifact_id: {
            type: "integer",
            description: "The artifact ID to fetch more data for"
          },
          cursor: {
            type: "string",
            description: "Pagination cursor (if available)"
          },
          limit: {
            type: "integer",
            description: "Number of records to fetch (max 100)"
          }
        },
        required: [ "artifact_id" ]
      }
    },
    {
      name: "web_search",
      description: "Search the web for information, documentation, or current data. Useful for finding API documentation, tutorials, or current information.",
      input_schema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "The search query to look up"
          },
          num_results: {
            type: "integer",
            description: "Number of search results to return (default: 5, max: 10)"
          }
        },
        required: [ "query" ]
      }
    },
    {
      name: "create_rag_store",
      description: "Create a RAG (Retrieval Augmented Generation) knowledge base from API documentation and user-provided files",
      input_schema: {
        type: "object",
        properties: {
          app_name: {
            type: "string",
            description: "Name of the application/API"
          },
          documentation: {
            type: "array",
            description: "Array of documentation URLs or text content"
          },
          user_uploads: {
            type: "array",
            description: "Array of uploaded file references"
          }
        },
        required: [ "app_name" ]
      }
    },
    {
      name: "generate_integration_config",
      description: "Generate initial integration configuration with authentication and one test endpoint",
      input_schema: {
        type: "object",
        properties: {
          app_name: {
            type: "string",
            description: "Name of the application to integrate"
          },
          use_case: {
            type: "string",
            description: "Description of what the integration will be used for"
          },
          rag_store_id: {
            type: "string",
            description: "ID of the RAG store containing API documentation"
          }
        },
        required: [ "app_name", "use_case" ]
      }
    },
    {
      name: "test_integration_endpoint",
      description: "Test an integration endpoint with provided credentials",
      input_schema: {
        type: "object",
        properties: {
          integration_id: {
            type: "integer",
            description: "ID of the integration to test"
          },
          credentials: {
            type: "object",
            description: "API credentials (e.g., api_key, oauth_token)"
          },
          test_params: {
            type: "object",
            description: "Optional test parameters for the API call"
          }
        },
        required: [ "integration_id", "credentials" ]
      }
    },
    {
      name: "build_integration_endpoints",
      description: "Build out all remaining endpoints for an integration based on successful test pattern",
      input_schema: {
        type: "object",
        properties: {
          integration_id: {
            type: "integer",
            description: "ID of the integration to build out"
          },
          use_case: {
            type: "string",
            description: "Original use case for context"
          },
          rag_store_id: {
            type: "string",
            description: "ID of the RAG store for endpoint discovery"
          }
        },
        required: [ "integration_id" ]
      }
    }
  ]

  def process_message_with_tools(user_message, conversation_history = [], current_canvas = nil)
    begin
      # Load context if available
      context = get_context
      Rails.logger.info "🎯 Processing with context: #{context.inspect}" if context.present?

      # Detect user intent
      detected_mode = detect_user_intent(user_message)
      Rails.logger.info "🤖 Scout detected mode: #{detected_mode}"

      # Build system prompt with dynamic schema information and mode
      system_prompt = build_system_prompt_with_dynamic_schema(current_canvas, detected_mode)

      # Enhance user message with canvas context if available
      enhanced_user_message = enhance_message_with_canvas_context(user_message, current_canvas)

      # Prepare conversation messages with history
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_user_message)

      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name} (including history)"

      # Send to AI service with function calling
      response = @ai_service.send_message(
        system_prompt,
        conversation_messages,

        max_tokens: 25000,
        temperature: 0.7
      )

      # Parse response for JSON structure with message and tool calls
      if tool_calls = parse_function_calls_from_response(response)
        Rails.logger.info "Detected function calls: #{tool_calls.map { |t| t[:name] }}"

        # Execute the tools
        tool_results = execute_tools(tool_calls)

        # Send the real tool results back to AI service for an updated response
        final_message = generate_response_with_tool_results(user_message, @parsed_user_message, tool_results)

        {
          message: final_message,
          tools_used: true,
          tools_list: tool_calls.map { |t| t[:name] }.uniq,
          success_count: tool_results.count { |r| r[:success] },
          error_count: tool_results.count { |r| !r[:success] },
          canvas: @suggested_canvas,
          canvas_data: @canvas_data,
          mode: detected_mode
        }
      else
        # No tools needed, extract message from response
        # If @parsed_user_message is nil, try to extract from response
        final_message = @parsed_user_message
        if final_message.nil? && response.is_a?(String)
          begin
            parsed = JSON.parse(response)
            final_message = parsed["message"] || response
          rescue JSON::ParserError
            final_message = response
          end
        end

        {
          message: final_message || response,
          tools_used: false,
          canvas: @suggested_canvas,
          canvas_data: @canvas_data,
          mode: detected_mode
        }
      end

    rescue JSON::ParserError => e
      Rails.logger.error "Scout JSON parsing error: #{e.message}"
      Rails.logger.error "Response that failed to parse: #{response}"

      {
        message: "I understand your request, but I'm having trouble processing it right now. Could you try rephrasing your question?",
        tools_used: false,
        error: "JSON parsing failed"
      }
    rescue => e
      Rails.logger.error "Scout generic tools error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        message: "I'm experiencing some technical difficulties. Please try again or let me know if you need help with something else.",
        tools_used: false,
        error: e.message
      }
    end
  end

  def process_message_with_tools_streaming(user_message, progress_callback = nil, conversation_history = [], current_canvas = nil)
    begin
      # Initialize instance variables
      @suggested_canvas = nil
      @canvas_data = nil
      @progress_callback = progress_callback

      progress_callback&.call("🧠 Building context with available data models...")

      # Detect user intent
      detected_mode = detect_user_intent(user_message)
      Rails.logger.info "🤖 Scout detected mode: #{detected_mode}"

      # Build system prompt with dynamic schema information and mode
      system_prompt = build_system_prompt_with_dynamic_schema(current_canvas, detected_mode)

      # Enhance user message with canvas context if available
      enhanced_user_message = enhance_message_with_canvas_context(user_message, current_canvas)

      # Prepare conversation messages with history
      conversation_messages = format_conversation_for_ai(conversation_history, enhanced_user_message)

      Rails.logger.info "Sending #{conversation_messages.length} messages to #{@ai_provider_name} (including history)"
      progress_callback&.call("🤖 Sending request to #{@ai_provider_name} with conversation context...")

      # Always stream responses for better UX
      Rails.logger.info "Streaming response in #{detected_mode} mode"

      accumulated_content = ""
      tool_calls = []
      streaming_started = false
      # @saved_message_content is initialized in the constructor to persist across all recursive calls

      # Stream the response - use native Bedrock tools
      tools = get_bedrock_tools
      Rails.logger.info "Sending #{tools.length} tools to Bedrock"
      Rails.logger.info "Tools: #{tools.map { |t| t[:name] }.join(', ')}"

      @ai_service.send_message_streaming(
        system_prompt,
        conversation_messages,
        max_tokens: 25000,
        temperature: 0.7,
        json_mode: false,  # Let Bedrock handle tool calling natively
        tools: tools
      ) do |chunk|
        if chunk[:type] == :content && chunk[:content]
          accumulated_content += chunk[:content]

          if !streaming_started
            streaming_started = true
            progress_callback&.call("💬 streaming")
          end

          # Stream content directly
          progress_callback&.call({
            type: "content_chunk",
            content: chunk[:content]
          })
        elsif chunk[:type] == :tool_use_start
          # Tool use is starting
          progress_callback&.call({
            type: "tool_detected",
            name: chunk[:tool_name],
            tool_id: chunk[:tool_id]
          })

          # Start collecting this tool call
          tool_calls << {
            id: chunk[:tool_id],
            name: chunk[:tool_name],
            arguments: ""
          }
        elsif chunk[:type] == :tool_use
          # Tool arguments are being streamed
          if chunk[:tool_use] && tool_calls.last
            # The tool_use chunk contains the input as a string
            tool_calls.last[:arguments] += chunk[:tool_use].input || ""
            # Only log first chunk to reduce noise
            if tool_calls.last[:arguments].length < 10
              Rails.logger.info "Tool use starting for #{tool_calls.last[:name]}"
            end
          end

        elsif chunk[:type] == :complete
          # Response complete
          Rails.logger.info "Bedrock response complete. Tool calls: #{tool_calls.length}"

          # If we have tool calls, execute them
          if tool_calls.any?
            Rails.logger.info "Executing tool calls: #{tool_calls.map { |t| t[:name] }}"
            Rails.logger.info "Tool calls detail: #{tool_calls.inspect}"

            # Save any accumulated content before tools as an intermediate message
            if accumulated_content.present? && accumulated_content.strip.length > 0
              content_hash = accumulated_content.strip
              unless @saved_message_content.include?(content_hash)
                Rails.logger.info "💾 Saving intermediate message before tools: #{accumulated_content}"
                progress_callback&.call({
                  type: "save_message",
                  content: accumulated_content,
                  role: "assistant"
                })
                @saved_message_content.add(content_hash)
                # Mark that we've saved messages during streaming
                @messages_saved_during_streaming = true
                # Reset accumulated content after saving to prevent duplication
                accumulated_content = ""
              else
                Rails.logger.info "⚠️ Skipping duplicate intermediate message: #{accumulated_content.strip.first(50)}..."
              end
            end

            # Parse and execute each tool
            results = []
            tool_calls.each do |tool_call|
              Rails.logger.info "Processing tool: #{tool_call[:name]} with raw arguments: #{tool_call[:arguments].inspect}"

              # Parse arguments
              args = begin
                tool_call[:arguments].to_s.strip.empty? ? {} : JSON.parse(tool_call[:arguments])
              rescue JSON::ParserError => e
                Rails.logger.error "Failed to parse tool arguments: #{e.message}"
                {}
              end

              Rails.logger.info "Parsed arguments for #{tool_call[:name]}: #{args.inspect}"

              progress_callback&.call({
                type: "tool_start",
                name: tool_call[:name],
                arguments: args
              })

              # Handle special canvas loading tool
              if tool_call[:name] == "load_canvas"
                canvas_name = args["canvas_name"] || "campaign_viewer"  # Default to campaign_viewer if not specified
                Rails.logger.info "Canvas loading requested: #{canvas_name}"
                @suggested_canvas = canvas_name
                Rails.logger.info "Set @suggested_canvas to: #{@suggested_canvas}"
                results << { success: true, message: "Loading #{canvas_name}" }
              else
                # Execute our existing tools
                result = execute_tool_by_name(tool_call[:name], args, progress_callback)
                results << result

                # Notify tool completion
                progress_callback&.call({
                  type: "tool_complete",
                  name: tool_call[:name],
                  success: result[:success] || false
                })

                # Check if the tool result includes a canvas to load
                if result[:canvas] && progress_callback
                  progress_callback.call({
                    type: "load_canvas",
                    canvas: result[:canvas],
                    canvas_data: result[:canvas_data] || result[:task_list] || {}
                  })
                end

                # Auto-update task progress if we have a task list
                update_task_for_tool_completion(tool_call[:name], args, result[:success], progress_callback)
              end
            end

            # Preserve any streamed content from before tool execution
            initial_message = accumulated_content

            # If no message was streamed but tools were used, provide a default message
            if initial_message.empty? && tool_calls.any? { |tc| tc[:name] == "load_canvas" }
              initial_message = "I'll load the #{@suggested_canvas.gsub('_', ' ')} for you right now."
            elsif initial_message.empty?
              initial_message = "I've executed the requested tools."
            end

            # For get_schema, add information about what to do next
            if tool_calls.any? { |tc| tc[:name] == "get_schema" } && results.any? { |r| r[:success] }
              schema_result = results.find { |r| r[:tool_name] == "get_schema" }
              if schema_result && initial_message.include?("check the campaign structure")
                initial_message += "\n\nGreat! I've retrieved the campaign structure. Now, please provide me with the following details for your new campaign:\n\n"
                initial_message += "1. **Campaign Name**: What would you like to call this campaign?\n"
                initial_message += "2. **Subject Line**: What subject line should we use?\n"
                initial_message += "3. **Target Audience**: Who should receive this campaign? (You can specify a contact group or describe the recipients)\n"
                initial_message += "4. **Email Template**: Do you have a specific template in mind, or would you like me to help create one?\n\n"
                initial_message += "Once you provide these details, I'll create the campaign for you!"
              end
            end

            # If we have tool results, we need to continue the conversation
            if results.any? && !tool_calls.any? { |tc| tc[:name] == "load_canvas" }
              Rails.logger.info "Tool execution complete, continuing conversation with tool results"

              # First, add the assistant's message with tool use
              # This is required before sending tool results
              tool_use_content = []

              # Add any text content that was accumulated
              if accumulated_content.present?
                tool_use_content << { text: accumulated_content }
              end

              # Add the tool use blocks
              tool_calls.each do |tool_call|
                # Handle empty arguments
                arguments = tool_call[:arguments].to_s.strip.empty? ? {} : JSON.parse(tool_call[:arguments])

                tool_use_content << {
                  tool_use: {
                    tool_use_id: tool_call[:id],
                    name: tool_call[:name],
                    input: arguments
                  }
                }
              end

              # Add assistant message with tool use
              conversation_messages << {
                role: "assistant",
                content: tool_use_content
              }

              # Now add tool result messages
              tool_calls.zip(results).each do |tool_call, result|
                # Add tool result as a user message with proper content structure
                conversation_messages << {
                  role: "user",
                  content: [
                    {
                      tool_result: {
                        tool_use_id: tool_call[:id],
                        content: [
                          {
                            json: sanitize_for_bedrock(
                              if result.is_a?(Hash)
                                if result[:success]
                                  # For successful results, include all relevant data
                                  {
                                    success: true,
                                    message: result[:message] || "Tool executed successfully",
                                    data: result.except(:success, :message, :canvas, :canvas_data, :task_list)
                                  }
                                else
                                  # For failures, include error information
                                  {
                                    success: false,
                                    error: result[:error] || "Tool execution failed",
                                    details: result[:details] || result.except(:success, :error)
                                  }
                                end
                              else
                                # Fallback for non-hash results
                                { success: true, result: result }
                              end
                            )
                          }
                        ]
                      }
                    }
                  ]
                }
              end

              # Call Bedrock again to get the final response
              progress_callback&.call("🎯 Generating response based on results...")

              # Log the conversation for debugging
              Rails.logger.info "Continuing conversation with #{conversation_messages.length} messages"
              conversation_messages.each_with_index do |msg, idx|
                Rails.logger.info "Message #{idx}: role=#{msg[:role]}, content_type=#{msg[:content].class}"
                if msg[:content].is_a?(Array)
                  Rails.logger.info "  Content array length: #{msg[:content].length}"
                  msg[:content].each_with_index do |content_item, i|
                    content_keys = content_item.keys.join(", ")
                    Rails.logger.info "  Content[#{i}]: #{content_keys}"
                    if content_item[:tool_use]
                      Rails.logger.info "    Tool use: #{content_item[:tool_use][:name]}"
                    elsif content_item[:tool_result]
                      Rails.logger.info "    Tool result for: #{content_item[:tool_result][:tool_use_id]}"
                    end
                  end
                end
              end

              # Initialize final_message before the begin block
              final_message = nil

              begin
                # Use streaming for the continuation response too
                tools = get_bedrock_tools
                continuation_message = ""

                # Signal that we're starting to stream the continuation
                progress_callback&.call("💬 streaming")

                continuation_tool_calls = []

                @ai_service.send_message_streaming(
                  system_prompt,
                  conversation_messages,
                  max_tokens: 25000,
                  temperature: 0.7,
                  json_mode: false,
                  tools: tools
                ) do |chunk|
                  if chunk[:type] == :content && chunk[:content]
                    continuation_message += chunk[:content]
                    # Stream the continuation content to the UI
                    progress_callback&.call({
                      type: "content_chunk",
                      content: chunk[:content]
                    })
                  elsif chunk[:type] == :tool_use_start
                    # AI wants to use another tool in the continuation
                    Rails.logger.info "Continuation wants to use tool: #{chunk[:tool_name]}"
                    continuation_tool_calls << {
                      id: chunk[:tool_id],
                      name: chunk[:tool_name],
                      arguments: ""
                    }
                    # Notify UI about tool detection
                    progress_callback&.call({
                      type: "tool_detected",
                      name: chunk[:tool_name],
                      tool_id: chunk[:tool_id]
                    })
                  elsif chunk[:type] == :tool_use && continuation_tool_calls.any?
                    # Accumulate tool arguments
                    continuation_tool_calls.last[:arguments] += chunk[:tool_use].input || ""
                  elsif chunk[:type] == :complete
                    Rails.logger.info "Continuation streaming complete: #{continuation_message.length} chars"
                  end
                end

                # If the AI provided a message before using continuation tools, save it
                if continuation_message.present? && continuation_tool_calls.any?
                  content_hash = continuation_message.strip
                  unless @saved_message_content.include?(content_hash)
                    Rails.logger.info "💾 Saving continuation message before tools: #{continuation_message}"
                    progress_callback&.call({
                      type: "save_message",
                      content: continuation_message,
                      role: "assistant"
                    })
                    @saved_message_content.add(content_hash)
                    # Mark that we've saved messages during streaming
                    @messages_saved_during_streaming = true
                    # Reset continuation message after saving to prevent duplication
                    continuation_message = ""
                  else
                    Rails.logger.info "⚠️ Skipping duplicate continuation message: #{continuation_message.strip.first(50)}..."
                  end
                end

                # If the continuation wants to use more tools, execute them recursively
                if continuation_tool_calls.any?
                  Rails.logger.info "Continuation requested #{continuation_tool_calls.length} more tools"

                  # Execute the continuation tools
                  continuation_results = []
                  continuation_tool_calls.each do |tool_call|
                    Rails.logger.info "Processing continuation tool: #{tool_call[:name]} with arguments: #{tool_call[:arguments]}"

                    # Parse arguments if they're a string
                    parsed_args = if tool_call[:arguments].is_a?(String)
                      begin
                        tool_call[:arguments].to_s.strip.empty? ? {} : JSON.parse(tool_call[:arguments])
                      rescue JSON::ParserError => e
                        Rails.logger.error "Failed to parse tool arguments: #{e.message}"
                        {}
                      end
                    else
                      tool_call[:arguments]
                    end

                    result = execute_tool_by_name(tool_call[:name], parsed_args)
                    continuation_results << result

                    # Notify tool completion
                    progress_callback&.call({
                      type: "tool_complete",
                      name: tool_call[:name],
                      success: result[:success] || false
                    })

                    # Check if the tool result includes a canvas to load
                    if result[:canvas] && progress_callback
                      progress_callback.call({
                        type: "load_canvas",
                        canvas: result[:canvas],
                        canvas_data: result[:canvas_data] || result[:task_list] || {}
                      })
                    end

                    # Auto-update task progress if we have a task list
                    update_task_for_tool_completion(tool_call[:name], parsed_args, result[:success], progress_callback)

                    # Notify UI about tool detection first
                    progress_callback&.call({
                      type: "tool_detected",
                      name: tool_call[:name],
                      tool_id: tool_call[:id]
                    })

                    # Then notify about tool execution
                    progress_callback&.call({
                      type: "tool_start",
                      name: tool_call[:name],
                      arguments: parsed_args
                    })
                  end

                  # Now we need to continue AGAIN with these new tool results
                  # This creates a recursive pattern for chained tool calls

                  # Add the assistant's message with the continuation tool use
                  tool_use_content = []
                  if continuation_message.present?
                    tool_use_content << { text: continuation_message }
                  end

                  continuation_tool_calls.each do |tool_call|
                    tool_use_content << {
                      tool_use: {
                        tool_use_id: tool_call[:id],
                        name: tool_call[:name],
                        input: tool_call[:arguments].to_s.strip.empty? ? {} : JSON.parse(tool_call[:arguments])
                      }
                    }
                  end

                  conversation_messages << {
                    role: "assistant",
                    content: tool_use_content
                  }

                  # Add continuation tool results
                  continuation_tool_calls.zip(continuation_results).each do |tool_call, result|
                    conversation_messages << {
                      role: "user",
                      content: [
                        {
                          tool_result: {
                            tool_use_id: tool_call[:id],
                            content: [
                              {
                                json: sanitize_for_bedrock(
                                  if result.is_a?(Hash)
                                    if result[:success]
                                      # For successful results, include all relevant data
                                      {
                                        success: true,
                                        message: result[:message] || "Tool executed successfully",
                                        data: result.except(:success, :message, :canvas, :canvas_data, :task_list)
                                      }
                                    else
                                      # For failures, include error information
                                      {
                                        success: false,
                                        error: result[:error] || "Tool execution failed",
                                        details: result[:details] || result.except(:success, :error)
                                      }
                                    end
                                  else
                                    # Fallback for non-hash results
                                    { success: true, result: result }
                                  end
                                )
                              }
                            ]
                          }
                        }
                      ]
                    }
                  end

                  # Stream another continuation
                  progress_callback&.call("💬 streaming")

                  additional_message = ""
                  more_tool_calls = []

                  @ai_service.send_message_streaming(
                    system_prompt,
                    conversation_messages,
                    max_tokens: 25000,
                    temperature: 0.7,
                    json_mode: false,
                    tools: tools
                  ) do |chunk|
                    if chunk[:type] == :content && chunk[:content]
                      additional_message += chunk[:content]
                      progress_callback&.call({
                        type: "content_chunk",
                        content: chunk[:content]
                      })
                    elsif chunk[:type] == :tool_use_start
                      # AI wants even more tools!
                      Rails.logger.info "AI wants another tool in final continuation: #{chunk[:tool_name]}"
                      more_tool_calls << {
                        id: chunk[:tool_id],
                        name: chunk[:tool_name],
                        arguments: ""
                      }
                    elsif chunk[:type] == :tool_use && more_tool_calls.any?
                      more_tool_calls.last[:arguments] += chunk[:tool_use].input || ""
                    elsif chunk[:type] == :complete
                      Rails.logger.info "Final continuation complete: #{additional_message.length} chars"
                    end
                  end

                  # Continue tool execution in a loop until done or limit reached
                  max_tool_iterations = 20
                  total_tool_calls = tool_calls.length + continuation_tool_calls.length

                  # Keep executing tools while the AI wants more and we haven't hit the limit
                  while more_tool_calls.any? && total_tool_calls < max_tool_iterations
                    Rails.logger.info "AI requested #{more_tool_calls.length} more tools (total: #{total_tool_calls + more_tool_calls.length})"

                    # Execute the additional tools
                    more_results = []
                    more_tool_calls.each do |tool_call|
                      Rails.logger.info "Processing additional tool: #{tool_call[:name]} with arguments: #{tool_call[:arguments]}"

                      # Parse arguments
                      parsed_args = if tool_call[:arguments].is_a?(String)
                        begin
                          tool_call[:arguments].to_s.strip.empty? ? {} : JSON.parse(tool_call[:arguments])
                        rescue JSON::ParserError => e
                          Rails.logger.error "Failed to parse tool arguments: #{e.message}"
                          {}
                        end
                      else
                        tool_call[:arguments]
                      end

                      result = execute_tool_by_name(tool_call[:name], parsed_args)
                      more_results << result

                      # Notify tool completion
                      progress_callback&.call({
                        type: "tool_complete",
                        name: tool_call[:name],
                        success: result[:success] || false
                      })

                      # Check if the tool result includes a canvas to load
                      if result[:canvas] && progress_callback
                        progress_callback.call({
                          type: "load_canvas",
                          canvas: result[:canvas],
                          canvas_data: result[:canvas_data] || result[:task_list] || {}
                        })
                      end

                      # Notify UI about tool detection and execution
                      progress_callback&.call({
                        type: "tool_detected",
                        name: tool_call[:name],
                        tool_id: tool_call[:id]
                      })
                      progress_callback&.call({
                        type: "tool_start",
                        name: tool_call[:name],
                        arguments: parsed_args
                      })

                      # Auto-update task progress if we have a task list
                      update_task_for_tool_completion(tool_call[:name], parsed_args, result[:success], progress_callback)
                    end

                    # Add the assistant's message with the additional tool use
                    additional_tool_content = []
                    if additional_message.present?
                      additional_tool_content << { text: additional_message }
                    end

                    more_tool_calls.each do |tool_call|
                      additional_tool_content << {
                        tool_use: {
                          tool_use_id: tool_call[:id],
                          name: tool_call[:name],
                          input: tool_call[:arguments].to_s.strip.empty? ? {} : JSON.parse(tool_call[:arguments])
                        }
                      }
                    end

                    conversation_messages << {
                      role: "assistant",
                      content: additional_tool_content
                    }

                    # Add tool results
                    more_tool_calls.zip(more_results).each do |tool_call, result|
                      conversation_messages << {
                        role: "user",
                        content: [
                          {
                            tool_result: {
                              tool_use_id: tool_call[:id],
                              content: [
                                {
                                  json: sanitize_for_bedrock(
                                    if result.is_a?(Hash)
                                      if result[:success]
                                        # For successful results, include all relevant data
                                        {
                                          success: true,
                                          message: result[:message] || "Tool executed successfully",
                                          data: result.except(:success, :message, :canvas, :canvas_data, :task_list)
                                        }
                                      else
                                        # For failures, include error information
                                        {
                                          success: false,
                                          error: result[:error] || "Tool execution failed",
                                          details: result[:details] || result.except(:success, :error)
                                        }
                                      end
                                    else
                                      # Fallback for non-hash results
                                      { success: true, result: result }
                                    end
                                  )
                                }
                              ]
                            }
                          }
                        ]
                      }
                    end

                    # Update totals and prepare for next iteration
                    total_tool_calls += more_tool_calls.length

                    # Update tool_calls for the next iteration
                    all_tool_calls = tool_calls + continuation_tool_calls + more_tool_calls

                    # Clear for next iteration
                    more_tool_calls = []

                    # One more round of streaming to see if AI wants more tools
                    progress_callback&.call("💬 streaming")

                    last_message = ""

                    @ai_service.send_message_streaming(
                      system_prompt,
                      conversation_messages,
                      max_tokens: 25000,
                      temperature: 0.7,
                      json_mode: false,
                      tools: tools
                    ) do |chunk|
                      if chunk[:type] == :content && chunk[:content]
                        last_message += chunk[:content]
                        progress_callback&.call({
                          type: "content_chunk",
                          content: chunk[:content]
                        })
                      elsif chunk[:type] == :tool_use_start
                        more_tool_calls << {
                          id: chunk[:tool_id],
                          name: chunk[:tool_name],
                          arguments: ""
                        }
                      elsif chunk[:type] == :tool_use && more_tool_calls.any?
                        more_tool_calls.last[:arguments] += chunk[:tool_use].input || ""
                      elsif chunk[:type] == :complete
                        Rails.logger.info "Tool iteration complete: #{last_message.length} chars"
                      end
                    end

                    # If there's a message before more tools, save it
                    if last_message.present? && more_tool_calls.any?
                      content_hash = last_message.strip
                      unless @saved_message_content.include?(content_hash)
                        Rails.logger.info "💾 Saving last message before more tools: #{last_message}"
                        progress_callback&.call({
                          type: "save_message",
                          content: last_message,
                          role: "assistant"
                        })
                        @saved_message_content.add(content_hash)
                      else
                        Rails.logger.info "⚠️ Skipping duplicate last message: #{last_message.strip.first(50)}..."
                      end
                    end

                    # Update the additional_message with the latest
                    additional_message = last_message if last_message.present?
                  end # end while loop

                  # After the loop, set the final message
                  if total_tool_calls >= max_tool_iterations && more_tool_calls.any?
                    Rails.logger.warn "Tool call limit reached (#{max_tool_iterations}) - AI still wants to use #{more_tool_calls.length} more tools"
                    if additional_message.empty?
                      additional_message = "I've executed #{total_tool_calls} tools to complete your request. The task progress is shown in the canvas above."
                    end
                  end

                  # Use the last non-empty message
                  final_message = additional_message.present? ? additional_message : continuation_message
                else
                  # No more tools requested in first continuation
                  final_message = continuation_message
                end

              rescue => e
                Rails.logger.error "Error getting final response: #{e.message}"
                Rails.logger.error "Bedrock API error details: #{e.class.name}"
                # Fall back to the initial message if we have one
                final_message = initial_message unless initial_message.empty?
              end
            end

            # Ensure we have a final message
            final_message ||= initial_message.empty? ? "I've processed your request." : initial_message

            # Return with tool results
            Rails.logger.info "Returning with @suggested_canvas: #{@suggested_canvas.inspect}"
            return {
              message: final_message,
              message_already_saved: @messages_saved_during_streaming || false,
              tools_used: true,
              tools_list: tool_calls.map { |t| t[:name] },
              success_count: results.count { |r| r[:success] },
              error_count: results.count { |r| !r[:success] },
              canvas: @suggested_canvas,
              canvas_data: @canvas_data,
              mode: detected_mode
            }
          else
            # No tools, just return the message
            # But first check if the message is JSON that contains canvas instructions
            if accumulated_content.strip.start_with?("{") && accumulated_content.strip.end_with?("}")
              begin
                parsed = JSON.parse(accumulated_content)
                if parsed["canvas"]
                  @suggested_canvas = parsed["canvas"]
                  Rails.logger.info "Canvas found in JSON response: #{@suggested_canvas}"
                end
                # Use the message from the JSON if available
                accumulated_content = parsed["message"] if parsed["message"]
              rescue JSON::ParserError
                # Not valid JSON, use as-is
              end
            end

            return {
              message: accumulated_content,
              message_already_saved: @messages_saved_during_streaming || false,
              tools_used: false,
              canvas: @suggested_canvas,
              mode: detected_mode
            }
          end
        end
      end


      # For builder mode or complex queries, use non-streaming for tool detection
      response = @ai_service.send_message(
        system_prompt,
        conversation_messages,

        max_tokens: 25000,
        temperature: 0.7,
        json_mode: true  # Force JSON output for tool calling
      )

      progress_callback&.call("📝 Parsing #{@ai_provider_name}'s response...")

      # Parse response for JSON structure with message and tool calls
      if tool_calls = parse_function_calls_from_response(response)
        Rails.logger.info "Detected function calls: #{tool_calls.map { |t| t[:name] }}"

        # Show what tools will be executed
        tool_names = tool_calls.map { |t| t[:name] }.uniq
        if tool_names.include?("get_schema")
          progress_callback&.call("🔍 Discovering database schema...")
        end
        if tool_names.include?("get_data")
          progress_callback&.call("📊 Querying your marketing data...")
        end
        if tool_names.include?("create_object")
          progress_callback&.call("✨ Creating new marketing object...")
        end

        # Execute the tools with individual progress updates
        tool_results = execute_tools_with_progress(tool_calls, progress_callback)

        progress_callback&.call("🎯 Generating personalized response...")

        # Send the real tool results back to AI service for an updated response
        final_message = generate_response_with_tool_results(user_message, @parsed_user_message, tool_results)

        {
          message: final_message,
          tools_used: true,
          tools_list: tool_names,
          success_count: tool_results.count { |r| r[:success] },
          error_count: tool_results.count { |r| !r[:success] },
          canvas: @suggested_canvas,
          canvas_data: @canvas_data
        }
      else
        # No tools needed, extract message from response
        # If @parsed_user_message is nil, try to extract from response
        final_message = @parsed_user_message
        if final_message.nil? && response.is_a?(String)
          begin
            parsed = JSON.parse(response)
            final_message = parsed["message"] || response
          rescue JSON::ParserError
            final_message = response
          end
        end

        {
          message: final_message || response,
          tools_used: false,
          canvas: @suggested_canvas,
          canvas_data: @canvas_data,
          mode: detected_mode
        }
      end

    rescue JSON::ParserError => e
      Rails.logger.error "Scout JSON parsing error: #{e.message}"
      Rails.logger.error "Response that failed to parse: #{response}"

      {
        message: "I understand your request, but I'm having trouble processing it right now. Could you try rephrasing your question?",
        tools_used: false,
        error: "JSON parsing failed"
      }
    rescue => e
      Rails.logger.error "Scout generic tools error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        message: "I'm experiencing some technical difficulties. Please try again or let me know if you need help with something else.",
        tools_used: false,
        error: e.message
      }
    end
  end

  # Public method to execute analyze_landing_page_request tool
  def execute_analyze_landing_page_request(args)
    execute_analyze_landing_page_request_internal(args)
  end

  # Set context for Scout to be aware of current view/page
  def set_context(context)
    @context = context
    Rails.logger.info "🎯 Scout context set: #{context.inspect}"

    # Store context in session for persistence (convert to hash for serialization)
    if @session_id && context.present?
      # Convert ActionController::Parameters to hash for safe caching
      cacheable_context = context.is_a?(ActionController::Parameters) ? context.to_unsafe_h : context
      Rails.cache.write("scout_context_#{@session_id}", cacheable_context, expires_in: 1.hour)
    end
  end

  # Get current context (from instance or session)
  def get_context
    return @context if @context.present?

    # Try to load from session cache
    if @session_id
      cached_context = Rails.cache.read("scout_context_#{@session_id}")
      if cached_context.present?
        @context = cached_context
        Rails.logger.info "🔄 Restored Scout context from cache: #{@context.inspect}"
      end
    end

    @context
  end

  private

  def get_bedrock_tools
    # Define tools in Bedrock format
    tools = []

    # Add canvas loading tool
    tools << {
      name: "load_canvas",
      description: "Load a specific canvas view in the Scout interface",
      parameters: {
        type: "object",
        properties: {
          canvas_name: {
            type: "string",
            description: "The name of the canvas to load",
            enum: [ "campaign_viewer", "analytics_dashboard", "landing_page_viewer", "contact_viewer", "email_template_viewer", "task_progress" ]
          }
        },
        required: [ "canvas_name" ]
      }
    }

    # Add our existing tools
    TOOLS.each do |tool|
      tools << {
        name: tool[:name],
        description: tool[:description],
        parameters: tool[:parameters]
      }
    end

    tools
  end

  def build_system_prompt_with_dynamic_schema(context_type = nil, mode = nil)
    available_models = ScoutDataRegistry.available_object_types

    # Dynamic AI identity based on provider
    ai_identity = case Rails.application.config.ai_service
    when :grok
      "You are Amos, the AI business automation assistant powered by Grok. You have access to a comprehensive toolset for managing and automating business operations."
    when :claude
      "You are Amos, the AI business automation assistant powered by Claude. You have access to a comprehensive toolset for managing and automating business operations."
    when :openai
      "You are Amos, the AI business automation assistant powered by OpenAI GPT-5. You have access to a comprehensive toolset for managing and automating business operations."
    when :bedrock
      "You are Amos, the AI business automation assistant powered by AWS Bedrock. You have access to a comprehensive toolset for managing and automating business operations."
    else
      "You are Amos, the AI business automation assistant. You have access to a comprehensive toolset for managing and automating business operations."
    end

    # Add context-specific focus based on what the user is working with
    context_focus = case context_type
    when "email_template", "email_template_editor", "email_template_viewer"
      <<~CONTEXT

      **CURRENT FOCUS: EMAIL TEMPLATES**
      The user is working with email templates. Prioritize helping with:
      - Creating engaging email content with proper personalization using {{variables}}
      - Improving subject lines for better open rates
      - Structuring email content for clarity and conversions
      - Testing and previewing templates
      - Linking templates to campaigns

      Remember: ALWAYS use {{first_name}}, {{last_name}}, {{email}}, {{full_name}} for variables, never [brackets].
      CONTEXT
    when "landing_page", "landing_page_editor", "landing_page_viewer", "landing_page_generator"
      <<~CONTEXT

      **CURRENT FOCUS: LANDING PAGES**
      The user is working with landing pages. Prioritize helping with:
      - Creating high-converting landing pages with clear CTAs
      - Optimizing page layout and design for conversions
      - A/B testing suggestions
      - Form optimization and lead capture
      - Mobile responsiveness
      CONTEXT
    when "campaign", "campaign_viewer"
      <<~CONTEXT

      **CURRENT FOCUS: EMAIL CAMPAIGNS**
      The user is working with email campaigns. Prioritize helping with:
      - Campaign strategy and timing
      - Selecting the right audience segments
      - Analyzing campaign performance metrics
      - Improving open and click rates
      - Linking appropriate email templates
      CONTEXT
    when "contact", "contact_viewer", "contact_generator"
      <<~CONTEXT

      **CURRENT FOCUS: CONTACTS & AUDIENCES**
      The user is working with contacts. Prioritize helping with:
      - Organizing and segmenting contact lists
      - Importing and managing contact data
      - Creating targeted contact groups
      - Data hygiene and deduplication
      - GDPR compliance and opt-out management
      CONTEXT
    when "analytics", "analytics_dashboard"
      <<~CONTEXT

      **CURRENT FOCUS: ANALYTICS & REPORTING**
      The user is viewing analytics. Prioritize helping with:
      - Interpreting campaign performance data
      - Identifying trends and insights
      - Recommending optimization strategies
      - Comparing campaign effectiveness
      - ROI calculations and reporting
      CONTEXT
    else
      ""
    end

    # Determine if we should be in advisor mode based on mode parameter or context
    mode_prompt = case mode
    when "advisor"
      build_advisor_prompt
    when "builder"
      build_builder_prompt
    else
      # Default to builder mode
      build_builder_prompt
    end

    <<~PROMPT
      #{ai_identity}
      #{context_focus}
      #{mode_prompt}
      USER CONTEXT:
      - User: #{@user.first_name} #{@user.last_name}
      - Entity: #{@entity.name}

      AVAILABLE TOOLS:
      1. get_data(object_type, filters, options) - Query any data model
      2. create_object(object_type, data) - Create basic objects (campaigns, contacts, groups)
      3. get_schema(object_type) - Get REAL database schema and field information. Before creating or updating records, call get_schema to confirm field names and types. For contacts, note the boolean field 'lead' (default true) and 'status' values: active, inactive, unsubscribed.
      4. generate_ai_landing_page(title, description, page_type) - Create sophisticated AI-powered landing pages (PREFERRED for NEW landing pages)
      5. update_landing_page_status(landing_page_id, status) - Publish, unpublish, or archive landing pages
      6. update_landing_page_content(landing_page_id, instruction) - Update content of existing landing pages (PREFERRED for EDITING existing pages)
      7. revert_landing_page_to_version(landing_page_id, version_id) - Revert landing pages to previous versions
      8. load_form_submissions(landing_page_id) - View form submissions from landing pages
      9. load_workflow_analytics(period) - View workflow performance and analytics

      AVAILABLE DATA MODELS:
      #{available_models.join(', ')}

      **ADDITIONAL SERVICES AVAILABLE:**
#{'      '}
      INTELLIGENT CANVAS:
      You can load data viewers and interactive canvases to display information visually.
      Available canvases: landing_page_viewer, landing_page_generator, contact_viewer, contact_generator,
      campaign_viewer, analytics_dashboard, email_template_viewer, email_template_editor, dynamic_canvas, task_progress
#{'      '}
      DYNAMIC VISUALIZATIONS:
      When users ask for analysis, comparisons, or custom reports, use create_dynamic_visualization to build
      custom HTML visualizations. This is perfect for:
      - Year-over-year comparisons
      - Custom metric dashboards
      - Campaign performance analysis
      - ROI calculations and reports
      - Any custom data visualization
#{'      '}
      When users ask to "show", "view", or "see" data, suggest loading the appropriate canvas.
      Example responses with canvas suggestions:
      - "Let me show you your landing pages" → suggest loading landing_page_viewer canvas
      - "Here are your contacts" → suggest loading contact_viewer canvas#{'  '}
      - "I'll create a landing page for you" → suggest loading landing_page_generator canvas
#{'      '}
      LANDING PAGE FORM TEMPLATES:
      You can reference predefined form templates when creating landing pages with html_content.
      Available templates: contact_form, newsletter_signup, lead_magnet, demo_request, event_registration,#{' '}
      free_trial, quote_request, consultation_booking
#{'      '}
      Each template provides Bootstrap-styled HTML forms that submit to /api/v1/contacts with proper field names.
      When generating landing page HTML, you can include these forms or create custom forms following the same pattern.
#{'      '}
      MODEL METADATA:
      All business models have comprehensive metadata including purpose, business context, relationships,#{' '}
      and usage examples. This helps you understand how models relate and what they're used for in marketing.

      **CRITICAL: WHEN TO USE TOOLS - BE AGGRESSIVE!**
#{'      '}
      If the user mentions ANY of these, USE TOOLS IMMEDIATELY:
      - "create a contact" → use create_object("contacts", {email: ..., first_name: ..., last_name: ...})
      - "create a campaign" → use create_object("campaigns", {...})#{'  '}
      - "create a landing page" → use generate_ai_landing_page(title, description, page_type) - NEVER use create_object for landing pages!
      - "update landing page" or "change landing page" → use update_landing_page_content(landing_page_id, instruction)
      - "revert landing page" or "undo changes" → use revert_landing_page_to_version(landing_page_id)
      - "publish landing page" → use update_landing_page_status(landing_page_id, "published")
      - "unpublish landing page" → use update_landing_page_status(landing_page_id, "draft")
      - "show me campaigns" → use get_data("campaigns", ...)
      - "performance" or "metrics" → use get_data with include_metrics: true
      - "recent" → use get_data with date filters

      **LANDING PAGE OPERATIONS - CRITICAL:**
#{'      '}
      FOR NEW LANDING PAGES:
      - Use generate_ai_landing_page (uses Claude AI with professional landing page expertise)
      - Never use create_object for landing pages - it only creates empty records
      - The AI system creates complete HTML with Bootstrap, responsive design, contact forms, and professional styling
      - Available page types: lead_generation, product_launch, event_registration, newsletter_signup, free_trial, demo_request
#{'      '}
      FOR EXISTING LANDING PAGES:
      - Use update_landing_page_content when user wants to modify, change, update, or improve existing pages
      - CRITICAL: If user says "update my landing page" or similar WITHOUT a specific ID, ALWAYS use get_data("landing_pages") FIRST to find their existing pages
      - Look for recent pages, pages matching keywords from their request, or ask user to clarify which page
      - NEVER create new pages when user clearly wants to update existing ones
      - Use get_data("landing_pages") to find existing pages when user refers to them by name/title
      - Create automatic backups before updates (enabled by default)
#{'      '}
      DECISION LOGIC:
      - "Create/make/build a new landing page" → generate_ai_landing_page
      - "Update/change/modify my landing page" → get_data("landing_pages") first, then update_landing_page_content#{'  '}
      - "Update page 7" or "change landing page 15" → update_landing_page_content directly with ID
#{'      '}
      FOR ROLLBACKS:
      - Use revert_landing_page_to_version when user wants to undo changes or go back to previous version
      - If no version_id specified, automatically reverts to most recent backup

      LANDING PAGE CONVERSATION EXAMPLES:
      - "Create a landing page for our new product" → generate_ai_landing_page(title, description, page_type)
      - "Update my holiday landing page to mention 50% off" → get_data("landing_pages") first, then update_landing_page_content(page_id, instruction)
      - "Change the headline on page 7" → update_landing_page_content(7, "change the headline to...")
      - "I don't like the changes, go back" → revert_landing_page_to_version(page_id)
      - "Undo the last update to my landing page" → revert_landing_page_to_version(page_id)
#{'      '}
      **INTEGRATION & DATA ANALYTICS SYSTEM:**
#{'      '}
      FETCHING EXTERNAL DATA:
      - Use list_connections to show available integrations (Stripe, Shopify, HubSpot, etc.)
      - Use invoke_operation to fetch data from connected services
      - Data is automatically saved as Artifacts with schema, sample, and row count
      - Results are streamed to dynamic_canvas for immediate visualization
#{'      '}
      ANALYZING DATA WITH ARTIFACTS:
      - When data is fetched via invoke_operation, it creates an Artifact (stored dataset)
      - Use aggregate_artifact_data to perform analytics on Artifacts:
        * group_by_field: Group by any field and apply count/sum/avg/min/max
        * group_by_time: Create time-series aggregations (hour/day/week/month/year)
        * top_k: Find the most common values in a field
        * simple_stats: Calculate statistics across all numeric fields
      - Aggregation results are automatically visualized in dynamic_canvas
      - Use fetch_next_page when an artifact has more data available (check has_more flag)
#{'      '}
      EXAMPLE ANALYTICS WORKFLOWS:
      1. "Show me my Stripe customers by plan":
         - invoke_operation to fetch customers → creates Artifact
         - aggregate_artifact_data with group_by_field on 'plan' field
#{'      '}
      2. "Analyze customer signups over time":
         - invoke_operation to fetch customers → creates Artifact#{'  '}
         - aggregate_artifact_data with group_by_time on 'created' field
#{'      '}
      3. "Top 10 products by revenue":
         - invoke_operation to fetch orders → creates Artifact
         - aggregate_artifact_data with top_k on 'product' field, with sum aggregation on 'amount'
#{'      '}
      ARTIFACT-FIRST APPROACH:
      - Never include raw data arrays in responses
      - Reference data by artifact_id
      - Use aggregation tools for analysis
      - Dynamic canvas handles visualization automatically
#{'      '}
      CONTACT CREATION EXAMPLES:
      - "create contact John Doe john@doe.com" → create_object("contacts", {email: "john@doe.com", first_name: "John", last_name: "Doe"})
      - "add contact for Jane Smith jane@smith.com" → create_object("contacts", {email: "jane@smith.com", first_name: "Jane", last_name: "Smith"})

      **EMAIL TEMPLATE VARIABLES - CRITICAL:**
      When creating email templates, ALWAYS use double curly braces {{}} for variable substitution:
      - Use {{first_name}} NOT [first_name]
      - Use {{last_name}} NOT [last_name]
      - Use {{email}} NOT [email]
      - Use {{full_name}} NOT [full_name]
#{'      '}
      Example: "Hello {{first_name}}, thank you for your interest in {{company_name}}."
#{'      '}
      NEVER use square brackets [] for variables - the system only recognizes double curly braces {{}}.

      **SCHEMA DISCOVERY - CRITICAL FOR SUCCESS:**
#{'      '}
      ALWAYS use get_schema(object_type) FIRST when:
      - You need to query data but aren't sure what fields exist
      - You encounter database column errors
      - You're creating objects and need to know required fields
      - The user asks about data structure or available fields

      The get_schema tool shows you ACTUAL database columns, not assumptions!

      **For Data Queries:**
      - Use get_schema("campaigns") to see real available fields
      - Then use get_data("campaigns", filters, options) with correct field names
      - Example workflow: get_schema("campaigns") → see actual columns → get_data("campaigns", {status: "sent"}, {limit: 10})

      **For Creating Objects:**
      - Use get_schema(object_type) first to understand required fields
      - Then use create_object(object_type, data)
      - Example: get_schema("contacts") → see required fields → create_object("contacts", {email: "john@doe.com"})

      **QUERY OPTIONS:**
      - limit: number (default 10, max 100)
      - include_metrics: boolean (includes performance data)
      - order_by: "field_name desc/asc" (use ONLY fields that exist!)
      - filters: object with field names that actually exist

      **AVAILABLE CANVASES (optional):**
      When appropriate, you can suggest loading a visual canvas:
      - "analytics_dashboard" - for performance metrics and analytics
      - "landing_page_viewer" - to show existing landing pages
      - "landing_page_generator" - to create new landing pages
      - "campaign_viewer" - to show email campaigns
      - "campaign_editor" - to edit/create campaigns
      - "contact_viewer" - to show contacts
      - "contact_generator" - to create new contacts

**CRITICAL CANVAS LOADING INSTRUCTIONS:**
When the user explicitly asks to "load", "show", "open" or "view" a specific canvas:
- YOU MUST USE THE load_canvas TOOL - do not respond with JSON
- The load_canvas tool takes a canvas_name parameter
- Available canvases: campaign_viewer, campaign_editor, analytics_dashboard, landing_page_viewer, contact_viewer, email_template_viewer, task_progress
- Example: User says "load the campaign viewer" → Use tool: load_canvas with canvas_name: "campaign_viewer"

      #{mode == 'advisor' ? advisor_response_format : builder_response_format}


      **CRITICAL EXAMPLES FOR "analyze my campaigns":**

      When user asks "analyze my campaigns" or "help me analyze my email campaigns", respond with:

      {
        "message": "I'll analyze your email campaigns right now! Let me pull your campaign data and provide detailed performance insights.",
        "tool_calls": [
          {
            "name": "get_schema",
            "arguments": {"object_type": "campaigns"}
          },
          {
            "name": "get_data",#{' '}
            "arguments": {"object_type": "campaigns", "filters": {}, "options": {"limit": 20, "include_metrics": true}}
          }
        ],
        "canvas": "analytics_dashboard"
      }

      **Key Rules:**
      1. Always respond with valid JSON
      2. The "message" field is what the user will see
      3. Use get_schema proactively to avoid database errors
      4. Only reference fields that actually exist in the database
      5. When in doubt, check the schema first!
      6. Be transparent: tell users when you're discovering their data structure
      7. **BE AGGRESSIVE WITH TOOLS** - If user wants to analyze/query anything, USE TOOLS!
      8. **NO LINE BREAKS OR NEWLINES** in the message field - use \\n instead
      9. **ALWAYS use tools for analysis requests**
      10. **FORMAT RESPONSES IN MARKDOWN** for better readability:
          - Use ## headers for main sections
          - Use ### for subsections#{'  '}
          - Use **bold** for important metrics and emphasis
          - Use bullet points (- ) for lists
          - Use numbered lists (1. ) for recommendations
          - Use > blockquotes for key insights
          - Use `code` formatting for technical terms
          - Keep paragraphs short and scannable
          - NEVER use HTML tags like <strong>, <em>, <ul>, <li>, etc.
          - ALWAYS use Markdown syntax: **bold**, *italic*, - bullet, etc.

      **MARKDOWN FORMATTING EXAMPLE:**
      "## 📊 Campaign Analysis\\n\\n**Overall Performance:**\\n- 6 total campaigns\\n- 3 completed, 1 in progress, 2 drafts\\n\\n### 🎯 Top Performer\\n**\\"new test\\"** campaign:\\n- **50% click rate** (excellent!)\\n- 100% delivery rate\\n- 0 unsubscribes\\n\\n### ⚠️ Areas for Improvement\\n1. **Open rates at 0%** - check spam folders\\n2. **Subject line optimization** needed\\n3. **A/B testing** recommended"
#{'      '}
      **NEVER use HTML formatting. ALWAYS use Markdown.**

      Be conversational in your message but use tools intelligently behind the scenes.
    PROMPT
  end

  def format_available_models(models)
    models.map do |model|
      status = []
      status << "Query" if model[:can_query]
      status << "Create" if model[:can_create]
      "- #{model[:model_name]}: #{model[:description]} (#{status.join(', ')})"
    end.join("\n")
  end

  def format_query_options(options)
    lines = []
    lines << "Filters:"
    lines << "  - date_range: #{options[:filters][:date_ranges].join(', ')}"
    lines << "  - status: #{options[:filters][:status_values].join(', ')}"
    lines << "Options:"
    lines << "  - limit: #{options[:options][:limit]}"
    lines << "  - order_by: #{options[:options][:order_by]}"
    lines << "  - include_metrics: #{options[:options][:include_metrics]}"
    lines.join("\n")
  end

  def parse_function_calls_from_response(response)
    Rails.logger.info "Raw #{@ai_provider_name} response: #{response}"

    begin
      # First, try to parse the response as-is (for properly formatted JSON)
      parsed = JSON.parse(response)
      Rails.logger.info "Successfully parsed JSON response: #{parsed.keys}"

      @parsed_user_message = parsed["message"]
      @suggested_canvas = parsed["canvas"]
      tool_calls = parsed["tool_calls"]

      if tool_calls && tool_calls.is_a?(Array) && tool_calls.any?
        Rails.logger.info "Found #{tool_calls.length} tool calls: #{tool_calls.map { |t| t['name'] }}"
        tool_calls.map do |call|
          {
            name: call["name"],
            arguments: call["arguments"] || {}
          }
        end
      else
        Rails.logger.warn "No tool calls found in response. Tool_calls field: #{tool_calls.inspect}"
        nil
      end

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse #{@ai_provider_name} response as JSON: #{e.message}"
      Rails.logger.error "Response length: #{response.length}, Sample: #{response[0..200]}"

      # Only try cleaning if the initial parse failed
      begin
        # Clean the response to handle newlines and control characters
        cleaned_response = response.to_s
          .force_encoding("UTF-8")
          .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "") # Remove control chars but keep newlines

        # Try to parse the cleaned response
        parsed = JSON.parse(cleaned_response)
        Rails.logger.info "Successfully parsed cleaned JSON response: #{parsed.keys}"

        @parsed_user_message = parsed["message"]
        @suggested_canvas = parsed["canvas"]
        tool_calls = parsed["tool_calls"]

        if tool_calls && tool_calls.is_a?(Array) && tool_calls.any?
          Rails.logger.info "Found #{tool_calls.length} tool calls after cleaning: #{tool_calls.map { |t| t['name'] }}"
          tool_calls.map do |call|
            {
              name: call["name"],
              arguments: call["arguments"] || {}
            }
          end
        else
          Rails.logger.warn "No tool calls found after cleaning. Tool_calls field: #{tool_calls.inspect}"
          nil
        end

      rescue JSON::ParserError => e2
        Rails.logger.error "Failed to parse cleaned #{@ai_provider_name} response: #{e2.message}"

        # Try to extract message from malformed JSON as fallback
        extracted_message = extract_message_from_malformed_json(response)
        @parsed_user_message = extracted_message || "I apologize, but I'm having trouble processing that request. Could you please try rephrasing it?"

        nil
      end

    rescue => e
      Rails.logger.error "Unexpected error parsing #{@ai_provider_name} response: #{e.message}"
      @parsed_user_message = "I encountered an unexpected error. Please try again."
      nil
    end
  end

  private

  def extract_message_from_malformed_json(response)
    # Try different patterns to extract the message content from malformed JSON

    # First, try to clean the JSON and parse again
    begin
      # Remove potential control characters that break JSON parsing
      cleaned = response.gsub(/[\x00-\x1F\x7F]/, " ")
      parsed = JSON.parse(cleaned)
      return parsed["message"] if parsed.is_a?(Hash) && parsed["message"]
    rescue
      # Continue with pattern matching if cleaning doesn't work
    end

    # Pattern 1: Look for "message": "content" with proper escaping
    if match = response.match(/"message"\s*:\s*"((?:[^"\\]|\\.)*)"/m)
      # Unescape the matched content
      return match[1].gsub('\n', "\n").gsub('\"', '"').gsub("\\\\", "\\")
    end

    # Pattern 2: Try to extract from Claude's typical JSON structure
    if response.include?('"message":') && response.include?('"tool_calls":')
      # Extract everything between "message": " and " before the next field
      start_pos = response.index('"message":')
      if start_pos
        # Find the start of the actual message content
        message_start = response.index('"', start_pos + 10)
        if message_start
          # Find the end of the message (looking for "," or "}" that ends this field)
          message_end = find_json_string_end(response, message_start + 1)
          if message_end
            message_content = response[message_start + 1...message_end]
            return message_content.gsub('\n', "\n").gsub('\"', '"').gsub("\\\\", "\\")
          end
        end
      end
    end

    # Pattern 3: Look for message content after a JSON structure
    if match = response.match(/\}\s*(.+)$/m)
      return match[1].strip
    end

      # Fallback: Return the full response (it's likely plain text from advisor mode)
      response
  end

  def find_json_string_end(str, start_pos)
    pos = start_pos
    while pos < str.length
      char = str[pos]
      if char == '"' && str[pos-1] != "\\"
        return pos
      end
      pos += 1
    end
    nil
  end

  def execute_tools(tool_calls)
    results = []

    tool_calls.each do |tool_call|
      result = case tool_call[:name]
      when "get_data"
        execute_get_data(tool_call[:arguments])
      when "create_object"
        execute_create_object(tool_call[:arguments])
      when "get_schema"
        execute_get_schema(tool_call[:arguments])
      when "generate_ai_landing_page"
        execute_generate_ai_landing_page(tool_call[:arguments])
      when "update_landing_page_status"
        execute_update_landing_page_status(tool_call[:arguments])
      when "update_landing_page_content"
        execute_update_landing_page_content(tool_call[:arguments])
      when "revert_landing_page_to_version"
        execute_revert_landing_page_to_version(tool_call[:arguments])
      when "link_template_to_campaign"
        execute_link_template_to_campaign(tool_call[:arguments])
      when "create_dynamic_visualization"
        execute_create_dynamic_visualization(tool_call[:arguments])
      when "manage_task_list"
        execute_manage_task_list(tool_call[:arguments])
      else
        { success: false, error: "Unknown tool: #{tool_call[:name]}" }
      end

      results << {
        tool_name: tool_call[:name],
        arguments: tool_call[:arguments],
        result: result,
        success: !result.key?(:error)
      }
    end

    results
  end


  def execute_tools_with_progress(tool_calls, progress_callback = nil)
    results = []

    tool_calls.each_with_index do |tool_call, index|
      # Show progress for each tool
      case tool_call[:name]
      when "get_schema"
        object_type = tool_call[:arguments]["object_type"]
        progress_callback&.call("🔍 Checking #{object_type} database schema...")
      when "get_data"
        object_type = tool_call[:arguments]["object_type"]
        progress_callback&.call("📊 Fetching #{object_type} data...")
      when "create_object"
        object_type = tool_call[:arguments]["object_type"]
        progress_callback&.call("✨ Creating new #{object_type}...")
      when "generate_ai_landing_page"
        progress_callback&.call("🤖 Generating AI-powered landing page...")
      when "update_landing_page_status"
        progress_callback&.call("📝 Updating landing page status...")
      when "update_landing_page_content"
        progress_callback&.call({ type: "intermediate_message", content: "✨ Updating landing page content...", role: "assistant" })
      when "revert_landing_page_to_version"
        progress_callback&.call({ type: "intermediate_message", content: "⏪ Reverting landing page to previous version...", role: "assistant" })
      when "link_template_to_campaign"
        progress_callback&.call({ type: "intermediate_message", content: "🔗 Linking email template to campaign...", role: "assistant" })
      when "create_dynamic_visualization"
        progress_callback&.call({ type: "intermediate_message", content: "📊 Creating custom visualization...", role: "assistant" })
      when "manage_task_list"
        action = tool_call[:arguments]["action"]
        case action
        when "create"
          progress_callback&.call({ type: "intermediate_message", content: "📋 Creating task list...", role: "assistant" })
        when "complete_task"
          progress_callback&.call({ type: "intermediate_message", content: "✅ Completing task...", role: "assistant" })
        else
          progress_callback&.call({ type: "intermediate_message", content: "📝 Updating task list...", role: "assistant" })
        end
      end

      result = case tool_call[:name]
      when "get_data"
        execute_get_data(tool_call[:arguments])
      when "create_object"
        execute_create_object(tool_call[:arguments])
      when "get_schema"
        execute_get_schema(tool_call[:arguments])
      when "generate_ai_landing_page"
        execute_generate_ai_landing_page(tool_call[:arguments])
      when "update_landing_page_status"
        execute_update_landing_page_status(tool_call[:arguments])
      when "update_landing_page_content"
        execute_update_landing_page_content(tool_call[:arguments])
      when "revert_landing_page_to_version"
        execute_revert_landing_page_to_version(tool_call[:arguments])
      when "link_template_to_campaign"
        execute_link_template_to_campaign(tool_call[:arguments])
      when "create_dynamic_visualization"
        execute_create_dynamic_visualization(tool_call[:arguments])
      when "manage_task_list"
        execute_manage_task_list(tool_call[:arguments])
      else
        { success: false, error: "Unknown tool: #{tool_call[:name]}" }
      end

      results << {
        tool_name: tool_call[:name],
        arguments: tool_call[:arguments],
        result: result,
        success: !result.key?(:error)
      }

      # Show completion for each tool
      if result[:success]
        case tool_call[:name]
        when "get_schema"
          progress_callback&.call({ type: "intermediate_message", content: "✅ Schema discovered for #{tool_call[:arguments]['object_type']}", role: "assistant" })
        when "get_data"
          count = result.dig(:data, :count) || 0
          progress_callback&.call({ type: "intermediate_message", content: "✅ Found #{count} records", role: "assistant" })
        when "create_object"
          progress_callback&.call({ type: "intermediate_message", content: "✅ Successfully created #{tool_call[:arguments]['object_type']}", role: "assistant" })
        when "manage_task_list"
          action = tool_call[:arguments]["action"]
          case action
          when "create"
            progress_callback&.call({ type: "intermediate_message", content: "✅ Task list created", role: "assistant" })
          when "complete_task"
            progress_callback&.call({ type: "intermediate_message", content: "✅ Task completed", role: "assistant" })
          else
            progress_callback&.call({ type: "intermediate_message", content: "✅ Task list updated", role: "assistant" })
          end
        end
      else
        progress_callback&.call({ type: "intermediate_message", content: "❌ Tool execution failed: #{result[:error]}", role: "assistant" })
      end
    end

    results
  end

  def execute_get_data(args)
    object_type = normalize_object_type(args["object_type"])
    filters = args["filters"] || {}
    options = args["options"] || {}

    Rails.logger.info "Executing get_data: object_type=#{object_type}, filters=#{filters}, options=#{options}"

    begin
      # Use existing UniversalQueryEngine
      query_engine = UniversalQueryEngine.new(@user, @entity)

      # Convert to format expected by query engine
      # Fix common field name variations
      fixed_filters = fix_field_names(filters, object_type)
      fixed_order_by = fix_field_names_in_order_by(options["order_by"], object_type)

      query_params = {
        objects: [ object_type ],
        filters: fixed_filters,
        limit: options["limit"] || 20,
        order_by: fixed_order_by,
        include_metrics: options["include_metrics"] != false,
        include_relationships: options["include_relationships"]
      }

      Rails.logger.info "Query params: #{query_params}"

      result = query_engine.execute_get_data(query_params)

      Rails.logger.info "Query result success: #{result[:success]}"
      if result[:success] && result[:data]
        result[:data].each do |obj_type, data|
          Rails.logger.info "Found #{data[:count] || 0} #{obj_type}"
        end
      end

      if result[:success]
        {
          success: true,
          data: result[:data],
          metadata: result[:metadata]
        }
      else
        Rails.logger.error "Query failed: #{result[:error]}"
        { error: result[:error] }
      end
    rescue => e
      Rails.logger.error "get_data error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { error: "Query failed: #{e.message}" }
    end
  end

  def execute_create_object(args)
    object_type = args["object_type"]
    data = args["data"]

    Rails.logger.info "Executing create_object: object_type=#{object_type}, data=#{data}"

    begin
      # Get the model class (use singular form for model lookup)
      singular_type = singularize_object_type(object_type)
      model_class = object_type_to_class(singular_type)
      return { error: "Unknown object type: #{object_type}" } unless model_class

      # Add automatic scoping
      scoped_data = data.dup
      scoped_data["entity_id"] = @entity.id if model_class.column_names.include?("entity_id")
      scoped_data["user_id"] = @user.id if model_class.column_names.include?("user_id")

      # Apply field mapping fixes for common naming inconsistencies
      scoped_data = apply_field_mapping(scoped_data, object_type)

      # Create the object
      new_object = model_class.create!(scoped_data)

      {
        success: true,
        object_id: new_object.id,
        object_type: object_type,
        data: format_created_object(new_object),
        message: "Successfully created #{object_type}"
      }
    rescue ActiveRecord::RecordInvalid => e
      { error: "Validation failed: #{e.record.errors.full_messages.join(', ')}" }
    rescue => e
      Rails.logger.error "create_object error: #{e.message}"
      { error: "Creation failed: #{e.message}" }
    end
  end

  def execute_get_schema(args)
    object_type = args["object_type"]

    Rails.logger.info "Schema discovery requested for: #{object_type}"

    # Normalize object type (handle both singular and plural)
    normalized_type = object_type.to_s.downcase
    normalized_type = normalized_type.pluralize unless normalized_type.end_with?("s")

    # Use dynamic schema discovery
    schema = ScoutDataRegistry.get_actual_schema(normalized_type)

    if schema
      Rails.logger.info "Schema discovered for #{normalized_type}: #{schema[:actual_columns].length} columns, #{schema[:record_count]} records"

      {
        success: true,
        object_type: normalized_type,
        schema: schema,
        summary: "Found #{schema[:actual_columns].length} actual database columns for #{normalized_type}. #{schema[:record_count]} records exist."
      }
    else
      available_types = ScoutDataRegistry.available_object_types.join(", ")
      {
        success: false,
        error: "Unknown object type: #{object_type}. Available types: #{available_types}"
      }
    end
  end

  def object_type_to_class(object_type)
    case object_type.to_s.downcase
    when "campaign"
      Campaign
    when "contact"
      Contact
    when "contact_group"
      ContactGroup
    when "landing_page"
      LandingPage
    when "email_template"
      EmailTemplate
    when "business_profile"
      BusinessProfile
    else
      nil
    end
  end

  def format_created_object(object)
    # Return basic object information
    result = { id: object.id }

    # Add common display fields
    display_fields = %w[name title subject email first_name last_name]
    display_fields.each do |field|
      if object.respond_to?(field) && object.send(field).present?
        result[field] = object.send(field)
      end
    end

    # Add contact-specific fields
    if object.is_a?(Contact)
      result[:lead] = object.lead
      result[:status] = object.status
    end

    result
  end

  def generate_response_with_tool_results(user_message, initial_message, tool_results)
    # Format tool results for AI
    results_summary = format_tool_results_for_ai(tool_results)

    Rails.logger.info "=== TOOL RESULTS SUMMARY FOR #{@ai_provider_name.upcase} ==="
    Rails.logger.info "Number of tool results: #{tool_results.length}"
    tool_results.each_with_index do |result, i|
      Rails.logger.info "Tool #{i+1}: #{result[:tool_name]} - Success: #{result[:success]}"
      if result[:success] && result[:result]
        case result[:tool_name]
        when "get_data"
          if result[:result][:data]
            Rails.logger.info "  Data keys: #{result[:result][:data].keys}"
            result[:result][:data].each do |type, data|
              if data.is_a?(Hash) && data[:records]
                Rails.logger.info "    #{type}: #{data[:records]&.length || 0} records"
              else
                Rails.logger.info "    #{type}: #{data.inspect}"
              end
            end
          end
        when "create_object"
          Rails.logger.info "  Created object: #{result[:result].inspect}"
        when "get_schema"
          Rails.logger.info "  Schema result: #{result[:result][:object_type] || 'unknown'}"
        else
          Rails.logger.info "  Result: #{result[:result].inspect}"
        end
      end
    end
    Rails.logger.info "=== END TOOL RESULTS SUMMARY ==="

    # Check if we have any successful results
    successful_results = tool_results.select { |r| r[:success] }
    failed_results = tool_results.select { |r| !r[:success] }

    # If all tools failed, return a simplified error message
    if successful_results.empty?
      error_summary = failed_results.map { |r| r[:result][:error] }.join(", ")
      Rails.logger.error "All tools failed: #{error_summary}"
      return "I tried to access your marketing data but ran into some technical issues: #{error_summary}. Please try again or let me know if you need help with something else."
    end

    final_prompt = <<~PROMPT
      You provided this initial response to the user: "#{initial_message}"

      You also requested tool execution, and here are the REAL results from those tools:

      TOOL RESULTS:
      #{results_summary}

      USER'S ORIGINAL REQUEST: #{user_message}

      Now provide an updated, conversational response that incorporates the actual data. You should:
      1. Use the REAL data from the tool results, not assumptions
      2. Be specific about what was found or created#{'  '}
      3. Don't mention "tools" - just present the information naturally
      4. If any tools failed, explain it helpfully
      5. Suggest relevant next steps based on the actual results
      #{has_metrics?(tool_results) ? "6. ANALYZE THE SPECIFIC METRICS provided in the data above\n      7. Provide actionable insights based on the real performance numbers" : "6. Focus on confirming the action was completed successfully"}

      IMPORTANT: Format your response using Markdown for better readability:
      - Use **bold** for emphasis (e.g., **50% open rate**)
      - Use bullet points (-) for lists
      - Use ### for section headers
      - Do NOT use HTML tags like <strong> or <em>
      - Replace newlines with \\n in your response

      Provide your updated response in Markdown format (not JSON):
    PROMPT

    # Log the complete prompt being sent to Claude
    Rails.logger.info "=== COMPLETE PROMPT BEING SENT TO #{@ai_provider_name.upcase} ==="
    Rails.logger.info final_prompt
    Rails.logger.info "=== END #{@ai_provider_name.upcase} PROMPT ==="
    Rails.logger.info "Prompt length: #{final_prompt.length} characters"

    # Ensure we're not sending empty content
    if final_prompt.strip.empty?
      Rails.logger.error "Empty prompt generated!"
      return "I'm having trouble processing that request right now. Please try again."
    end

    # Send to Claude with a fallback message
    begin
      response = @ai_service.send_message(final_prompt, "Please provide your response.")
      response.present? ? response : "I was able to process your request but had trouble generating a response. Please try again."
    rescue => e
      Rails.logger.error "Error generating final response: #{e.message}"
      "I found your data but had trouble generating a detailed response. Please try asking again or be more specific about what you'd like to know."
    end
  end

  def format_tool_results_for_ai(tool_results)
    formatted = []

    tool_results.each do |result|
      if result[:success]
        case result[:tool_name]
        when "get_data"
          formatted << format_data_results(result[:result])
        when "create_object"
          formatted << format_creation_results(result[:result])
        when "get_schema"
          formatted << format_schema_results(result[:result])
        when "generate_ai_landing_page"
          formatted << format_landing_page_generation_results(result[:result])
        when "update_landing_page_status"
          formatted << format_landing_page_status_results(result[:result])
        when "link_template_to_campaign"
          formatted << result[:result][:message]
        when "manage_task_list"
          formatted << format_task_list_results(result[:result])
        else
          # Generic success format for other tools
          formatted << format_generic_tool_success(result[:tool_name], result[:result])
        end
      else
        formatted << "#{result[:tool_name]} failed: #{result[:result][:error]}"
      end
    end

    formatted.join("\n\n")
  end

  def format_data_results(result)
    return "No data found" unless result[:data]

    # Log what we're sending to Claude
    Rails.logger.info "=== FORMATTING DATA FOR #{@ai_provider_name.upcase} ==="
    Rails.logger.info "Result structure: #{result.keys}"
    Rails.logger.info "Data keys: #{result[:data].keys}"

    formatted_sections = []

    result[:data].each do |object_type, data|
      records = data[:records] || []

      if records.any?
        Rails.logger.info "Formatting #{records.length} #{object_type} records for #{@ai_provider_name}"

        section = []
        section << "=== #{object_type.upcase} DATA (#{records.length} records) ==="

        records.each_with_index do |record, index|
          section << "\n#{object_type.singularize.capitalize} ##{index + 1}:"

          # Include all relevant fields based on object type
          case object_type
          when "campaigns"
            section << format_campaign_for_ai(record)
          when "contacts"
            section << format_contact_for_ai(record)
          when "landing_pages"
            section << format_landing_page_for_ai(record)
          else
            section << format_generic_object_for_ai(record)
          end
        end

        formatted_sections << section.join("\n")
      else
        formatted_sections << "No #{object_type} found"
      end
    end

    final_result = formatted_sections.join("\n\n")

    # Log the final formatted result
    Rails.logger.info "=== FINAL FORMATTED DATA FOR #{@ai_provider_name.upcase} ==="
    Rails.logger.info final_result
    Rails.logger.info "=== END #{@ai_provider_name.upcase} DATA ==="

    final_result
  end

  def format_campaign_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE CAMPAIGN DATA TO #{@ai_provider_name.upcase} ==="

    # Convert the record to a readable format for AI
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    elsif record.is_a?(Hash)
      data = record
    else
      data = record.as_json rescue record.to_h rescue record.inspect
    end

    Rails.logger.info "Campaign data being sent: #{data.inspect}"

    # Format as clean, readable text for AI
    lines = []
    lines << "  COMPLETE CAMPAIGN DATA:"

    data.each do |key, value|
      if value.is_a?(Hash)
        lines << "    #{key}:"
        value.each do |sub_key, sub_value|
          lines << "      #{sub_key}: #{sub_value}"
        end
      else
        lines << "    #{key}: #{value}"
      end
    end

    lines.join("\n")
  end

  def format_contact_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE CONTACT DATA TO #{@ai_provider_name.upcase} ==="

    # Convert to readable format
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    else
      data = record.attributes rescue record.to_h
    end

    Rails.logger.info "Contact data being sent: #{data.inspect}"

    lines = []
    lines << "  CONTACT RECORD:"
    lines << "    - ID: #{data['id']}"
    lines << "    - Name: #{data['first_name']} #{data['last_name']}"
    lines << "    - Email: #{data['email']}"
    lines << "    - Created: #{data['created_at']}"
    lines << "    - Groups: #{data['contact_groups']&.map { |g| g['name'] }&.join(', ') || 'None'}"

    # Add engagement metrics if available
    if data["email_deliveries"]
      lines << "    - Email Performance: #{data['email_deliveries'].length} emails sent"
    end

    lines.join("\n")
  end

  def format_landing_page_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE LANDING PAGE DATA TO #{@ai_provider_name.upcase} ==="

    # Convert to readable format
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    else
      data = record.attributes rescue record.to_h
    end

    Rails.logger.info "Landing page data being sent: #{data.inspect}"

    lines = []
    lines << "  LANDING PAGE RECORD:"
    lines << "    - ID: #{data['id']}"
    lines << "    - Title: #{data['title']}"
    lines << "    - Slug: #{data['slug']}"
    lines << "    - Status: #{data['status']}"
    lines << "    - Description: #{data['description']}"
    lines << "    - Created: #{data['created_at']}"

    # Add content preview if available
    if data["html_content"]
      content_preview = data["html_content"].to_s.strip[0..100] + "..."
      lines << "    - Content Preview: #{content_preview}"
    end

    lines.join("\n")
  end

  def format_generic_object_for_ai(record)
    Rails.logger.info "=== SENDING COMPLETE GENERIC OBJECT DATA TO #{@ai_provider_name.upcase} ==="

    # Convert to readable format
    if record.respond_to?(:to_json)
      data = JSON.parse(record.to_json)
    else
      data = record.attributes rescue record.to_h
    end

    Rails.logger.info "Generic object data being sent: #{data.inspect}"

    lines = []
    lines << "  OBJECT RECORD:"
    data.each do |key, value|
      lines << "    - #{key.humanize}: #{value}"
    end

    lines.join("\n")
  end

  def format_creation_results(result)
    if result[:success]
      "Successfully created #{result[:object_type]}: #{result[:message]}"
    else
      "Failed to create object: #{result[:error]}"
    end
  end

  def format_schema_results(result)
    if result[:success]
      schema = result[:schema]
      available_columns = schema[:actual_columns] || []
      available_fields = schema[:available_fields] || []

      "Schema for #{schema[:model]} (#{schema[:object_type]}):\n" +
      "Database columns: #{available_columns.join(', ')}\n" +
      "Queryable fields: #{available_fields.join(', ')}\n" +
      "Record count: #{schema[:record_count]}\n" +
      "Relationships: #{(schema[:relationships] || []).join(', ')}"
    else
      "Failed to get schema: #{result[:error]}"
    end
  end

  def format_landing_page_generation_results(result)
    return "Landing page generation failed" unless result[:success]

    landing_page_data = result[:data] || {}

    formatted = []
    formatted << "=== LANDING PAGE SUCCESSFULLY CREATED ==="
    formatted << "✅ Successfully created landing page: '#{landing_page_data[:title]}'"
    formatted << "📄 Page ID: #{landing_page_data[:id]}"
    formatted << "🏷️  Status: #{landing_page_data[:status]}"
    formatted << "🔗 Slug: #{landing_page_data[:slug]}"
    formatted << "📝 Description: #{landing_page_data[:description]}"
    formatted << ""
    formatted << "🤖 AI Generation Status: #{result[:ai_generation_status]}"
    formatted << "📋 The landing page has been created and AI content generation is running in the background."
    formatted << "🎯 User can now see their new page in the landing page list."

    formatted.join("\n")
  end

  def format_landing_page_status_results(result)
    return "Landing page status update failed" unless result[:success]

    landing_page_data = result[:data] || {}
    action = case landing_page_data[:status]
    when "published" then "published"
    when "draft" then "unpublished"
    when "archived" then "archived"
    else "updated"
    end

    formatted = []
    formatted << "=== LANDING PAGE STATUS UPDATED ==="
    formatted << "✅ Successfully #{action} landing page: '#{landing_page_data[:title]}'"
    formatted << "📄 Page ID: #{landing_page_data[:id]}"
    formatted << "🏷️  New Status: #{landing_page_data[:status]}"
    formatted << "🔗 Slug: #{landing_page_data[:slug]}"

    formatted.join("\n")
  end

  def format_generic_tool_success(tool_name, result)
    if result[:message]
      "✅ #{tool_name} completed successfully: #{result[:message]}"
    elsif result[:success]
      "✅ #{tool_name} completed successfully"
    else
      "#{tool_name} result: #{result.inspect}"
    end
  end

  def format_task_list_results(result)
    return result[:error] if result[:error]

    if result[:task_list]
      task_list = result[:task_list]
      tasks = task_list[:tasks]

      if result[:progress]
        "#{result[:message]}\n#{result[:progress]}"
      elsif tasks && tasks.any?
        completed = tasks.count { |t| t[:status] == "completed" }
        total = tasks.size
        "#{result[:message]} (#{completed}/#{total} tasks)"
      else
        result[:message]
      end
    else
      result[:message] || "Task list operation completed"
    end
  end

  def fix_field_names(filters, object_type)
    return filters unless filters.is_a?(Hash)

    fixed_filters = {}

    filters.each do |key, value|
      fixed_key = map_field_name(key.to_s, object_type)
      fixed_filters[fixed_key] = value
    end

    fixed_filters
  end

  def fix_field_names_in_order_by(order_by, object_type)
    return order_by unless order_by.is_a?(String)

    # Split field and direction
    parts = order_by.split(" ")
    field = parts[0]
    direction = parts[1] || "desc"

    fixed_field = map_field_name(field, object_type)
    "#{fixed_field} #{direction}"
  end

  def map_field_name(field, object_type)
    # Common field mappings
    case object_type.to_s.downcase
    when "campaign", "campaigns"
      case field.to_s.downcase
      when "send_date"
        "sent_at"
      when "create_date"
        "created_at"
      when "update_date"
        "updated_at"
      else
        field
      end
    when "contact", "contacts"
      case field.to_s.downcase
      when "create_date"
        "created_at"
      when "update_date"
        "updated_at"
      else
        field
      end
    else
      field
    end
  end

  def normalize_object_type(object_type)
    # Convert singular to plural forms expected by the query engine
    case object_type.to_s.downcase
    when "campaign"
      "campaigns"
    when "contact"
      "contacts"
    when "contact_group"
      "contact_groups"
    when "landing_page"
      "landing_pages"
    when "email_template"
      "email_templates"
    when "business_profile"
      "business_profiles"
    else
      # If already plural or unknown, return as-is
      object_type
    end
  end

  def singularize_object_type(object_type)
    # Convert plural to singular forms for model class lookup
    case object_type.to_s.downcase
    when "campaigns"
      "campaign"
    when "contacts"
      "contact"
    when "contact_groups"
      "contact_group"
    when "landing_pages"
      "landing_page"
    when "email_templates"
      "email_template"
    when "business_profiles"
      "business_profile"
    else
      # If already singular or unknown, return as-is
      object_type
    end
  end

  def format_conversation_for_ai(conversation_history, user_message)
    # Format conversation messages for AI consumption (converse API format)
    messages = []

    # Add conversation history (limit to recent messages to avoid token limits)
    recent_history = conversation_history.last(10) # Last 10 messages for context

    recent_history.each do |msg|
      role = msg[:role] == "user" ? "user" : "assistant"
      content = msg[:content]

      if content.present?
        # Ensure content is always an array for converse API
        content_array = if content.is_a?(String)
          [ { text: content } ]
        elsif content.is_a?(Array)
          # If it's already an array, extract the text from it
          # This handles cases where content might be [{ text: "..." }] already
          if content.first.is_a?(Hash) && content.first[:text]
            [ { text: content.first[:text] } ]
          else
            [ { text: content.to_s } ]
          end
        else
          [ { text: content.to_s } ]
        end

        messages << { role: role, content: content_array }
      end
    end

    # Add current message
    messages << { role: "user", content: [ { text: user_message } ] }

    Rails.logger.info "Formatted conversation: #{messages.length} messages total"
    Rails.logger.info "Messages: #{messages.map { |m| "#{m[:role]}: #{m[:content].first[:text][0..50] rescue m[:content].to_s[0..50]}..." }.join(' | ')}"

    messages
  end

  def apply_field_mapping(data, object_type)
    mapped_data = data.dup

    # Landing page field mappings
    if object_type == "landing_pages" || object_type == "landing_page"
      if mapped_data["name"].present? && mapped_data["title"].blank?
        mapped_data["title"] = mapped_data.delete("name")
      end
    end

    # Campaign field mappings
    if object_type == "campaigns" || object_type == "campaign"
      if mapped_data["title"].present? && mapped_data["name"].blank?
        mapped_data["name"] = mapped_data["title"]
      end
    end

    mapped_data
  end

  def execute_generate_ai_landing_page(args)
    title = args["title"].to_s.strip
    # Clamp description to model limit to avoid validation errors
    description = args["description"].to_s.strip
    description = description[0, 1000]
    title = title[0, 255] if title.present?
    page_type = args["page_type"] || "lead_generation"
    campaign_id = args["campaign_id"]

    return { error: "title is required" } unless title.present?
    return { error: "description is required" } unless description.present?

    begin
      # Create the basic landing page record first
      landing_page = @entity.landing_pages.create!(
        title: title,
        description: description,
        status: "draft",
        user_id: @user.id,
        campaign_id: campaign_id
      )

      # Get business profile for AI context
      business_profile = @entity.business_profiles.first

      # Use the new interactive framework for landing page generation
      Rails.logger.info "Scout: Landing page #{landing_page.id} created - ready for interactive generation"

      # For now, we'll mark it as requiring interactive generation
      # The user can then use the interactive wizard to complete it
      landing_page.update!(
        metadata: {
          generation_requested: true,
          page_type: page_type,
          requested_at: Time.current
        }
      )

      # Suggest loading the landing page viewer canvas to show the new page in the list
      @suggested_canvas = "landing_page_viewer"
      @canvas_data = {}

      {
        success: true,
        object_id: landing_page.id,
        object_type: "landing_pages",
        data: {
          id: landing_page.id,
          title: landing_page.title,
          description: landing_page.description,
          status: landing_page.status,
          slug: landing_page.slug
        },
        message: "✅ Successfully created landing page '#{title}'! Click on it below to open the interactive wizard and generate content.",
        ai_generation_status: "Ready for interactive content generation",
        canvas: "landing_page_viewer",
        canvas_data: {}
      }
    rescue ActiveRecord::RecordInvalid => e
      { error: "Landing page creation failed: #{e.record.errors.full_messages.join(', ')}" }
    rescue => e
      Rails.logger.error "generate_ai_landing_page error: #{e.message}"
      { error: "AI landing page generation failed: #{e.message}" }
    end
  end

  def has_metrics?(tool_results)
    # Check if any tool results contain metrics/performance data
    tool_results.any? do |result|
      data = result[:result]
      next false unless data.is_a?(Hash)

      # Look for common metrics indicators
      has_metrics_data = data.key?(:metrics) ||
                        data.key?(:performance) ||
                        data.key?(:analytics) ||
                        data.key?(:stats) ||
                        (data.key?(:data) && data[:data].is_a?(Array) && data[:data].any? { |item| item.is_a?(Hash) && (item.key?("open_rate") || item.key?("click_rate") || item.key?("sent_count")) })

      has_metrics_data
    end
  end

  def execute_update_landing_page_status(args)
    landing_page_id = args["landing_page_id"]
    status = args["status"]

    return { error: "landing_page_id is required" } unless landing_page_id.present?
    return { error: "status is required" } unless status.present?

    unless %w[draft published archived].include?(status)
      return { error: "status must be one of: draft, published, archived" }
    end

    begin
      landing_page = @entity.landing_pages.find(landing_page_id)

      # Check if landing page has content before publishing
      if status == "published" && !landing_page.has_content?
        return { error: "Cannot publish landing page without content. Please generate content first." }
      end

      landing_page.update!(status: status)

      status_action = case status
      when "published" then "published"
      when "draft" then "unpublished"
      when "archived" then "archived"
      end

      # Set canvas refresh data
      @suggested_canvas = "landing_page_details"
      @canvas_data = { landing_page_id: landing_page.id }

      {
        success: true,
        object_id: landing_page.id,
        object_type: "landing_pages",
        data: {
          id: landing_page.id,
          title: landing_page.title,
          status: landing_page.status,
          slug: landing_page.slug
        },
        message: "Successfully #{status_action} landing page '#{landing_page.title}'",
        canvas: "landing_page_details",
        canvas_data: { landing_page_id: landing_page.id }
      }
    rescue ActiveRecord::RecordNotFound
      { error: "Landing page with ID #{landing_page_id} not found" }
    rescue ActiveRecord::RecordInvalid => e
      { error: "Status update failed: #{e.record.errors.full_messages.join(', ')}" }
    rescue => e
      Rails.logger.error "update_landing_page_status error: #{e.message}"
      { error: "Status update failed: #{e.message}" }
    end
  end

  def execute_update_landing_page_content(args)
    landing_page_id = args["landing_page_id"]
    instruction = args["instruction"]
    create_backup = args.fetch("create_backup", true)

    return { error: "landing_page_id is required" } unless landing_page_id.present?
    return { error: "instruction is required" } unless instruction.present?

    begin
      landing_page = @entity.landing_pages.find(landing_page_id)

      # Create backup version if requested and content exists
      if create_backup && landing_page.has_content?
        landing_page.create_version_backup("Before update: #{instruction.truncate(100)}")
      end

      # Get business profile for context
      business_profile = @entity.business_profiles.first || @user.business_profile

      # Store job status in cache BEFORE enqueueing for immediate SSE pickup
      job_status_key = "job_status_#{@user.id}_#{landing_page.id}"
      Rails.cache.write(job_status_key, {
        type: "job_started",
        job_type: "landing_page_update",
        landing_page_id: landing_page.id,
        message: "Updating landing page content...",
        timestamp: Time.current.iso8601,
        status: "processing"
      }, expires_in: 30.minutes)

      Rails.logger.info "📊 Pre-stored job status for immediate SSE pickup: #{job_status_key}"

      # Create a job to apply the content change
      job = ApplyHtmlLandingPageChangeJob.perform_later(
        landing_page.id,
        instruction,
        @entity.id,
        @user.id,
        business_profile&.id
      )

      # Set canvas refresh data
      @suggested_canvas = "landing_page_details"
      @canvas_data = { landing_page_id: landing_page.id }

      {
        success: true,
        object_id: landing_page.id,
        object_type: "landing_pages",
        data: {
          id: landing_page.id,
          title: landing_page.title,
          status: landing_page.status,
          slug: landing_page.slug,
          job_id: job.job_id
        },
        message: "Successfully started content update for landing page '#{landing_page.title}'. Changes will be applied shortly.",
        canvas: "landing_page_details",
        canvas_data: { landing_page_id: landing_page.id }
      }
    rescue ActiveRecord::RecordNotFound
      { error: "Landing page with ID #{landing_page_id} not found" }
    rescue => e
      Rails.logger.error "update_landing_page_content error: #{e.message}"
      { error: "Content update failed: #{e.message}" }
    end
  end

  def execute_load_form_submissions(args)
    landing_page_id = args[:landing_page_id]
    filters = args[:filters] || {}

    return { error: "landing_page_id is required" } unless landing_page_id.present?

    begin
      # Find the landing page
      landing_page = @entity.landing_pages.find_by(id: landing_page_id, user: @user)
      return { error: "Landing page not found" } unless landing_page

      # Load submissions data
      submissions_data = load_form_submissions_data_for_page(landing_page, filters)

      # Set canvas data for loading
      @suggested_canvas = "form_submissions"
      @canvas_data = submissions_data

      {
        success: true,
        object_type: "landing_page_submissions",
        data: submissions_data,
        message: "📊 Loaded #{submissions_data[:stats][:total]} form submissions for '#{landing_page.title}'. " \
                 "Conversion rate: #{submissions_data[:stats][:conversion_rate]}%",
        canvas: "form_submissions",
        canvas_data: submissions_data
      }
    rescue ActiveRecord::RecordNotFound
      { error: "Landing page not found" }
    rescue => e
      Rails.logger.error "load_form_submissions error: #{e.message}"
      { error: "Failed to load form submissions: #{e.message}" }
    end
  end

  def load_form_submissions_data_for_page(landing_page, filters = {})
    # Base query for submissions from this landing page
    base_query = landing_page.landing_page_submissions.includes(:contact)

    # Apply filters
    if filters[:form_type].present?
      base_query = base_query.where(form_type: filters[:form_type])
    end

    if filters[:status].present?
      base_query = base_query.where(status: filters[:status])
    end

    case filters[:time_range]
    when "today"
      base_query = base_query.today
    when "week"
      base_query = base_query.this_week
    when "month"
      base_query = base_query.this_month
    end

    # Get submissions with limit
    submissions = base_query.recent.limit(50)

    # Calculate stats
    total = base_query.count
    processed = base_query.where(status: [ "processed", "duplicate" ]).count
    pending = base_query.where(status: "pending").count
    failed = base_query.where(status: "failed").count
    spam = base_query.where(status: "spam").count
    conversion_rate = total > 0 ? (processed.to_f / total * 100).round(1) : 0.0

    # Format submissions for display
    formatted_submissions = submissions.map do |submission|
      {
        id: submission.id,
        form_type: submission.form_type,
        status: submission.status,
        submitted_at: submission.submitted_at.iso8601,
        processed_at: submission.processed_at&.iso8601,
        contact_info: submission.contact_info,
        utm_params: submission.utm_params,
        source_ip: submission.source_ip,
        referrer: submission.referrer,
        submission_data: submission.submission_data
      }
    end

    {
      submissions: formatted_submissions,
      stats: {
        total: total,
        processed: processed,
        pending: pending,
        failed: failed,
        spam: spam,
        conversion_rate: conversion_rate
      },
      landing_page: {
        id: landing_page.id,
        title: landing_page.title,
        slug: landing_page.slug
      },
      pagination: {
        current_count: formatted_submissions.length,
        total_count: total,
        has_previous: false, # TODO: Implement pagination
        has_next: formatted_submissions.length >= 50
      }
    }
  end

  def execute_load_workflow_analytics(args)
    period_days = args[:period] || 30
    period = period_days.to_i.days

    begin
      # Load analytics data
      observability = ObservabilityService.instance
      analytics_data = {
        workflow_analytics: observability.workflow_analytics(period),
        tool_analytics: observability.tool_analytics(period),
        user_analytics: observability.user_analytics(period),
        ai_metrics: observability.ai_metrics(period),
        performance_metrics: observability.performance_metrics(period),
        period_days: period_days.to_i
      }

      # Set canvas data for loading
      @suggested_canvas = "workflow_analytics"
      @canvas_data = analytics_data

      {
        success: true,
        object_type: "workflow_analytics",
        data: analytics_data,
        message: "📊 Loaded workflow analytics for the last #{period_days} days. " \
                 "#{analytics_data[:workflow_analytics][:total_workflows]} workflows started, " \
                 "#{analytics_data[:workflow_analytics][:completion_rate]}% completion rate.",
        canvas: "workflow_analytics",
        canvas_data: analytics_data
      }
    rescue => e
      Rails.logger.error "load_workflow_analytics error: #{e.message}"
      { error: "Failed to load workflow analytics: #{e.message}" }
    end
  end

  def execute_web_search(args)
    query = args["query"] || args[:query]
    num_results = args["num_results"] || args[:num_results] || 5

    return { success: false, error: "Query is required" } if query.blank?

    Rails.logger.info "🔍 Performing web search for: #{query}"

    begin
      # Use real Serper API if available, otherwise fall back to mock
      if ENV["SERPER_API_KEY"].present?
        serper = SerperApiService.new
        result = serper.search(query, num_results: num_results)

        if result[:success]
          {
            success: true,
            query: query,
            results: result[:results],
            count: result[:results].length,
            source: "serper"
          }
        else
          # Fall back to mock on error
          Rails.logger.warn "Serper API failed, using mock results: #{result[:error]}"
          mock_results = query.match?(/API|documentation|auth/i) ?
            generate_api_doc_search_results(query) :
            generate_general_search_results(query)

          {
            success: true,
            query: query,
            results: mock_results.first(num_results),
            count: mock_results.length,
            source: "mock"
          }
        end
      else
        # Use mock results when Serper is not configured
        results = query.match?(/API|documentation|auth/i) ?
          generate_api_doc_search_results(query) :
          generate_general_search_results(query)

        {
          success: true,
          query: query,
          results: results.first(num_results),
          count: results.length,
          source: "mock"
        }
      end
    rescue => e
      Rails.logger.error "Web search failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def generate_api_doc_search_results(query)
    # Extract the app name from the query
    app_name = query.match(/(\w+)\s+API/i)&.captures&.first || "Service"

    [
      {
        title: "#{app_name} API Documentation - Getting Started",
        url: "https://docs.#{app_name.downcase}.com/api/getting-started",
        snippet: "Learn how to authenticate and make your first API call to #{app_name}. Includes examples in multiple programming languages and common use cases.",
        source: "Official Documentation"
      },
      {
        title: "#{app_name} REST API Reference",
        url: "https://api.#{app_name.downcase}.com/reference",
        snippet: "Complete reference documentation for all #{app_name} API endpoints, including request/response formats, rate limits, and error codes.",
        source: "API Reference"
      },
      {
        title: "#{app_name} Authentication Guide",
        url: "https://docs.#{app_name.downcase}.com/api/authentication",
        snippet: "Detailed guide on #{app_name} authentication methods including OAuth 2.0, API keys, and JWT tokens. Best practices for secure integration.",
        source: "Security Documentation"
      },
      {
        title: "#{app_name} API Rate Limits and Best Practices",
        url: "https://docs.#{app_name.downcase}.com/api/rate-limits",
        snippet: "Understanding rate limits, quotas, and best practices for optimizing your #{app_name} API usage. Includes retry strategies and caching.",
        source: "Developer Guide"
      },
      {
        title: "#{app_name} Webhooks Documentation",
        url: "https://docs.#{app_name.downcase}.com/api/webhooks",
        snippet: "Set up webhooks to receive real-time updates from #{app_name}. Event types, payload formats, and signature verification.",
        source: "Webhooks Guide"
      }
    ]
  end

  def generate_general_search_results(query)
    [
      {
        title: "Search Result for: #{query}",
        url: "https://example.com/result1",
        snippet: "This is a relevant search result about #{query} with useful information and context.",
        source: "Web"
      },
      {
        title: "Understanding #{query} - Complete Guide",
        url: "https://example.com/guide",
        snippet: "A comprehensive guide covering all aspects of #{query} including best practices and examples.",
        source: "Tutorial"
      },
      {
        title: "Latest Updates on #{query}",
        url: "https://example.com/news",
        snippet: "Recent developments and news related to #{query}. Stay up to date with the latest information.",
        source: "News"
      }
    ]
  end

  def execute_create_rag_store(args)
    app_name = args["app_name"] || args[:app_name]
    documentation = args["documentation"] || args[:documentation] || []
    user_uploads = args["user_uploads"] || args[:user_uploads] || []
    search_results = args["search_results"] || args[:search_results] || []

    return { success: false, error: "App name is required" } if app_name.blank?

    Rails.logger.info "📚 Creating RAG store for #{app_name}"

    begin
      # Process all documentation sources
      documents_to_process = []

      # Add search results as URLs
      search_results.each do |result|
        documents_to_process << {
          type: "url",
          content: result[:url] || result["url"],
          metadata: { title: result[:title] || result["title"] }
        }
      end

      # Add user-provided documentation
      documentation.each do |doc|
        if doc.start_with?("http")
          documents_to_process << { type: "url", content: doc }
        else
          documents_to_process << { type: "text", content: doc }
        end
      end

      # Add uploaded files
      user_uploads.each do |upload|
        documents_to_process << {
          type: "file",
          content: upload[:path] || upload["path"],
          filename: upload[:filename] || upload["filename"]
        }
      end

      # Process documents to extract chunks
      processor = DocumentProcessorService.new
      processing_result = processor.process_documents(documents_to_process)

      if !processing_result[:success]
        return { success: false, error: "Document processing failed: #{processing_result[:error]}" }
      end

      # Create RAG store with Pinecone
      rag_service = RagStoreService.new
      rag_result = rag_service.create_rag_store(
        app_name,
        processing_result[:chunks],
        {
          user: @user,
          entity: @entity,
          total_sources: documents_to_process.length,
          processing_metadata: processing_result[:metadata]
        }
      )

      if rag_result[:success]
        {
          success: true,
          rag_store_id: rag_result[:rag_store_id],
          app_name: app_name,
          documents_indexed: documents_to_process.length,
          chunks_created: rag_result[:chunks_stored],
          status: "ready",
          message: "Successfully created knowledge base for #{app_name} with #{processing_result[:chunks].length} content chunks from #{documents_to_process.length} sources"
        }
      else
        { success: false, error: rag_result[:error] }
      end
    rescue => e
      Rails.logger.error "RAG store creation failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: e.message }
    end
  end

  def execute_generate_integration_config(args)
    app_name = args["app_name"] || args[:app_name]
    use_case = args["use_case"] || args[:use_case]
    rag_store_id = args["rag_store_id"] || args[:rag_store_id]

    return { success: false, error: "App name and use case are required" } if app_name.blank? || use_case.blank?

    Rails.logger.info "🔧 Generating integration config for #{app_name}"

    begin
      # Use real IntegrationBuilder service
      builder = IntegrationBuilderService.new(@user, @entity)
      result = builder.generate_integration_config(app_name, use_case, rag_store_id)

      if result[:success]
        {
          success: true,
          integration_id: result[:integration_id],
          config: result[:config],
          endpoints_created: result[:endpoints_created],
          message: result[:message]
        }
      else
        { success: false, error: result[:error] }
      end
    rescue => e
      Rails.logger.error "Integration config generation failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: e.message }
    end
  end

  def execute_test_integration_endpoint(args)
    integration_id = args["integration_id"] || args[:integration_id]
    credentials = args["credentials"] || args[:credentials] || {}
    test_params = args["test_params"] || args[:test_params] || {}

    return { success: false, error: "Integration ID and credentials are required" } if integration_id.blank? || credentials.blank?

    Rails.logger.info "🧪 Testing integration endpoint #{integration_id}"

    begin
      # Use real IntegrationTester service
      tester = IntegrationTesterService.new(@user, @entity)
      result = tester.test_endpoint(integration_id, credentials, test_params)

      # Return in expected format
      if result[:success]
        {
          success: true,
          status_code: result[:status_code],
          response_time_ms: result[:response_time_ms],
          sample_data: result[:sample_data],
          message: result[:message],
          auth_working: result[:auth_working]
        }
      else
        {
          success: false,
          error: result[:error],
          status_code: result[:status_code] || 0,
          message: result[:message],
          auth_working: result[:auth_working] || false,
          details: result[:details]
        }
      end
    rescue => e
      Rails.logger.error "Integration test failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      {
        success: false,
        error: e.message,
        status_code: 0,
        message: "Test execution failed: #{e.message}"
      }
    end
  end

  def execute_build_integration_endpoints(args)
    integration_id = args["integration_id"] || args[:integration_id]
    use_case = args["use_case"] || args[:use_case]
    rag_store_id = args["rag_store_id"] || args[:rag_store_id]

    return { success: false, error: "Integration ID is required" } if integration_id.blank?

    Rails.logger.info "🏗️ Building full integration endpoints for #{integration_id}"

    begin
      # Use real IntegrationBuilder service
      builder = IntegrationBuilderService.new(@user, @entity)
      result = builder.build_full_integration(integration_id, rag_store_id)

      if result[:success]
        {
          success: true,
          integration_id: result[:integration_id],
          endpoints_created: result[:operations_created],
          resources: result[:resources],
          message: result[:message]
        }
      else
        { success: false, error: result[:error] }
      end
    rescue => e
      Rails.logger.error "Integration build failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: e.message }
    end
  end

  def execute_store_uploaded_images(args)
    user_id = args["user_id"] || args[:user_id]
    entity_id = args["entity_id"] || args[:entity_id]
    image_data = args["image_data"] || args[:image_data]

    user = User.find(user_id)
    entity = Entity.find(entity_id)

    stored_images = []
    design_reference = nil

    # Extract images_data JSON from the form submission
    images_data_json = image_data["images_data"] || image_data[:images_data] || "{}"

    begin
      parsed_data = JSON.parse(images_data_json)
      images = parsed_data["images"] || []
      design_ref_data = parsed_data["design_reference"]

        # Process uploaded images
        images.each do |img_data|
          if img_data["type"] == "library" && img_data["asset_id"]
            # Reference existing library image
            begin
              lib_asset = ImageAsset.by_entity(entity.id).find(img_data["asset_id"])
              stored_images << {
                id: lib_asset.id,
                url: lib_asset.url,
                title: lib_asset.display_title,
                description: lib_asset.description.to_s,
                slot: img_data["slot"],
                source: "library"
              }
            rescue => e
              Rails.logger.warn "Library image not found: #{img_data['asset_id']} (#{e.message})"
            end
          elsif img_data["type"] == "upload"
          # For now, we'll create a placeholder ImageAsset record
          # The actual file upload handling will be enhanced later
          image_asset = ImageAsset.create!(
            user: user,
            entity: entity,
            title: "Landing Page Image #{img_data['slot']}",
            description: "Uploaded image for landing page (#{img_data['filename']})",
            source: "placeholder",  # Changed from 'upload' to 'placeholder'
            tags: [ "landing_page", "user_upload" ],
            metadata: {
              original_filename: img_data["filename"],
              slot: img_data["slot"]
            }
          )

            stored_images << {
            id: image_asset.id,
            url: image_asset.url || "/placeholder-image-#{img_data['slot']}.jpg",
            title: image_asset.title,
            description: image_asset.description,
            slot: img_data["slot"],
            filename: img_data["filename"]
          }
          elsif img_data["type"] == "ai_generate" && img_data["prompt"].present?
          # Generate AI image
          begin
            ai_image = ImageGenerationService.new.generate_and_store!(
              user: user,
              entity: entity,
              title: "AI Generated - Slot #{img_data['slot']}",
              description: img_data["prompt"],
              size: img_data["slot"] == 1 ? "1792x1024" : "1024x1024",  # Use DALL-E 3 supported sizes
              quality: "standard",
              tags: [ "landing_page", "ai_generated" ]
            )

            stored_images << {
              id: ai_image.id,
              url: ai_image.url,
              title: ai_image.title,
              description: ai_image.description,
              slot: img_data["slot"],
              prompt: img_data["prompt"]
            }
          rescue => e
            Rails.logger.error "Failed to generate AI image for slot #{img_data['slot']}: #{e.message}"
          end
          end
      end

      # Process design reference if uploaded
      if design_ref_data
        # For now, create a record for the design reference
        # File handling will be enhanced later
        design_reference = {
          filename: design_ref_data["filename"],
          notes: design_ref_data["notes"],
          type: design_ref_data["type"]
        }
      end

      {
        success: true,
        data: {
          stored_images: stored_images,
          design_reference: design_reference || {}  # Ensure it's always an object
        },
        message: "Processed #{stored_images.length} image(s) and stored them for your landing page"
      }

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse images data: #{e.message}"
      {
        success: true,
        data: {
          stored_images: [],
          design_reference: {}  # Ensure it's always an object
        },
        message: "No images to process"
      }
    rescue => e
      Rails.logger.error "Error storing uploaded images: #{e.message}"
      {
        success: false,
        error: "Failed to store images: #{e.message}"
      }
    end
  end

  def execute_process_landing_page_images(args)
    user_id = args["user_id"] || args[:user_id]
    entity_id = args["entity_id"] || args[:entity_id]
    image_preferences = args["image_preferences"] || args[:image_preferences]
    business_info = args["business_info"] || args[:business_info]

    user = User.find(user_id)
    entity = Entity.find(entity_id)

    image_preference = image_preferences["image_preference"] || image_preferences[:image_preference]

    case image_preference
    when "ai_generate"
      # Generate images using AI
      image_style = image_preferences["image_style"] || image_preferences[:image_style] || "professional"
      image_descriptions = image_preferences["image_descriptions"] || image_preferences[:image_descriptions] || ""
      business_name = business_info["business_name"] || business_info[:business_name] || "the business"

      generated_images = []

      # Generate hero image
      hero_prompt = "Professional #{image_style} style hero image for #{business_name}, high quality, modern, engaging"
      if image_descriptions.present?
        hero_prompt += ", #{image_descriptions}"
      end

      begin
        hero_image = ImageGenerationService.new.generate_and_store!(
          user: user,
          entity: entity,
          title: "Hero Image - #{business_name}",
          description: hero_prompt,
          size: "1200x600",
          quality: "hd",
          tags: [ "landing_page", "hero", image_style ]
        )
        generated_images << {
          id: hero_image.id,
          url: hero_image.url,
          title: hero_image.title,
          description: hero_image.description,
          type: "hero"
        }
      rescue => e
        Rails.logger.error "Failed to generate hero image: #{e.message}"
      end

      # Generate feature/content image if descriptions suggest multiple images
      if image_descriptions.present? && image_descriptions.include?(",")
        content_prompt = "Professional #{image_style} style content image for #{business_name}, supporting visual"
        begin
          content_image = ImageGenerationService.new.generate_and_store!(
            user: user,
            entity: entity,
            title: "Content Image - #{business_name}",
            description: content_prompt,
            size: "800x600",
            quality: "standard",
            tags: [ "landing_page", "content", image_style ]
          )
          generated_images << {
            id: content_image.id,
            url: content_image.url,
            title: content_image.title,
            description: content_image.description,
            type: "content"
          }
        rescue => e
          Rails.logger.error "Failed to generate content image: #{e.message}"
        end
      end

      {
        success: true,
        data: {
          processed_images: generated_images,
          image_strategy: "ai_generated"
        },
        message: "Generated #{generated_images.length} custom image(s) for your landing page",
        recommendation: "Images have been created and will be automatically integrated into your landing page design"
      }

    when "upload_own"
      # For now, return success and let user upload later in editor
      {
        success: true,
        data: {
          processed_images: [],
          image_strategy: "user_upload"
        },
        message: "Image upload prepared - you can add your images in the editor",
        recommendation: "Use the image editing tools in the landing page editor to upload your custom images"
      }

    when "use_placeholders"
      {
        success: true,
        data: {
          processed_images: [],
          image_strategy: "placeholders"
        },
        message: "Using placeholder images for now",
        recommendation: "Placeholder images will be used initially - you can replace them anytime in the editor"
      }

    when "skip_for_now"
      {
        success: true,
        data: {
          processed_images: [],
          image_strategy: "none"
        },
        message: "Skipping images for now - focusing on content",
        recommendation: "You can add images later using the landing page editor"
      }

    else
      {
        success: false,
        error: "Unknown image preference: #{image_preference}"
      }
    end
  end

  def execute_analyze_landing_page_request_internal(args)
    Rails.logger.info "Scout: Analyzing landing page request and existing business info"

    user_message = args["user_message"] || ""
    user = args["user"] || @user
    entity = args["entity"] || @entity

    # Get business profile
    business_profile = @user.business_profile || @user.ensure_business_profile

    # Analyze what we already know
    existing_info = {
      business_profile: {
        name: business_profile.name,
        industry: business_profile.industry,
        description: business_profile.description,
        target_audience: business_profile.target_audience,
        tone_of_voice: business_profile.tone_of_voice,
        values: business_profile.values,
        website: business_profile.website
      },
      entity: {
        name: entity.is_a?(Hash) ? (entity["name"] || entity[:name]) : entity.name,
        subdomain: entity.is_a?(Hash) ? (entity["subdomain"] || entity[:subdomain]) : entity.subdomain
      }
    }

    # Extract context from user message
    message_context = {
      mentions_classes: user_message.downcase.include?("class"),
      mentions_course: user_message.downcase.include?("course"),
      mentions_event: user_message.downcase.include?("event"),
      mentions_product: user_message.downcase.include?("product"),
      mentions_service: user_message.downcase.include?("service"),
      mentions_new: user_message.downcase.include?("new"),
      mentions_series: user_message.downcase.include?("series")
    }

    # Determine what additional info we need
    missing_info = []
    missing_info << "specific class/course details" if message_context[:mentions_classes] || message_context[:mentions_course]
    missing_info << "event details" if message_context[:mentions_event]
    missing_info << "product/service details" if message_context[:mentions_product] || message_context[:mentions_service]
    missing_info << "call to action"
    missing_info << "urgency/deadline information"

    {
      success: true,
      data: {
        business_profile: existing_info[:business_profile],
        entity: existing_info[:entity],
        message_context: message_context,
        missing_info: missing_info
      },
      message: "I've analyzed your business profile and the landing page request.",
      recommendation: "I have your business profile information. Now I need specific details about #{missing_info.join(', ')}"
    }
  end

  def execute_revert_landing_page_to_version(args)
    landing_page_id = args["landing_page_id"]
    version_id = args["version_id"]

    return { error: "landing_page_id is required" } unless landing_page_id.present?

    begin
      landing_page = @entity.landing_pages.find(landing_page_id)

      # If no specific version_id provided, get the most recent backup version
      if version_id.present?
        version = landing_page.landing_page_versions.find(version_id)
      else
        # Get the most recent version that has html_content
        version = landing_page.landing_page_versions
          .where("content->>'html_content' IS NOT NULL")
          .order(created_at: :desc)
          .first
      end

      return { error: "No version found to revert to" } unless version
      return { error: "Version does not contain html_content" } unless version.content.is_a?(Hash) && version.content["html_content"].present?

      # Perform the revert
      if landing_page.restore_from_version(version)
        # Set canvas refresh data
        @suggested_canvas = "landing_page_details"
        @canvas_data = { landing_page_id: landing_page.id }

        {
          success: true,
          object_id: landing_page.id,
          object_type: "landing_pages",
          data: {
            id: landing_page.id,
            title: landing_page.title,
            status: landing_page.status,
            slug: landing_page.slug,
            reverted_version_id: version.id
          },
          message: "Successfully reverted landing page '#{landing_page.title}' to version from #{version.created_at.strftime('%Y-%m-%d %H:%M')}",
          canvas: "landing_page_details",
          canvas_data: { landing_page_id: landing_page.id }
        }
      else
        { error: "Failed to revert landing page to specified version" }
      end
    rescue ActiveRecord::RecordNotFound => e
      if e.model == "LandingPage"
        { error: "Landing page with ID #{landing_page_id} not found" }
      else
        { error: "Version with ID #{version_id} not found" }
      end
    rescue => e
      Rails.logger.error "revert_landing_page_to_version error: #{e.message}"
      { error: "Revert failed: #{e.message}" }
    end
  end

  # Enhance user message with current canvas context to provide better AI understanding
  def enhance_message_with_canvas_context(user_message, current_canvas)
    return user_message unless current_canvas.present?

    enhanced_message = user_message
    canvas_context = ""

    case current_canvas["type"]
    when "landing_page_details"
      if landing_page_id = current_canvas.dig("data", "landing_page_id")
        begin
          landing_page = @entity.landing_pages.find(landing_page_id)
          canvas_context = "\n\n[CONTEXT: Currently viewing landing page ID #{landing_page_id} titled '#{landing_page.title}']"

          # If user uses vague language, make it more specific
          if user_message.match?(/\b(update|change|modify|edit)\s+(this|my|the)\s+(page|landing\s*page)\b/i)
            enhanced_message = user_message.gsub(
              /\b(update|change|modify|edit)\s+(this|my|the)\s+(page|landing\s*page)\b/i,
              "\\1 landing page ID #{landing_page_id}"
            )
          elsif user_message.match?(/\b(this|my|the)\s+(page|landing\s*page)\b/i)
            enhanced_message = user_message.gsub(
              /\b(this|my|the)\s+(page|landing\s*page)\b/i,
              "landing page ID #{landing_page_id}"
            )
          end
        rescue ActiveRecord::RecordNotFound
          canvas_context = "\n\n[CONTEXT: Currently viewing landing page canvas]"
        end
      end
    when "landing_page_viewer"
      canvas_context = "\n\n[CONTEXT: Currently viewing landing pages list]"
    when "contact_viewer"
      canvas_context = "\n\n[CONTEXT: Currently viewing contacts list]"
    when "campaign_viewer"
      canvas_context = "\n\n[CONTEXT: Currently viewing campaigns list]"
    end

    Rails.logger.info "Enhanced message: '#{user_message}' → '#{enhanced_message}#{canvas_context}'"

    enhanced_message + canvas_context
  end

  def requires_tools?(message)
    # Keywords that typically require tool usage
    tool_patterns = [
      /create|make|build|add|generate/i,
      /show\s+me|show\s+my|display|view/i,  # "show me my campaigns"
      /list.*all|get.*all/i,
      /update|change|modify|edit/i,
      /delete|remove/i,
      /link|connect|attach/i,
      /analyze.*campaigns|analyze.*data|compare.*campaigns/i,
      /my\s+(campaigns|contacts|landing\s+pages|emails)/i  # "my campaigns", "my contacts"
    ]

    tool_patterns.any? { |pattern| message.match?(pattern) }
  end

  def detect_user_intent(message)
    # Keywords that suggest advisory mode
    advisory_patterns = [
      /when\s+(is|are|should)/i,
      /what\s+(is|are|should)/i,
      /best\s+(day|time|practice)/i,
      /should\s+i/i,
      /what\s+do\s+you\s+think/i,
      /how\s+can\s+i\s+improve/i,
      /what.*recommend/i,
      /any\s+suggestions/i,
      /best\s+practice/i,
      /advice\s+on/i,
      /help\s+me\s+understand/i,
      /analyze/i,
      /strategy/i,
      /tips\s+for/i,
      /what\s+works\s+best/i,
      /is\s+it\s+better\s+to/i,
      /pros\s+and\s+cons/i,
      /compare/i,
      /why\s+is/i,
      /explain/i,
      /hello/i  # Greetings are usually advisory
    ]

    # Keywords that suggest builder mode - be more specific
    builder_patterns = [
      /create\s+.*campaign/i,
      /create\s+.*email/i,
      /create\s+a\s+new/i,
      /create.*for\s+me/i,
      /make\s+.*template/i,
      /build\s+.*page/i,
      /add\s+.*contact/i,
      /update\s+.*campaign/i,
      /change\s+.*template/i,
      /delete/i,
      /remove/i,
      /link.*to/i,
      /set\s+up/i,
      /generate\s+.*landing/i,
      /send\s+now|send\s+immediately|send\s+campaign/i,  # Be specific about "send"
      /publish/i,
      /new\s+email\s+campaign/i,
      /new\s+campaign/i
    ]

    # Check for advisory patterns first (since they're often questions)
    advisory_score = advisory_patterns.count { |pattern| message.match?(pattern) }
    builder_score = builder_patterns.count { |pattern| message.match?(pattern) }

    # Questions are almost always advisory
    advisory_score += 2 if message.strip.end_with?("?")

    Rails.logger.info "Intent detection - Message: '#{message}', Advisory: #{advisory_score}, Builder: #{builder_score}"

    advisory_score > builder_score ? "advisor" : "builder"
  end

  def build_advisor_prompt
    <<~ADVISOR

      **MODE: STRATEGIC ADVISOR**

      You are operating in ADVISOR MODE. Your role is to:
      - Provide strategic guidance and recommendations
      - Analyze data and identify opportunities
      - Share best practices and industry insights
      - Help users understand their metrics
      - Suggest improvements and optimizations
      - Explain concepts and strategies

      ADVISORY GUIDELINES:
      1. Focus on WHY and HOW rather than just WHAT
      2. Provide context and reasoning for recommendations
      3. Use data to support your insights
      4. Suggest A/B testing opportunities
      5. Share industry benchmarks when relevant
      6. Be consultative, not directive

      When analyzing data:
      - Look for trends and patterns
      - Identify areas for improvement
      - Celebrate successes
      - Provide actionable next steps

      RESPONSE FORMAT:
      When responding without tools, provide conversational, natural language responses.
      Use markdown formatting for structure (bold, lists, etc).
      Be friendly and personable in your communication.

      USE DYNAMIC VISUALIZATIONS:
      When providing analysis or comparisons, use create_dynamic_visualization to create
      custom HTML dashboards that visualize the insights. Include:
      - Metric cards with key numbers
      - Comparison tables
      - Insights and recommendations boxes
      - Visual indicators (up/down arrows, colors)

      Still use tools to GET data, but focus on ANALYZING and ADVISING rather than CREATING.
    ADVISOR
  end

  def build_builder_prompt
    <<~BUILDER

      **MODE: ACTION BUILDER**

      You are operating in BUILDER MODE. Your role is to:
      - Take immediate action on user requests
      - Create, update, and manage marketing assets
      - Execute tasks efficiently
      - Use tools proactively

      🚨 CRITICAL FIRST STEP: If your task needs 2+ tools, CREATE A TASK LIST FIRST!
      This ensures you plan properly and don't skip steps like schema checks.

      BUILDER GUIDELINES:
      1. Be action-oriented and efficient
      2. Use tools immediately when appropriate
      3. ALWAYS complete ALL requested actions - don't just say what you'll do, actually do it
      4. If the user asks for multiple things (like create AND link), execute ALL the necessary tools
      5. Confirm actions taken
      6. Suggest next steps after completing tasks
      7. If a tool returns requires_confirmation: true, explain what would happen and ask the user to confirm
      8. Never proceed with destructive actions (replacements, deletions) without explicit user confirmation
      9. 💬 COMMUNICATION: Provide interesting updates and insights as you work - users love to see your thought process!
      10. Share what you're discovering, any interesting data patterns, or helpful tips along the way

      IMPORTANT: When given a multi-step task:
      - Break it down into individual steps
      - Execute each step completely
      - Don't stop until all steps are done
      - 🗣️ COMMUNICATE throughout the process - explain what you're doing, what you found, any insights!
      - For example: "create a campaign and link a template" requires:
        1. create_object to create the campaign
        2. get_data to find the template (if needed)
        3. link_template_to_campaign to connect them

      CRITICAL: After getting data (like template IDs), ALWAYS follow through with the action (like linking).
      Don't just say "Now let me..." - actually DO IT with the appropriate tool!

      TASK MANAGEMENT - MANDATORY FOR MULTI-TOOL OPERATIONS:
      You MUST use the manage_task_list tool for ANY operation requiring 2 or more tools:
      1. ALWAYS start by creating a task list with ALL planned steps
      2. Include schema checks as explicit steps (don't assume you know the schema)
      3. Mark tasks as in_progress when you start them
      4. Mark tasks as completed when done
      5. Add new tasks if you discover additional steps needed

      REQUIRED task list usage:
      - ANY create operation (always needs: get_schema → create_object)
      - ANY operation with "and" (e.g., "create and link" needs 3+ steps)
      - Looking up data before actions (get_data → action)
      - Multi-object operations
      - ANY request that you think needs 2+ tools

      Example: "Create a campaign" requires:
      1. Get campaign schema
      2. Create campaign
      3. Show result/next steps
    BUILDER
  end

  def advisor_response_format
    <<~FORMAT
      **RESPONSE GUIDELINES:**
      - Respond naturally in conversational language using markdown formatting
      - Use tools when needed to fetch data or perform actions
      - When asked to load a canvas view, use the load_canvas tool
      - Prefer prebuilt canvases over custom views. ONLY create a dynamic visualization when the user explicitly asks for a bespoke analysis/report/visualization
        - Map requests to canvases (MUST):
          - "show my campaigns" / "open campaigns" -> load_canvas(canvas_name: "campaign_viewer")
          - "analytics" / "dashboard" / "performance" -> load_canvas(canvas_name: "analytics_dashboard")
          - "email templates" / "templates" -> load_canvas(canvas_name: "email_template_viewer")
          - "contacts" / "people" -> load_canvas(canvas_name: "contact_viewer")
        - After loading a canvas, you may fetch data or propose next actions as needed
      - Focus on analysis, insights, and recommendations

      **AVAILABLE TOOLS:**
      You have access to tools for:
      - Loading canvas views (load_canvas) - USE THIS TOOL when asked to open/load/show a canvas
      - Fetching and analyzing data (get_data, get_schema)
      - Creating visualizations (create_dynamic_visualization)
      - Managing marketing assets (various creation and update tools)
      - Task management (manage_task_list) for complex multi-step operations

      **TASK MANAGEMENT - REQUIRED FOR MULTI-TOOL ANALYSES:**
      You MUST use the manage_task_list tool for ANY analysis requiring 2+ tools:
      - Getting data from multiple sources
      - Fetching data then creating visualizations
      - Any analysis with multiple steps
      - Performance reviews, audits, comparisons

      Example: "Analyze my campaigns" requires task list:
      1. Get campaign schema (understand fields)
      2. Fetch campaign data
      3. Analyze metrics
      4. Create visualization
      5. Provide recommendations

      ALWAYS plan your analysis steps upfront with a task list!

      IMPORTANT: When the user asks to load/open/show a canvas viewer, you MUST use the load_canvas tool.
      Do NOT respond with JSON text. Use the actual tool calling mechanism.

      The system will handle tool calling automatically - just focus on helping the user.
    FORMAT
  end

  def builder_response_format
    <<~FORMAT
      **RESPONSE GUIDELINES:**
      - Respond naturally in conversational language using markdown formatting
      - Take immediate action using tools when appropriate
      - When asked to load a canvas view, use the load_canvas tool
      - Prefer prebuilt canvases over custom views. ONLY create a dynamic visualization when the user explicitly asks for a bespoke analysis/report/visualization
        - Map requests to canvases (MUST):
          - "show my campaigns" / "open campaigns" -> load_canvas(canvas_name: "campaign_viewer")
          - "analytics" / "dashboard" / "performance" -> load_canvas(canvas_name: "analytics_dashboard")
          - "email templates" / "templates" -> load_canvas(canvas_name: "email_template_viewer")
          - "contacts" / "people" -> load_canvas(canvas_name: "contact_viewer")
        - After loading a canvas, you may fetch data or propose next actions as needed
      - Confirm actions taken and suggest next steps

      **AVAILABLE TOOLS:**
      You have access to tools for:
      - Loading canvas views (load_canvas)
      - Creating and managing campaigns, contacts, landing pages, etc.
      - Fetching and displaying data
      - All marketing automation tasks

      The system will handle tool calling automatically - just focus on helping the user.
    FORMAT
  end

  def execute_link_template_to_campaign(args)
    begin
      campaign_id = args["campaign_id"]
      template_id = args["template_id"]

      # Find the campaign
      campaign = @entity.campaigns.find_by(id: campaign_id)
      return { success: false, error: "Campaign not found with ID: #{campaign_id}" } unless campaign

      # Find the template
      template = @entity.email_templates.find_by(id: template_id)
      return { success: false, error: "Email template not found with ID: #{template_id}" } unless template

      # Check if campaign already has a template
      if campaign.email_template_id.present? && campaign.email_template_id != template.id
        existing_template = campaign.email_template
        return {
          success: false,
          error: "Campaign '#{campaign.name}' already has a template linked: '#{existing_template.name}'",
          requires_confirmation: true,
          confirmation_type: "replace_template",
          data: {
            campaign_id: campaign.id,
            campaign_name: campaign.name,
            existing_template_id: existing_template.id,
            existing_template_name: existing_template.name,
            new_template_id: template.id,
            new_template_name: template.name
          },
          message: "⚠️ This campaign already has a template. Would you like to replace '#{existing_template.name}' with '#{template.name}'?"
        }
      end

      # Link the template to the campaign
      campaign.update!(email_template_id: template.id)

      {
        success: true,
        object_id: campaign.id,
        object_type: "campaigns",
        data: {
          campaign_id: campaign.id,
          campaign_name: campaign.name,
          template_id: template.id,
          template_name: template.name,
          template_subject: template.subject
        },
        message: "✅ Successfully linked template '#{template.name}' to campaign '#{campaign.name}'"
      }
    rescue => e
      Rails.logger.error "Error linking template to campaign: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def persist_task_list(task_session, cache_key, task_list)
    # Write to cache for fast access
    Rails.cache.write(cache_key, task_list, expires_in: 24.hours)

    # Persist to TaskSession for refresh persistence
    task_session.update!(
      state: { task_list: task_list },
      metadata: task_session.metadata.merge(
        updated_at: Time.current,
        task_count: task_list[:tasks]&.size || 0
      )
    )
  end

  def sanitize_for_bedrock(data)
    case data
    when Hash
      data.transform_values { |v| sanitize_for_bedrock(v) }
    when Array
      data.map { |item| sanitize_for_bedrock(item) }
    when ActiveSupport::TimeWithZone, Time, DateTime
      data.iso8601
    when Date
      data.to_s
    when ActiveRecord::Base
      # Convert ActiveRecord objects to a hash of their attributes
      sanitize_for_bedrock(data.attributes)
    else
      data
    end
  end

  def update_task_for_tool_completion(tool_name, args, success, progress_callback)
    # Check if we have an active task list
    entity_id = @entity&.id
    session_id = @session_id || SecureRandom.uuid
    cache_key = "scout_task_list_#{entity_id}_#{session_id}"

    # Try cache first, then TaskSession
    task_list = Rails.cache.read(cache_key)
    unless task_list && task_list[:tasks]
      # Try to load from TaskSession
      task_session = TaskSession.active
                               .where(user: @user)
                               .where("metadata->>'session_id' = ?", session_id)
                               .first
      task_list = task_session&.state&.dig("task_list")
    end
    return unless task_list && task_list[:tasks]

    Rails.logger.info "🔍 Checking task update for tool: #{tool_name}, args: #{args.inspect}"
    Rails.logger.info "📋 Current tasks in list: #{task_list[:tasks].map { |t| "#{t['id'] || t[:id]}: #{t['description'] || t[:description]} (#{t['status'] || t[:status]})" }.join(', ')}"

    # Find matching task based on tool name and context
    task = nil

    case tool_name
    when "get_schema"
      # Match tasks like "Get campaign schema", "Get campaigns schema"
      object_type = args["object_type"]
      task = task_list[:tasks].find do |t|
        desc = (t["description"] || t[:description] || "").downcase
        status = t["status"] || t[:status]
        status == "pending" &&
        (desc.include?("get") || desc.include?("fetch") || desc.include?("retrieve")) &&
        desc.include?("schema") &&
        (desc.include?(object_type.downcase) || desc.include?(object_type.singularize.downcase) || desc.include?(object_type.pluralize.downcase))
      end

    when "create_object"
      # Match tasks like "Create new campaign 'name'"
      object_type = args["object_type"]
      object_name = args["name"] || args["title"] || ""
      task = task_list[:tasks].find do |t|
        desc = (t["description"] || t[:description] || "").downcase
        status = t["status"] || t[:status]
        status == "pending" &&
        desc.include?("create") &&
        (desc.include?(object_type.downcase) || desc.include?(object_type.singularize.downcase)) &&
        (object_name.empty? || desc.include?(object_name.downcase))
      end

    when "get_data"
      # Match tasks like "Find most recent email template", "Find the most recent template"
      object_type = args["object_type"]
      task = task_list[:tasks].find do |t|
        desc = (t["description"] || t[:description] || "").downcase
        status = t["status"] || t[:status]
        status == "pending" &&
        (desc.include?("find") || desc.include?("get") || desc.include?("fetch") || desc.include?("retrieve")) &&
        (desc.include?(object_type.downcase) || desc.include?(object_type.singularize.downcase) || desc.include?(object_type.pluralize.downcase)) &&
        (desc.include?("recent") || desc.include?("latest") || desc.include?("template"))
      end

    when "link_template_to_campaign"
      # Match tasks like "Link template to campaign", "Link the template to the new campaign"
      task = task_list[:tasks].find do |t|
        desc = (t["description"] || t[:description] || "").downcase
        status = t["status"] || t[:status]
        status == "pending" &&
        desc.include?("link") &&
        desc.include?("template") &&
        desc.include?("campaign")
      end

    when "generate_ai_landing_page"
      # Match tasks like "Generate AI-powered landing page", "Generate landing page", "Create landing page"
      task = task_list[:tasks].find do |t|
        desc = (t["description"] || t[:description] || "").downcase
        status = t["status"] || t[:status]
        status == "pending" &&
        (desc.include?("generate") || desc.include?("create")) &&
        desc.include?("landing page")
      end
    end

    if task
      task_desc = task["description"] || task[:description]
      task_id = task["id"] || task[:id]
      Rails.logger.info "✅ Found matching task: #{task_desc} (ID: #{task_id})"
    else
      Rails.logger.info "❌ No matching task found for tool: #{tool_name}"
      Rails.logger.info "   Available tasks: #{task_list[:tasks].map { |t| "#{t['description'] || t[:description]} (#{t['status'] || t[:status]})" }.join(', ')}"
      return
    end

    # Update task status
    if success
      result = execute_manage_task_list({
        "action" => "complete_task",
        "task_id" => task["id"] || task[:id],
        "details" => "Completed successfully"
      })

      # If we have updated canvas data and a callback, trigger canvas reload
      if result[:canvas] == "task_progress" && progress_callback
        updated_list = Rails.cache.read(cache_key)
        Rails.logger.info "📊 Canvas reload triggered - Updated list: #{updated_list.inspect}"
        if updated_list && updated_list[:tasks] && !updated_list[:tasks].empty?
          Rails.logger.info "✅ Sending canvas update with #{updated_list[:tasks].size} tasks"
          progress_callback.call({
            type: "load_canvas",
            canvas: "task_progress",
            canvas_data: updated_list
          })
        else
          Rails.logger.warn "⚠️ Skipping canvas update - task list is empty or nil"
        end
      end
    else
      result = execute_manage_task_list({
        "action" => "fail_task",
        "task_id" => task["id"] || task[:id],
        "details" => "Failed to complete"
      })

      # If we have updated canvas data and a callback, trigger canvas reload
      if result[:canvas] == "task_progress" && progress_callback
        updated_list = Rails.cache.read(cache_key)
        Rails.logger.info "📊 Canvas reload triggered - Updated list: #{updated_list.inspect}"
        if updated_list && updated_list[:tasks] && !updated_list[:tasks].empty?
          Rails.logger.info "✅ Sending canvas update with #{updated_list[:tasks].size} tasks"
          progress_callback.call({
            type: "load_canvas",
            canvas: "task_progress",
            canvas_data: updated_list
          })
        else
          Rails.logger.warn "⚠️ Skipping canvas update - task list is empty or nil"
        end
      end
    end
  end

  def execute_create_dynamic_visualization(args)
    begin
      title = args["title"]
      subtitle = args["subtitle"]
      html_content = args["html_content"]

      # Store the visualization data for the canvas
      @suggested_canvas = "dynamic_canvas"
      @canvas_data = {
        "title" => title,
        "subtitle" => subtitle,
        "html_content" => html_content
      }

      # If we're in streaming mode, proactively load the canvas immediately
      if @progress_callback
        @progress_callback.call({
          type: "load_canvas",
          canvas: "dynamic_canvas",
          canvas_data: @canvas_data
        })
      end

      {
        success: true,
        message: "📊 Created custom visualization: #{title}",
        canvas_type: "dynamic_canvas",
        canvas_data: @canvas_data
      }
    rescue => e
      Rails.logger.error "Error creating dynamic visualization: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def execute_manage_task_list(args)
    action = args["action"]
    entity_id = @entity&.id
    session_id = @session_id || SecureRandom.uuid

    Rails.logger.info "🔑 Task management - Entity: #{entity_id}, Session: #{session_id}, Action: #{action}"

    # Use TaskSession for persistent storage
    task_session = TaskSession.active
                             .where(user: @user)
                             .where("metadata->>'session_id' = ?", session_id)
                             .first_or_create!(
                               user: @user,
                               status: "active",
                               metadata: {
                                 session_id: session_id,
                                 entity_id: entity_id,
                                 created_from: "scout_task_management"
                               }
                             )

    # Use Rails cache as a fast access layer, but persist to TaskSession
    cache_key = "scout_task_list_#{entity_id}_#{session_id}"

    case action
    when "create"
      # Create a new task list - handle both 'description' and 'title' fields
      tasks = (args["tasks"] || []).map do |task|
        {
          id: task["id"],
          description: task["description"] || task["title"] || "",
          status: task["status"] || "pending",
          details: task["details"]
        }
      end

      task_list = {
        title: args["title"],
        tasks: tasks,
        created_at: Time.current,
        updated_at: Time.current
      }
      persist_task_list(task_session, cache_key, task_list)

      Rails.logger.info "📝 Created task list with #{tasks.size} tasks"
      Rails.logger.info "📝 Tasks: #{tasks.map { |t| "#{t[:id]}: #{t[:description]}" }.join(', ')}"

      # Store for canvas display
      @suggested_canvas = "task_progress"
      @canvas_data = task_list

      # Canvas will be loaded via the return value
      # The streaming handler will pick up the canvas from the result

      # Immediately load the canvas if we have a callback
      if @progress_callback
        @progress_callback.call({
          type: "load_canvas",
          canvas: "task_progress",
          canvas_data: task_list
        })
      end

      {
        success: true,
        message: "📋 Created task list: #{args['title']}",
        task_list: task_list,
        canvas: "task_progress"
      }

    when "update"
      # Handle both task update and list update based on parameters
      if args["task_id"].present?
        # This is a task update, redirect to task update logic
        Rails.logger.info "🔄 Redirecting 'update' with task_id to task update logic"
        # Recursively call with the correct action
        execute_manage_task_list(args.merge("action" => "update_task"))
      else
        # Update entire task list
        existing_list = Rails.cache.read(cache_key)
        if existing_list
          # Only update tasks if provided, otherwise keep existing tasks
          if args["tasks"].present?
            existing_list[:tasks] = args["tasks"]
          end
          existing_list[:updated_at] = Time.current
          persist_task_list(task_session, cache_key, existing_list)

          @suggested_canvas = "task_progress"
          @canvas_data = existing_list

          {
            success: true,
            message: "📝 Task list updated",
            task_list: existing_list,
            canvas: "task_progress"
          }
        else
          {
            success: false,
            error: "No task list found to update"
          }
        end
      end

    when "add_task"
      # Add a single task
      existing_list = Rails.cache.read(cache_key)
      if existing_list
        new_task = {
          id: args["task_id"] || SecureRandom.hex(4),
          description: args["task_description"] || args["description"] || args["title"],
          status: "pending",
          details: nil
        }
        existing_list[:tasks] << new_task
        existing_list[:updated_at] = Time.current
        persist_task_list(task_session, cache_key, existing_list)

        @suggested_canvas = "task_progress"
        @canvas_data = existing_list

        {
          success: true,
          message: "➕ Task added: #{args['task_description']}",
          task_list: existing_list,
          canvas: "task_progress"
        }
      else
        {
          success: false,
          error: "No task list found"
        }
      end

    when "update_task", "update_status"
      # Update a task status (e.g., to in_progress) - handle both action names
      existing_list = Rails.cache.read(cache_key) || task_session.state&.dig("task_list")
      if existing_list
        task = existing_list[:tasks].find { |t| (t["id"] || t[:id]).to_s == args["task_id"].to_s }
        if task
          # Update status
          new_status = args["status"] || "in_progress"
          task[:status] = new_status
          task["status"] = new_status  # Ensure both symbol and string keys work
          task[:details] = args["details"] if args["details"]
          task["details"] = args["details"] if args["details"]

          # Add timestamp based on status
          case new_status
          when "in_progress"
            task[:started_at] = Time.current
            task["started_at"] = Time.current
          when "completed"
            task[:completed_at] = Time.current
            task["completed_at"] = Time.current
          when "failed"
            task[:failed_at] = Time.current
            task["failed_at"] = Time.current
          end

          existing_list[:updated_at] = Time.current
          Rails.cache.write(cache_key, existing_list, expires_in: 24.hours)

          @suggested_canvas = "task_progress"
          @canvas_data = existing_list

          # Send canvas update immediately if we have a callback
          if @progress_callback
            @progress_callback.call({
              type: "load_canvas",
              canvas: "task_progress",
              canvas_data: existing_list
            })
          end

          {
            success: true,
            message: "📝 Task updated: #{task['description'] || task[:description]} → #{new_status}",
            task_list: existing_list,
            canvas: "task_progress"
          }
        else
          {
            success: false,
            error: "Task not found: #{args['task_id']}"
          }
        end
      else
        {
          success: false,
          error: "No task list found"
        }
      end

    when "complete_task"
      # Mark a task as completed
      existing_list = Rails.cache.read(cache_key)
      if existing_list
        task = existing_list[:tasks].find { |t| (t["id"] || t[:id]).to_s == args["task_id"].to_s }
        if task
          task[:status] = "completed"
          task["status"] = "completed"  # Ensure both symbol and string keys work
          task[:details] = args["details"] if args["details"]
          task["details"] = args["details"] if args["details"]
          task[:completed_at] = Time.current
          task["completed_at"] = Time.current
          existing_list[:updated_at] = Time.current
          Rails.cache.write(cache_key, existing_list, expires_in: 24.hours)

          @suggested_canvas = "task_progress"
          @canvas_data = existing_list

          # Calculate progress
          total_tasks = existing_list[:tasks].size
          completed_tasks = existing_list[:tasks].count { |t| (t["status"] || t[:status]) == "completed" }
          progress_percentage = (completed_tasks.to_f / total_tasks * 100).round

            # Stream canvas update immediately so the UI shows progress between steps
            if @progress_callback
              @progress_callback.call({
                type: "load_canvas",
                canvas: "task_progress",
                canvas_data: existing_list
              })
            end

          {
            success: true,
            message: "✅ Task completed: #{task['description'] || task[:description]}",
            progress: "#{completed_tasks}/#{total_tasks} tasks completed (#{progress_percentage}%)",
            task_list: existing_list,
            canvas: "task_progress"
          }
        else
          {
            success: false,
            error: "Task not found: #{args['task_id']}"
          }
        end
      else
        {
          success: false,
          error: "No task list found"
        }
      end

    when "fail_task"
      # Mark a task as failed
      existing_list = Rails.cache.read(cache_key)
      if existing_list
        task = existing_list[:tasks].find { |t| (t["id"] || t[:id]).to_s == args["task_id"].to_s }
        if task
          task[:status] = "failed"
          task["status"] = "failed"  # Ensure both symbol and string keys work
          task[:details] = args["details"] || "Task failed"
          task["details"] = args["details"] || "Task failed"
          task[:failed_at] = Time.current
          task["failed_at"] = Time.current
          existing_list[:updated_at] = Time.current
          Rails.cache.write(cache_key, existing_list, expires_in: 24.hours)

          @suggested_canvas = "task_progress"
          @canvas_data = existing_list

            # Stream canvas update so the failure status appears immediately
            if @progress_callback
              @progress_callback.call({
                type: "load_canvas",
                canvas: "task_progress",
                canvas_data: existing_list
              })
            end

          {
            success: true,
            message: "❌ Task failed: #{task['description'] || task[:description]}",
            reason: args["details"],
            task_list: existing_list,
            canvas: "task_progress"
          }
        else
          {
            success: false,
            error: "Task not found: #{args['task_id']}"
          }
        end
      else
        {
          success: false,
          error: "No task list found"
        }
      end

    else
      {
        success: false,
        error: "Unknown action: #{action}"
      }
    end
  end

  # Integration tool implementations
  def execute_list_connections(args)
    connections = @entity.connections.includes(:integration, :integration_credentials)

    # Filter by category if provided
    if args["category"].present?
      connections = connections.joins(:integration)
                               .where(integrations: { category: args["category"] })
    end

    connections_data = connections.map do |conn|
      {
        id: conn.id,
        name: conn.name,
        integration: {
          name: conn.integration.name,
          slug: conn.integration.slug,
          category: conn.integration.category,
          icon_url: conn.integration.icon_url,
          description: conn.integration.description
        },
        status: conn.status,
        has_active_credentials: conn.integration_credentials.active.any?,
        last_used: conn.integration_logs.maximum(:created_at),
        daily_budget_remaining: conn.daily_write_budget ?
          (conn.daily_write_budget - conn.integration_logs.today.writes.count) :
          "unlimited",
        operations_count: conn.available_operations.count
      }
    end

    # Get all available integrations
    available_integrations = Integration.active.map do |integration|
      # Check if user already has a connection for this integration
      connected = connections.any? { |c| c.integration_id == integration.id }

      {
        id: integration.id,
        name: integration.name,
        slug: integration.slug,
        category: integration.category,
        description: integration.description,
        icon_url: integration.icon_url,
        auth_type: integration.auth_type,
        is_connected: connected,
        is_verified: integration.is_verified,
        operations_count: integration.integration_operations.count
      }
    end

    {
      success: true,
      connections: connections_data,
      available_integrations: available_integrations,
      total_connections: connections_data.length,
      total_available: available_integrations.length,
      categories: Integration.distinct.pluck(:category),
      canvas: "integrations_manager",
      canvas_data: {
        connections: connections_data,
        integrations: available_integrations
      }
    }
  end

  def execute_test_connection(args)
    connection = @entity.connections.find_by(id: args["connection_id"])

    return { success: false, error: "Connection not found" } unless connection

    # Test the connection
    test_result = connection.test_connection!

    if test_result[:success]
      {
        success: true,
        message: "✅ #{connection.integration.name} connection test successful!",
        connection: {
          id: connection.id,
          name: connection.name,
          integration: connection.integration.name,
          status: connection.status
        },
        test_details: test_result
      }
    else
      # Provide diagnostic information to help fix the issue
      {
        success: false,
        message: "❌ #{connection.integration.name} test failed: #{test_result[:error]}",
        error: test_result[:error],
        connection: {
          id: connection.id,
          name: connection.name,
          integration: connection.integration.name,
          status: connection.status
        },
        integration_config: {
          auth_type: connection.integration.auth_type,
          auth_config: connection.integration.auth_config,
          api_base_url: connection.integration.api_base_url
        },
        current_credentials: connection.active_credential ? {
          auth_method: connection.active_credential.auth_method,
          has_credentials: connection.active_credential.credentials.present?
        } : nil,
        suggested_fixes: generate_auth_fix_suggestions(connection, test_result),
        test_details: test_result
      }
    end
  end

  def generate_auth_fix_suggestions(connection, test_result)
    suggestions = []
    integration = connection.integration
    error_msg = test_result[:error]&.downcase || ""

    # Analyze common error patterns and suggest fixes
    if error_msg.include?("invalid api key") || error_msg.include?("unauthorized")
      case integration.slug
      when "stripe"
        if integration.auth_type == "bearer_token"
          suggestions << "Change auth_type from 'bearer_token' to 'basic_auth' - Stripe uses Basic Auth with API key as username"
        end
        if connection.active_credential&.auth_method == "bearer"
          suggestions << "Update credential auth_method from 'bearer' to 'basic'"
        end
      end

      suggestions << "Verify the API key is correct and has proper permissions"
      suggestions << "Check if the API key is for the correct environment (test vs live)"
    end

    if error_msg.include?("forbidden") || error_msg.include?("access denied")
      suggestions << "API key may lack required permissions/scopes"
      suggestions << "Check if the integration requires specific API permissions to be enabled"
    end

    suggestions
  end

  def execute_describe_connection(args)
    connection = @entity.connections.find_by(id: args["connection_id"])

    return { success: false, error: "Connection not found" } unless connection

    operations = connection.available_operations.map do |op|
      {
        operation_id: op.operation_id,
        name: op.name,
        description: op.description,
        method: op.http_method,
        path: op.path_template,
        requires_confirmation: op.requires_confirmation,
        is_safe: op.safe?,
        example: op.format_example_request
      }
    end

    {
      success: true,
      connection: {
        id: connection.id,
        name: connection.name,
        integration: connection.integration.name,
        status: connection.status,
        settings: connection.settings,
        rate_limit_tier: connection.rate_limit_tier,
        rate_limit_remaining: connection.within_rate_limit? ? "available" : "exceeded",
        daily_budget_remaining: connection.within_daily_budget? ?
          (connection.daily_write_budget || "unlimited") : "exceeded"
      },
      operations: operations,
      recent_logs: connection.integration_logs.recent.limit(5).map do |log|
        {
          operation: log.operation_id,
          status: log.response_status,
          success: log.successful?,
          duration_ms: log.duration_ms,
          created_at: log.created_at
        }
      end
    }
  end

  def execute_invoke_operation(args)
    # Normalize common alias keys from LLM/tooling
    op_id = args["operation_id"] || args["operation"]
    params_hash = args["params"] || args["parameters"] || {}
    body_hash = args["body"] || args["data"]

    connection = @entity.connections.find_by(id: args["connection_id"])
    return { success: false, error: "Connection not found" } unless connection

    operation = connection.integration.integration_operations
                         .find_by(operation_id: op_id)
    return { success: false, error: "Operation not found" } unless operation

    # Policy check
    unless connection.can_execute?(operation.operation_id, "scout")
      return { success: false, error: "Operation not allowed by policy" }
    end

    # Rate limit check
    unless connection.within_rate_limit?
      return {
        success: false,
        error: "Rate limit exceeded",
        retry_after: connection.integration_logs.recent.first&.created_at&.+(1.hour)
      }
    end

    # Build and execute request
    begin
      api_service = IntegrationApiService.new(connection)
      response = api_service.execute_operation(
        operation,
        params: params_hash,
        body: body_hash
      )

      # HTTParty::Response exposes .parsed_response and .code
      headers_hash = (response.headers || {}).to_h
      result = {
        success: response.respond_to?(:success?) ? response.success? : (200..299).cover?(response.code.to_i),
        data: response.parsed_response,
        status: response.code,
        headers: headers_hash.slice("x-ratelimit-remaining", "x-ratelimit-reset"),
        next_cursor: headers_hash["x-next-cursor"]
      }

      # Stream a brief summary to chat and load a dynamic canvas for visualization for GET/list responses
      if result[:success]
        # Best-effort infer records for list endpoints
        body = response.parsed_response
        records = if body.is_a?(Hash) && body["data"].is_a?(Array)
                    body["data"]
        elsif body.is_a?(Array)
                    body
        else
                    []
        end

        # Persist as an Artifact for downstream analysis/visualization
        begin
          if records.any?
            schema = Artifact.infer_schema(records)
            artifact = Artifact.create!(
              entity: @entity,
              user: @user,
              name: "#{connection.integration.name} • #{operation.name}",
              source: "integration",
              connection_id: connection.id,
              operation_id: operation.operation_id,
              schema: schema,
              sample: records.first(25),
              row_count: (body["total_count"] || records.length),
              metadata: { headers: headers_hash.slice("x-ratelimit-remaining", "x-ratelimit-reset") }
            )
            result[:artifact_id] = artifact.id
          end
        rescue => e
          Rails.logger.warn("Artifact persistence failed: #{e.message}")
        end

        if @progress_callback
          count = records.length
          sample = records.first(3)
          @progress_callback.call({ type: "intermediate_message", content: "✅ Retrieved #{count} record#{count == 1 ? '' : 's'} from #{connection.integration.name}. Rendering a quick view...", role: "assistant" })

          # Build a simple HTML table for the dynamic canvas as a default visualization
          table_headers = []
          if sample.first.is_a?(Hash)
            keys = sample.first.keys
            denylist = %w[object metadata livemode sources subscriptions discount tax_ids invoice_settings shipping address preferred_locales]
            scorer = lambda do |k|
              next -100 if denylist.include?(k.to_s)
              key = k.to_s
              score = 0
              score += 120 if key == "id" || key.end_with?("_id")
              score += 110 if key == "email"
              score += 100 if key == "name" || key == "description"
              score += 90  if key == "created" || key.end_with?("_at")
              score += 80  if key.include?("status")
              score += 70  if key.include?("amount") || key.include?("balance") || key.include?("total")
              score += 60  if key == "currency"
              score += 40  if key.include?("plan") || key.include?("subscription")
              # Prefer short scalar-like keys
              score += 10 if key.length <= 16
              score
            end
            table_headers = keys.sort_by { |k| -scorer.call(k) }.first(8)
          end
          rows_html = records.first(25).map do |row|
            if row.is_a?(Hash)
              "<tr>" + table_headers.map { |k| "<td>#{ERB::Util.html_escape(row[k].to_s)[0, 120]}</td>" }.join + "</tr>"
            else
              "<tr><td>#{ERB::Util.html_escape(row.to_s)[0, 120]}</td></tr>"
            end
          end.join
          header_html = table_headers.any? ? ("<thead><tr>" + table_headers.map { |k| "<th>#{ERB::Util.html_escape(k)}</th>" }.join + "</tr></thead>") : ""
          html = "<div class=\"table-responsive\"><table class=\"table table-dark table-striped table-sm\">#{header_html}<tbody>#{rows_html}</tbody></table></div>"

          safe_load_canvas("dynamic_canvas", {
            "title" => "#{connection.integration.name} • #{operation.name}",
            "subtitle" => operation.operation_id,
            "html_content" => html,
            "artifact_id" => result[:artifact_id],
            "row_count" => result[:row_count] || records.length
          })
        end
      end

      result
    rescue => e
      {
        success: false,
        error: e.message,
        error_class: e.class.name
      }
    end
  end

  def execute_dry_run_operation(args)
    # Normalize keys similar to invoke
    op_id = args["operation_id"] || args["operation"]
    params_hash = args["params"] || args["parameters"] || {}
    body_hash = args["body"] || args["data"]

    connection = @entity.connections.find_by(id: args["connection_id"])
    return { success: false, error: "Connection not found" } unless connection

    operation = connection.integration.integration_operations
                         .find_by(operation_id: op_id)
    return { success: false, error: "Operation not found" } unless operation

    # Validate request
    validation_errors = operation.validate_request(params_hash, body_hash)
    if validation_errors.any?
      return {
        success: false,
        error: "Validation failed",
        validation_errors: validation_errors
      }
    end

    # Build preview
    api_service = IntegrationApiService.new(connection)
    preview = api_service.build_request_preview(
      operation,
      params: params_hash,
      body: body_hash
    )

    # Generate confirmation token
    confirmation_data = {
      connection_id: connection.id,
      operation_id: operation.operation_id,
      params: params_hash,
      body: body_hash,
      expires_at: 5.minutes.from_now
    }

    confirmation_token = Rails.application.message_verifier("dry_run").generate(confirmation_data)

    {
      success: true,
      dry_run: true,
      confirmation_token: confirmation_token,
      preview: {
        method: preview[:method],
        url: preview[:url],
        headers: preview[:headers].except("Authorization", "X-Api-Key"),
        body: preview[:body]
      },
      requires_confirmation: operation.requires_confirmation,
      estimated_impact: {
        is_write: operation.write_operation?,
        is_idempotent: operation.is_idempotent,
        affects_resources: operation.name.include?("create") || operation.name.include?("update")
      }
    }
  end

  def execute_confirm_operation(args)
    begin
      confirmation_data = Rails.application.message_verifier("dry_run").verify(args["token"])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      return { success: false, error: "Invalid or expired confirmation token" }
    end

    # Check expiration
    if confirmation_data[:expires_at] < Time.current
      return { success: false, error: "Confirmation token has expired" }
    end

    # Execute the operation
    execute_invoke_operation(confirmation_data)
  end

  def execute_discover_api_schema(args)
    integration = Integration.find_by(slug: args["integration"])
    return { success: false, error: "Integration not found" } unless integration

    # Check if user has a connection to this integration
    connection = @entity.connections.find_by(integration: integration)

    {
      success: true,
      integration: {
        name: integration.name,
        slug: integration.slug,
        category: integration.category,
        auth_type: integration.auth_type,
        documentation_url: integration.documentation_url,
        connected: connection.present?
      },
      operations: integration.integration_operations.active.map do |op|
        {
          operation_id: op.operation_id,
          name: op.name,
          description: op.description,
          method: op.http_method,
          path: op.path_template,
          request_schema: op.request_schema,
          pagination: op.pagination_strategy
        }
      end,
      connection_required: connection.nil?,
      setup_instructions: integration.auth_config["setup_instructions"]
    }
  end

  def execute_configure_integration(args)
    connection = @entity.connections.find_by(id: args["connection_id"])

    return { success: false, error: "Connection not found" } unless connection

    integration = connection.integration

    # Check permissions
    if integration.is_verified
      # Global integration - require admin
      return { success: false, error: "Admin access required to modify verified integrations" } unless @user.admin?
    else
      # Custom integration - must be owned by user
      return { success: false, error: "You can only modify your own custom integrations" } unless connection.entity == @entity
    end

    updated_fields = []

    # Update integration settings
    if args["updates"].present?
      updates = args["updates"]

      if updates["api_base_url"].present?
        integration.api_base_url = updates["api_base_url"]
        updated_fields << "API base URL"
      end

      if updates["auth_config"].present?
        integration.auth_config.merge!(updates["auth_config"])
        updated_fields << "Authentication configuration"
      end

      if updates["allowed_hosts"].present?
        integration.allowed_hosts = updates["allowed_hosts"]
        updated_fields << "Allowed hosts"
      end

      if updates["rate_limits"].present?
        integration.metadata ||= {}
        integration.metadata["rate_limits"] = updates["rate_limits"]
        updated_fields << "Rate limits"
      end

      if updates["custom_headers"].present?
        integration.metadata ||= {}
        integration.metadata["custom_headers"] = updates["custom_headers"]
        updated_fields << "Custom headers"
      end

      integration.save!
    end

    # Update operations
    if args["operation_updates"].present?
      args["operation_updates"].each do |op_update|
        operation = integration.integration_operations.find_by(operation_id: op_update["operation_id"])

        if operation
          operation.path_template = op_update["path_template"] if op_update["path_template"].present?
          operation.request_schema = op_update["request_schema"] if op_update["request_schema"].present?
          operation.pagination_strategy = op_update["pagination_strategy"] if op_update["pagination_strategy"].present?
          operation.save!
          updated_fields << "Operation: #{operation.name}"
        end
      end
    end

    # Test the connection with new settings
    test_result = connection.test_connection!

    {
      success: true,
      message: "Integration configuration updated",
      updated_fields: updated_fields,
      connection_test: test_result,
      integration: {
        id: integration.id,
        name: integration.name,
        api_base_url: integration.api_base_url,
        auth_type: integration.auth_type
      }
    }
  rescue => e
    { success: false, error: "Failed to update configuration: #{e.message}" }
  end

  public # Make aggregation methods public

  def execute_aggregate_artifact_data(args)
    # Normalize args to handle both string and symbol keys
    args = args.with_indifferent_access if args.respond_to?(:with_indifferent_access)

    artifact_id = args["artifact_id"]
    Rails.logger.info "execute_aggregate_artifact_data called with artifact_id: #{artifact_id} (class: #{artifact_id.class})"
    Rails.logger.info "@entity: #{@entity&.id}, @user: #{@user&.id}"

    # Find artifact - try with entity first, then without
    artifact = if @entity
      Artifact.find_by(id: artifact_id, entity: @entity)
    else
      Artifact.find_by(id: artifact_id)
    end

    Rails.logger.info "Found artifact: #{artifact&.id}"
    return { success: false, error: "Artifact not found or access denied" } unless artifact

    operation = args["operation"]

    # For now, work with the sample data stored in the artifact
    # In a production system, this would query the actual stored data
    data = artifact.sample || []

    begin
      case operation
      when "group_by_field"
          field = args["field"]
          return { success: false, error: "Field required for group_by_field" } unless field

        # Group data by field and apply aggregations
        grouped = data.group_by { |row| row[field] }
        results = grouped.map do |key, rows|
          result = { field => key }

          if args["aggregations"].present?
            args["aggregations"].each do |agg|
              func = agg["function"]
              agg_field = agg["field"] || field
              alias_name = agg["alias"] || "#{func}_#{agg_field}"

              case func
              when "count"
                result[alias_name] = rows.length
              when "sum"
                result[alias_name] = rows.sum { |r| r[agg_field].to_f }
              when "avg"
                sum = rows.sum { |r| r[agg_field].to_f }
                result[alias_name] = rows.empty? ? 0 : (sum / rows.length).round(2)
              when "min"
                result[alias_name] = rows.map { |r| r[agg_field] }.compact.min
              when "max"
                result[alias_name] = rows.map { |r| r[agg_field] }.compact.max
              when "distinct"
                result[alias_name] = rows.map { |r| r[agg_field] }.uniq.length
              end
            end
          else
            result["count"] = rows.length
          end

          result
        end

        # Sort results if requested
        if args["order_by"]
          results.sort_by! { |r| r[args["order_by"]] || 0 }
          results.reverse! if args["order_direction"] == "desc"
        end

      when "group_by_time"
        time_field = args["time_field"]
        time_bucket = args["time_bucket"] || "day"
        return { success: false, error: "Time field required for group_by_time" } unless time_field

        # Group by time buckets
        grouped = data.group_by do |row|
          begin
            time = Time.parse(row[time_field].to_s)
            case time_bucket
            when "hour"
              time.strftime("%Y-%m-%d %H:00")
            when "day"
              time.strftime("%Y-%m-%d")
            when "week"
              time.beginning_of_week.strftime("%Y-%m-%d")
            when "month"
              time.strftime("%Y-%m")
            when "quarter"
              "#{time.year} Q#{(time.month - 1) / 3 + 1}"
            when "year"
              time.year.to_s
            else
              time.strftime("%Y-%m-%d")
            end
          rescue
            "invalid_date"
          end
        end

        results = grouped.map do |bucket, rows|
          {
            time_bucket => bucket,
            "count" => rows.length,
            "records" => rows.length
          }
        end.sort_by { |r| r[time_bucket] }

      when "top_k"
        field = args["field"]
        k = args["k"] || 10
        return { success: false, error: "Field required for top_k" } unless field

        # Count occurrences and get top k
        counts = data.group_by { |row| row[field] }
                     .map { |value, rows| { field => value, "count" => rows.length } }
                     .sort_by { |r| -r["count"] }
                     .first(k)

        results = counts

      when "simple_stats"
        # Calculate basic statistics across numeric fields
        numeric_fields = artifact.schema.select { |k, v| %w[integer float number].include?(v) }.keys

        results = numeric_fields.map do |field|
          values = data.map { |r| r[field].to_f }.compact
          next if values.empty?

          {
            "field" => field,
            "count" => values.length,
            "sum" => values.sum.round(2),
            "avg" => (values.sum / values.length).round(2),
            "min" => values.min,
            "max" => values.max
          }
        end.compact

      else
        return { success: false, error: "Unknown operation: #{operation}" }
      end

      # Stream results to dynamic canvas if we have a progress callback
      if @progress_callback && results.any?
        @progress_callback.call({
          type: "intermediate_message",
          content: "✅ Completed #{operation} aggregation on #{data.length} records",
          role: "assistant"
        })

        # Generate appropriate visualization
        viz_html = generate_aggregation_html(operation, results, args)

        safe_load_canvas("dynamic_canvas", {
          "title" => "#{artifact.name} • #{operation.humanize}",
          "subtitle" => "Aggregation of #{data.length} records",
          "html_content" => viz_html,
          "artifact_id" => artifact.id,
          "aggregation_type" => operation
        })
      end

      # Return success result
      {
        success: true,
        data: {
          results: results,
          row_count: results.length,
          aggregation_type: operation,
          artifact_id: artifact.id,
          source_row_count: data.length
        }
      }

    rescue => e
      { success: false, error: "Aggregation failed: #{e.message}" }
    end
  end

  public

  def execute_fetch_next_page(args)
    artifact = Artifact.find_by(id: args["artifact_id"], entity: @entity)
    return { success: false, error: "Artifact not found or access denied" } unless artifact

    # Check if this artifact supports pagination
    connection = Connection.find_by(id: artifact.connection_id)
    return { success: false, error: "No connection associated with this artifact" } unless connection

    operation = IntegrationOperation.find_by(
      integration_id: connection.integration_id,
      operation_id: artifact.operation_id
    )
    return { success: false, error: "Operation not found" } unless operation

    # Get pagination info from artifact metadata
    cursor = args["cursor"] || artifact.metadata["next_cursor"]
    limit = [ args["limit"] || 25, 100 ].min

    return { success: false, error: "No more pages available" } unless cursor

    # Execute the operation with pagination parameters
    api_service = IntegrationApiService.new(connection)

    begin
      # Add cursor to the original parameters
      params = artifact.metadata["original_params"] || {}
      params["cursor"] = cursor
      params["limit"] = limit

      response = api_service.execute_operation(operation, params: params)

      if response.code.between?(200, 299)
        body = response.parsed_response
        records = if body.is_a?(Hash) && body["data"].is_a?(Array)
                    body["data"]
        elsif body.is_a?(Array)
                    body
        else
                    []
        end

        # Create a new artifact for this page
        new_artifact = Artifact.create!(
          entity: @entity,
          user: @user,
          name: "#{artifact.name} (Page)",
          source: "integration",
          connection_id: connection.id,
          operation_id: operation.operation_id,
          schema: artifact.schema,
          sample: records.first(25),
          row_count: records.length,
          metadata: {
            parent_artifact_id: artifact.id,
            next_cursor: response.headers["x-next-cursor"] || body["next_cursor"],
            has_more: body["has_more"] || false,
            original_params: params
          }
        )

        {
          success: true,
          data: {
            artifact_id: new_artifact.id,
            rows: records,
            row_count: records.length,
            next_cursor: new_artifact.metadata["next_cursor"],
            has_more: new_artifact.metadata["has_more"]
          }
        }
      else
        { success: false, error: "API request failed: #{response.code}" }
      end

    rescue => e
      { success: false, error: "Failed to fetch next page: #{e.message}" }
    end
  end

  public

  def execute_tool_by_name(tool_name, args, progress_callback = nil)
    # Map tool name to execution method
    case tool_name
    when "get_data"
      execute_get_data(args)
    when "create_object"
      execute_create_object(args)
    when "get_schema"
      execute_get_schema(args)
    when "generate_ai_landing_page"
      execute_generate_ai_landing_page(args)
    when "web_search"
      execute_web_search(args)
    when "create_rag_store"
      execute_create_rag_store(args)
    when "generate_integration_config"
      execute_generate_integration_config(args)
    when "test_integration_endpoint"
      execute_test_integration_endpoint(args)
    when "build_integration_endpoints"
      execute_build_integration_endpoints(args)
    when "update_landing_page_status"
      execute_update_landing_page_status(args)
    when "update_landing_page_content"
      execute_update_landing_page_content(args)
    when "revert_landing_page_to_version"
      execute_revert_landing_page_to_version(args)
    when "link_template_to_campaign"
      execute_link_template_to_campaign(args)
    when "create_dynamic_visualization"
      execute_create_dynamic_visualization(args)
    when "manage_task_list"
      execute_manage_task_list(args)
    when "analyze_landing_page_request"
      execute_analyze_landing_page_request_internal(args)
    when "process_landing_page_images"
      execute_process_landing_page_images(args)
    when "store_uploaded_images"
      execute_store_uploaded_images(args)
    when "list_connections"
      execute_list_connections(args)
    when "describe_connection"
      execute_describe_connection(args)
    when "invoke_operation"
      execute_invoke_operation(args)
    when "dry_run_operation"
      execute_dry_run_operation(args)
    when "confirm_operation"
      execute_confirm_operation(args)
    when "discover_api_schema"
      execute_discover_api_schema(args)
    when "configure_integration"
      execute_configure_integration(args)
    when "test_connection"
      execute_test_connection(args)
    when "aggregate_artifact_data"
      execute_aggregate_artifact_data(args)
    when "fetch_next_page"
      execute_fetch_next_page(args)
    else
      { success: false, error: "Unknown tool: #{tool_name}" }
    end
  end

  private

  def canvas_allowed?(canvas_name)
    # Check if canvas is allowed by agent loadout
    return true unless @agent_loadout # No restrictions if no loadout
    @agent_loadout.canvas_allowed?(canvas_name)
  end

  def safe_load_canvas(canvas_name, canvas_data = {})
    # Load canvas only if allowed
    if canvas_allowed?(canvas_name)
      @suggested_canvas = canvas_name
      @canvas_data = canvas_data

      # Stream canvas load if we have a callback
      if @progress_callback
        @progress_callback.call({
          type: "load_canvas",
          canvas: canvas_name,
          canvas_data: canvas_data
        })
      end

      true
    else
      Rails.logger.warn "Canvas '#{canvas_name}' not allowed for agent role '#{@agent_loadout.agent_role}'"
      false
    end
  end

  def generate_aggregation_html(operation, results, args)
    case operation
    when "group_by_field", "top_k"
      # Generate a table for grouped data
      return "<p>No results to display</p>" if results.empty?

      headers = results.first.keys
      rows_html = results.map do |row|
        "<tr>" + headers.map { |h| "<td>#{ERB::Util.html_escape(row[h].to_s)}</td>" }.join + "</tr>"
      end.join

      "<div class=\"table-responsive\">
        <table class=\"table table-dark table-striped table-sm\">
          <thead>
            <tr>#{headers.map { |h| "<th>#{ERB::Util.html_escape(h)}</th>" }.join}</tr>
          </thead>
          <tbody>#{rows_html}</tbody>
        </table>
      </div>"

    when "group_by_time"
      # Generate a time series visualization (table for now, could be a chart)
      return "<p>No time series data</p>" if results.empty?

      rows_html = results.map do |row|
        "<tr><td>#{ERB::Util.html_escape(row[args['time_bucket'] || 'time_bucket'])}</td><td>#{row['count']}</td></tr>"
      end.join

      "<div class=\"table-responsive\">
        <table class=\"table table-dark table-striped table-sm\">
          <thead>
            <tr><th>Time Period</th><th>Count</th></tr>
          </thead>
          <tbody>#{rows_html}</tbody>
        </table>
      </div>"

    when "simple_stats"
      # Generate a stats summary table
      return "<p>No numeric fields to analyze</p>" if results.empty?

      rows_html = results.map do |stat|
        "<tr>
          <td>#{ERB::Util.html_escape(stat['field'])}</td>
          <td>#{stat['count']}</td>
          <td>#{stat['sum']}</td>
          <td>#{stat['avg']}</td>
          <td>#{stat['min']}</td>
          <td>#{stat['max']}</td>
        </tr>"
      end.join

      "<div class=\"table-responsive\">
        <table class=\"table table-dark table-striped table-sm\">
          <thead>
            <tr><th>Field</th><th>Count</th><th>Sum</th><th>Average</th><th>Min</th><th>Max</th></tr>
          </thead>
          <tbody>#{rows_html}</tbody>
        </table>
      </div>"

    else
      "<p>Visualization not available for #{operation}</p>"
    end
  end
end
