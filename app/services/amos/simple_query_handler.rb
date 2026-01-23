# Handles simple queries that Amos can answer directly
# 
# IMPORTANT: In unified mode, this ALWAYS uses ScoutToolsService → ScoutGenericToolsServiceV2
# The LLM prompts in generate_simple_response methods below are COMMENTED OUT and NOT USED
# The actual prompt being used is in app/services/scout_generic_tools_service_v2.rb
module Amos
  class SimpleQueryHandler
    # Minimal tools for Amos
    ALLOWED_TOOLS = [
      :conversation_summary,
      :entity_info,
      :job_status,
      :web_search,
      :rag_query
    ].freeze
    
    attr_accessor :intent_mode
    
    def initialize(context)
      @context = context
      @intent_mode = nil # Set by orchestrator: :personal, :ideate, :operate, :create
    end
    
    def process(query)
      # ALWAYS use Scout with tools - single unified mode
      process_with_tools(query)
    end
    
    def can_stream?
      # We can stream LLM responses
      true
    end
    
    def process_streaming(query, &block)
      # ALWAYS use Scout with tools - single unified mode
      process_with_tools_streaming(query, &block)
    end
    
    private
    
    def needs_tools?(query)
      # Simple rules for when we need tools
      # No extra LLM call needed
      
      normalized = query.downcase
      
      # Always use tools if files are attached
      if normalized.include?("[attached files:") || normalized.include?("asset_id:")
        Rails.logger.info "[Scout] Attached files detected - using tools"
        return true
      end
      
      # Patterns that indicate tool usage needed
      tool_patterns = [
        # Canvas/viewing patterns (prioritized)
        /show\s+me|display|view|load|open/,
        /list\s+(my|all|the)/,
        /what\s+(campaigns|contacts|landing\s+pages|emails|integrations)/,
        
        # Data retrieval
        /count|how\s+many/,
        /get|fetch|retrieve|pull/,
        /last\s+\d+|recent|latest/,
        
        # Canvas specific
        /canvas|editor|builder/,
        
        # Integration/connection queries
        /stripe|payment|webhook|integration.*status/,
        /connected|connections/,
        
        # Document queries
        /document|file|upload/
      ]
      
      # Check if query matches any tool pattern
      needs_tools = tool_patterns.any? { |pattern| normalized.match?(pattern) }
      
      Rails.logger.info "[Scout] Query analysis:"
      Rails.logger.info "  Query: #{query}"
      Rails.logger.info "  Needs tools: #{needs_tools}"
      
      needs_tools
    end
    
    def extract_attached_files(query)
      # Simple extraction for attached file info
      # This is just to pass context to the analyzer
      files = []
      
      if query.include?("[Attached Files:") || query.include?("asset_id:")
        query.scan(/📎\s*([^(]+)\s*\(asset_id:\s*(\d+)(?:,\s*type:\s*([^)]+))?\)/i).each do |match|
          files << {
            filename: match[0].strip,
            asset_id: match[1],
            content_type: match[2]&.strip
          }
        end
      end
      
      files
    end
    
    def process_with_tools(query)
      # Initialize Scout tools service with limited toolset
      scout_tools = Amos::ScoutToolsService.new(@context)
      scout_tools.intent_mode = @intent_mode  # Pass intent mode for role adaptation
      
      # Process the query with tools
      response = scout_tools.process_query(query)
      
      # Return the response
      response
    rescue => e
      Rails.logger.error "[Scout] Tool processing error: #{e.message}"
      # Fallback to LLM if tools fail
      simple_chat_response(query)
    end
    
    def process_with_tools_streaming(query, &block)
      # Initialize Scout tools service with limited toolset
      scout_tools = Amos::ScoutToolsService.new(@context)
      scout_tools.intent_mode = @intent_mode  # Pass intent mode for role adaptation
      
      # Process the query with tools and streaming
      scout_tools.process_query_streaming(query) do |chunk|
        if chunk.is_a?(String)
          # Skip progress messages like "🤖 Processing request..."
          Rails.logger.debug "[Scout] Progress: #{chunk}"
        elsif chunk.is_a?(Hash)
          # Pass through content chunks to the stream callback
          if chunk[:type] == "content_chunk"
            yield chunk[:content] if block_given?
          elsif chunk[:type] == "canvas_update"
            # Handle canvas updates by broadcasting them
            Rails.logger.info "[Scout] Canvas update: #{chunk[:canvas_type]}"
            # Pass the canvas update through for the orchestrator to handle
            yield({ type: 'canvas_update', canvas_type: chunk[:canvas_type], canvas_data: chunk[:canvas_data] }) if block_given?
          elsif chunk[:type] == "tool_start" || chunk[:type] == "tool_use"
            # Log tool usage but don't stream it
            Rails.logger.info "[Scout] Using tool: #{chunk[:name] || chunk[:tool_name]}"
          elsif chunk[:type] == "intermediate_message"
            # Log but don't stream intermediate tool messages
            Rails.logger.info "[Scout] Tool message: #{chunk[:content]}"
          end
        end
      end
    rescue => e
      Rails.logger.error "[Scout] Tool streaming error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      # Return nil to indicate failure
      nil
    end
    
    def select_tool(query)
      case query.downcase
      when /summary|recap|what.*talked/i
        :conversation_summary
      when /business|company|profile|settings/i
        :entity_info
      when /status|jobs?|tasks?|running|progress/i
        :job_status
      when /search|look up|find.*online|current.*news/i
        :web_search
      when /knowledge|documentation|how.*work|explain/i
        :rag_query
      else
        nil
      end
    end
    
    def summarize_conversation
      messages = @context.recent_messages(20)
      
      if messages.empty?
        "We haven't discussed anything yet. How can I help you today?"
      else
        # Use a lightweight model to summarize
        summary = generate_summary(messages)
        "Here's what we've discussed:\n\n#{summary}"
      end
    end
    
    def get_entity_info(query)
      entity_data = @context.snapshot[:entity_context]
      
      if query.match?(/stripe/i)
        if entity_data[:has_stripe]
          "Your Stripe integration is connected and active."
        else
          "You haven't connected Stripe yet. Would you like me to help you set that up?"
        end
      elsif query.match?(/landing.*pages?/i)
        count = entity_data[:landing_pages_count]
        "You have #{count} landing page#{count == 1 ? '' : 's'} in your account."
      elsif query.match?(/contacts?/i)
        count = entity_data[:contacts_count]
        "You have #{count} contact#{count == 1 ? '' : 's'} in your database."
      else
        "Your business '#{entity_data[:name]}' is set up with subdomain: #{entity_data[:subdomain]}."
      end
    end
    
    def check_all_jobs
      # This would connect to actual job tracking
      "I'll check the status of all running tasks for you..."
    end
    
    def search_web(query)
      # Extract the search query
      search_term = query.gsub(/search|look up|find/i, '').strip
      
      # This would use actual web search API
      "I'll search for information about '#{search_term}'..."
    end
    
    def query_knowledge_base(query)
      # This would query the RAG store
      "Let me check our knowledge base for information about that..."
    end
    
    # COMMENTED OUT - No longer used in unified mode
    # def simple_chat_response(query)
    #   # Use a lightweight model (like Haiku) for simple responses
    #   response = generate_simple_response(query)
    #   response
    # end
    # 
    # def simple_chat_response_streaming(query, &block)
    #   # Use a lightweight model with streaming for simple responses
    #   generate_simple_response_streaming(query, &block)
    # end
    
    def generate_summary(messages)
      # Use Haiku or similar fast model
      recent_topics = messages.last(10).map { |m| m[:content] }.join("\n")
      
      # This would call actual LLM
      "Recent topics discussed: Landing pages, Stripe integration, and contact management."
    end
    
    # COMMENTED OUT - No longer used in unified mode (always using tools now)
