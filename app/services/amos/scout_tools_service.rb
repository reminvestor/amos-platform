# Scout Tools Service - Uses existing main_chat agent loadout
# Handles data fetching, displaying, and basic operations
# Complex creation tasks are still delegated to specialized agents

module Amos
  class ScoutToolsService
    attr_accessor :intent_mode
    
    def initialize(context)
      @context = context
      @user = context.user
      @entity = context.entity
      @session_id = context.session_id
      @intent_mode = nil # Set by orchestrator: :personal, :ideate, :operate, :create
    end
    
    def process_query(query)
      # Use the existing ScoutGenericToolsServiceV2 with main_chat loadout
      service = create_scout_service
      
      # Get the current canvas from the most recent message's metadata
      current_canvas = @context.recent_messages(1).first&.dig(:metadata, :canvas)
      
      # Set context including attached files if present
      context_data = {
        query: query,
        entity: @entity.attributes,
        recent_messages: @context.recent_messages(5)
      }
      
      # Check if query mentions attached files and extract asset IDs
      if query.match?(/\[Attached Files:.*asset_id:\s*(\d+)/i)
        Rails.logger.info "[Scout Tools] Detected attached files in query"
        # Extract file info from the query
        attached_files = []
        query.scan(/📎\s*([^(]+)\s*\(asset_id:\s*(\d+)(?:,\s*type:\s*([^)]+))?\)/i).each do |match|
          attached_files << {
            filename: match[0].strip,
            asset_id: match[1],
            content_type: match[2]&.strip
          }
        end
        if attached_files.any?
          context_data[:attached_files] = attached_files
          Rails.logger.info "[Scout Tools] Extracted #{attached_files.size} attached files: #{attached_files.inspect}"
        end
      end
      
      service.set_context(context_data)
      
      # Pass the current canvas to the Scout service
      Rails.logger.info "[Scout Tools] Current canvas from context: #{current_canvas.inspect}" if current_canvas
      
      # Process with tools (non-streaming)
      # Note: V2 requires streaming callback, so we collect the response
      accumulated_response = ""
      result = service.process_message_with_tools_streaming(
        query,
        ->(chunk) { 
          # Handle different chunk types
          if chunk.is_a?(Hash)
            if chunk[:type] == "content_chunk"
              accumulated_response += chunk[:content] || ""
            elsif chunk[:type] == "intermediate_message"
              # Optionally handle tool messages
              Rails.logger.info "[Scout] Tool message: #{chunk[:content]}"
            end
          elsif chunk.is_a?(String)
            # Some chunks might be plain strings
            accumulated_response += chunk
          end
        },
        @context.recent_messages(12),  # Full 12 message context window
        current_canvas  # Pass the canvas as the 4th parameter
      )
      
      # Return the final response or accumulated content
      if result.is_a?(Hash) && result[:final_response] && result[:final_response][:message]
        result[:final_response][:message]
      else
        accumulated_response
      end
    rescue => e
      Rails.logger.error "[Scout Tools] Error: #{e.message}"
      nil
    end
    
    def process_query_streaming(query, &block)
      # Use ScoutGenericToolsServiceV2 with main_chat loadout for streaming
      service = create_scout_service
      
      # Get the current canvas from the most recent message's metadata
      current_canvas = @context.recent_messages(1).first&.dig(:metadata, :canvas)
      
      # Set context including attached files if present
      context_data = {
        query: query,
        entity: @entity.attributes,
        recent_messages: @context.recent_messages(5)
      }
      
      # Check if query mentions attached files and extract asset IDs
      if query.match?(/\[Attached Files:.*asset_id:\s*(\d+)/i)
        Rails.logger.info "[Scout Tools Streaming] Detected attached files in query"
        # Extract file info from the query
        attached_files = []
        query.scan(/📎\s*([^(]+)\s*\(asset_id:\s*(\d+)(?:,\s*type:\s*([^)]+))?\)/i).each do |match|
          attached_files << {
            filename: match[0].strip,
            asset_id: match[1],
            content_type: match[2]&.strip
          }
        end
        if attached_files.any?
          context_data[:attached_files] = attached_files
          Rails.logger.info "[Scout Tools Streaming] Extracted #{attached_files.size} attached files: #{attached_files.inspect}"
        end
      end
      
      service.set_context(context_data)
      
      # Pass the current canvas to the Scout service
      Rails.logger.info "[Scout Tools] Current canvas from context: #{current_canvas.inspect}" if current_canvas
      
      # Process with streaming
      result = service.process_message_with_tools_streaming(
        query,
        ->(chunk) { yield chunk if block_given? },
        @context.recent_messages(12),  # Full 12 message context window
        current_canvas  # Pass the canvas as the 4th parameter
      )
      
      # Check for canvas updates
      Rails.logger.info "[Scout Tools] Final result structure: #{result.keys}" if result.is_a?(Hash)
      Rails.logger.info "[Scout Tools] Canvas type in result: #{result[:canvas_type]}" if result.is_a?(Hash)
      
      # Only broadcast canvas update if it wasn't already broadcast during tool execution
      # (canvas_type: "conversation" means no canvas was suggested or it was already broadcast)
      if result.is_a?(Hash) && result[:canvas_type].present? && result[:canvas_type] != "conversation"
        Rails.logger.info "[Scout Tools] Canvas update suggested: #{result[:canvas_type]}"
        # This should rarely happen now since canvas broadcasts happen during tool execution
        yield({ 
          type: 'canvas_update', 
          canvas_type: result[:canvas_type], 
          canvas_data: result[:canvas_data] || {}
        }) if block_given?
      end
      
      # Check if delegation occurred and there's no continuation
      if result.is_a?(Hash) && result[:final_response].is_a?(Hash)
        # If delegation occurred, there might be no message
        if result[:delegation_occurred] || result[:final_response][:delegation_occurred]
          nil
        else
          result[:final_response][:message]
        end
      else
        nil
      end
    end
    
    private
    
    def create_scout_service
      # Use the existing main_chat agent loadout from AgentLoadout model
      # Pass entity to load DB-driven tool configuration
      main_chat_loadout = AgentLoadout.new(agent_role: 'main_chat', entity: @entity)
      
      # Get the model mode from the latest message metadata (set by UI slider)
      last_message = @context.recent_messages.last
      model_mode = last_message&.dig(:metadata, :model_mode)&.to_sym || :auto
      
      # Create service with the loadout
      # Pass fresh_start_at from context to filter memory (excludes old messages from before Fresh Start)
      # Pass intent_mode for seamless role adaptation
      service = ScoutGenericToolsServiceV2.new(
        @user,
        @entity,
        @session_id,
        agent_loadout: main_chat_loadout,
        fresh_start_at: @context.respond_to?(:fresh_start_at) ? @context.fresh_start_at : nil,
        intent_mode: @intent_mode
      )
      
      # Apply the user's selected thinking depth mode
      # This controls max_tokens, temperature, and prompt modifiers
      service.set_model_mode(model_mode)
      Rails.logger.info "[ScoutToolsService] Set thinking depth mode: #{model_mode}, intent_mode: #{@intent_mode}"
      
      service
    end
  end
end
