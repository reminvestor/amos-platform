class CouncilResearchJob < ApplicationJob
  queue_as :agents

  def perform(entity_id:, user_id:, session_id:, research_id:, query:, depth:, include_peer_review: nil)
    entity = Entity.find(entity_id)
    user = User.find(user_id)
    # Use the passed session_id for ActionCable broadcasts (matches the user's active session)

    Rails.logger.info "🔬 CouncilResearchJob started: #{research_id}"
    Rails.logger.info "   Query: #{query.truncate(100)}"
    Rails.logger.info "   Depth: #{depth}"

    # Get depth configuration for model info
    depth_config = CouncilResearchService::DEPTH_CONFIGS[depth.to_sym]
    model_names = depth_config[:models].map { |m| OpenrouterService::MODELS[m][:name] }

    # Broadcast initial progress
    broadcast_progress(session_id, research_id, {
      status: "starting",
      message: "Initializing AI Council...",
      progress: 5
    })

    # Send a chat message showing which models we're querying
    ScoutChannel.broadcast_to(session_id, {
      type: "content",
      content: format_starting_message(query, depth, model_names, depth_config[:peer_review])
    })

    begin
      # Initialize the research service with user for token billing
      service = CouncilResearchService.new(entity, user: user)

      broadcast_progress(session_id, research_id, {
        status: "querying_models",
        message: "Querying #{model_names.size} AI models in parallel...",
        progress: 15,
        models: model_names
      })

      # Execute the research
      result = service.execute(
        query: query,
        depth: depth,
        include_peer_review: include_peer_review,
        use_cache: true
      )

      if result[:status] == "complete"
        # Broadcast successful completion
        broadcast_progress(session_id, research_id, {
          status: "synthesizing",
          message: "Chairman synthesizing final answer...",
          progress: 90
        })

        # Short delay to show synthesis message
        sleep(0.5)

        # Broadcast final result and load canvas
        broadcast_completion(session_id, research_id, result)

        Rails.logger.info "✅ CouncilResearchJob completed: #{research_id}"
      else
        # Handle error
        broadcast_error(session_id, research_id, result[:error] || "Research failed")
        Rails.logger.error "❌ CouncilResearchJob failed: #{result[:error]}"
      end

    rescue => e
      Rails.logger.error "❌ CouncilResearchJob error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      broadcast_error(session_id, research_id, e.message)
      raise
    end
  end

  private

  def broadcast_progress(session_id, research_id, data)
    ScoutChannel.broadcast_to(session_id, {
      type: "research_progress",
      research_id: research_id,
      **data,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_completion(session_id, research_id, result)
    # First broadcast the completion status
    ScoutChannel.broadcast_to(session_id, {
      type: "research_progress",
      research_id: research_id,
      status: "complete",
      message: "Research complete!",
      progress: 100,
      timestamp: Time.current.iso8601
    })

    # Then load the canvas with full results
    ScoutChannel.broadcast_to(session_id, {
      type: "load_canvas",
      canvas: "research_council",
      canvas_data: format_canvas_data(research_id, result)
    })

    # Also send a content message to the chat
    ScoutChannel.broadcast_to(session_id, {
      type: "content",
      content: format_chat_summary(result)
    })
  end

  def broadcast_error(session_id, research_id, error_message)
    ScoutChannel.broadcast_to(session_id, {
      type: "research_progress",
      research_id: research_id,
      status: "error",
      message: "Research failed: #{error_message}",
      progress: 0,
      timestamp: Time.current.iso8601
    })

    # Send error message to chat
    ScoutChannel.broadcast_to(session_id, {
      type: "content",
      content: "❌ **Research Failed**\n\n#{error_message}\n\nPlease try again or rephrase your query."
    })
  end

  def format_canvas_data(research_id, result)
    {
      research_id: research_id,
      query: result[:query],
      depth: result[:depth],
      status: result[:status],
      started_at: result[:started_at]&.iso8601,
      completed_at: result[:completed_at]&.iso8601,
      duration_ms: result[:duration_ms],

      # Individual model responses
      responses: result[:responses].transform_values do |response|
        {
          model_name: response[:model_name],
          provider: response[:provider],
          content: response[:content],
          success: response[:success],
          error: response[:error],
          duration_ms: response[:duration_ms],
          tokens: response[:tokens],
          cost_estimate: response[:cost_estimate]
        }
      end,

      # Peer reviews (if enabled)
      peer_reviews: result[:peer_reviews],

      # Synthesized answer
      synthesis: result[:synthesis],

      # Cost tracking
      total_cost: result[:total_cost],

      # Metadata
      from_cache: result[:from_cache] || false
    }
  end

  def format_starting_message(query, depth, model_names, peer_review)
    depth_label = case depth.to_s
    when "quick" then "Quick"
    when "standard" then "Standard"
    when "deep" then "Deep"
    else depth.to_s.titleize
    end

    <<~MARKDOWN.strip
      ## 🔬 Starting AI Council Research

      **Query:** "#{query.truncate(100)}"
      **Mode:** #{depth_label} (#{model_names.size} models#{peer_review ? " + peer review" : ""})

      **Querying via OpenRouter:**
      #{model_names.map { |name| "• #{name}" }.join("\n")}

      *Results will appear in the canvas when complete...*
    MARKDOWN
  end

  def format_chat_summary(result)
    synthesis = result[:synthesis]

    # Get successful model names
    successful_models = result[:responses]
      .select { |_, r| r[:success] }
      .map { |_, r| "#{r[:model_name]} (#{r[:provider]})" }

    failed_models = result[:responses]
      .reject { |_, r| r[:success] }
      .map { |_, r| r[:model_name] }

    summary = <<~MARKDOWN
      ## 🔬 Research Complete

      **Query:** #{result[:query]}
      **Duration:** #{(result[:duration_ms] / 1000.0).round(1)}s
      #{result[:from_cache] ? "*(cached result)*" : ""}

      **Models that contributed:**
      #{successful_models.map { |m| "✓ #{m}" }.join("\n")}
      #{failed_models.any? ? "\n**Failed:** #{failed_models.join(', ')}" : ""}

      ---

      #{synthesis[:content]&.truncate(1500) || "No synthesis available"}

      ---

      *View the full research in the canvas panel for individual model responses.*
    MARKDOWN

    summary.strip
  end
end