=begin
    def generate_simple_response(query)
      # Use Haiku LLM for ALL non-agent queries
      client = BedrockService.new
      
      system_prompt = "You are Amos, the AI business assistant for #{@context.entity_snapshot[:name]}.

      You help businesses succeed through intelligent automation and thoughtful guidance.
      
      You're in CONVERSATIONAL MODE right now (no tools available), but you understand what the system can do.
      
      ═══════════════════════════════════════════════════════════════
      SYSTEM CAPABILITIES
      ═══════════════════════════════════════════════════════════════
      
      ✅ WHAT SCOUT CAN DO (when tools are available):
      • Show/view/display data (campaigns, contacts, analytics, etc.)
      • Load canvases to visualize information
      • Search and read documents
      • Count, list, and filter existing data
      • Check status and connections
      • Answer questions using available data
      
      ❌ WHAT REQUIRES A SPECIALIST:
      • Creating landing pages → Landing Page specialist
      • Building email campaigns → Email specialist
      • Complex integrations → Integration specialist
      • Data imports/exports → Data specialist
      • Any complex multi-step creation
      
      Your approach:
      - Be a knowledgeable business partner
      - Share insights and recommendations
      - If they ask to see data, acknowledge and say the system will handle it
      - If they want to create something complex, acknowledge the specialist will help
      - Focus on being helpful and conversational"
      
      messages = [
        { role: "user", content: query }
      ]
      
      begin
        # Use the model preference from the context if available, otherwise default
        model = @context.recent_messages.last&.dig(:metadata, :model_preference) || "claude-haiku-4-5-20251001"
        
        response = client.send_message(
          system_prompt,
          messages,
          model: model,
          max_tokens: 200
        )
        
        response
      rescue => e
        Rails.logger.error "[Amos] Simple query LLM error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Basic fallback
        "I'm having trouble connecting right now. Please try again or let me know if you'd like to create something specific like a landing page or email campaign."
      end
    end
=end
    
    # COMMENTED OUT - No longer used in unified mode (always using tools now)
=begin
    def generate_simple_response_streaming(query, &block)
      # Use Haiku LLM with streaming for ALL non-agent queries
      client = BedrockService.new
      
      system_prompt = "You are Amos, the AI business assistant for #{@context.entity_snapshot[:name]}.

      You help businesses succeed through intelligent automation and thoughtful guidance.
      
      You're in CONVERSATIONAL MODE right now (no tools available), but you understand what the system can do.
      
      ═══════════════════════════════════════════════════════════════
      SYSTEM CAPABILITIES
      ═══════════════════════════════════════════════════════════════
      
      ✅ WHAT SCOUT CAN DO (when tools are available):
      • Show/view/display data (campaigns, contacts, analytics, etc.)
      • Load canvases to visualize information
      • Search and read documents
      • Count, list, and filter existing data
      • Check status and connections
      • Answer questions using available data
      
      ❌ WHAT REQUIRES A SPECIALIST:
      • Creating landing pages → Landing Page specialist
      • Building email campaigns → Email specialist
      • Complex integrations → Integration specialist
      • Data imports/exports → Data specialist
      • Any complex multi-step creation
      
      Your approach:
      - Be a knowledgeable business partner
      - Share insights and recommendations
      - If they ask to see data, acknowledge and say the system will handle it
      - If they want to create something complex, acknowledge the specialist will help
      - Focus on being helpful and conversational"
      
      messages = [
        { role: "user", content: query }
      ]
      
      begin
        # Use the model preference from the context if available, otherwise default
        model = @context.recent_messages.last&.dig(:metadata, :model_preference) || "claude-haiku-4-5-20251001"
        
        accumulated_content = ""
        
        # Stream the response
        client.send_message(
          system_prompt,
          messages,
          model: model,
          max_tokens: 200,
          stream: true
        ) do |chunk|
          # Handle streaming chunks
          case chunk[:type]
          when :content
            # Stream the content chunk to the user
            yield chunk[:content] if block_given?
            accumulated_content += chunk[:content]
          when :usage
            # Log token usage but don't stream it
            Rails.logger.info "[Amos] Token usage - Input: #{chunk[:tokens][:input]}, Output: #{chunk[:tokens][:output]}" if chunk[:tokens]
          end
        end
        
        # Return the full response for logging/context
        accumulated_content
      rescue => e
        Rails.logger.error "[Amos] Simple query streaming LLM error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Stream the error message
        error_msg = "I'm having trouble connecting right now. Please try again or let me know if you'd like to create something specific like a landing page or email campaign."
        yield error_msg if block_given?
        error_msg
      end
    end
=end
  end
end

