# frozen_string_literal: true

# V3AgentSupport - Controller concern for V3 agent loop integration
#
# Include this in ScoutController to add V3 support.
# V3 runs alongside V2, controlled by feature flag.
#
# Usage in controller:
#   include V3AgentSupport
#
#   # In chat_stream:
#   if v3_enabled?
#     process_through_v3(message, file_urls, current_canvas, selected_model)
#     return
#   end
#   # ... existing V2 code ...
#
module V3AgentSupport
  extend ActiveSupport::Concern

  private

  # Check if V3 is enabled for this request
  def v3_enabled?
    V3::FeatureFlag.enabled?(user: current_user, entity: current_entity)
  end

  # Process a message through V3 agent loop
  def process_through_v3(message, file_urls, current_canvas, model_preference)
    Rails.logger.info "[V3] Processing through V3 agent loop"

    # Stream thinking indicator
    stream_update("🧠 Processing...") if respond_to?(:stream_update, true)

    # Build enhanced message if files attached
    enhanced_message = build_v3_message(message, file_urls)

    # Save user message
    save_scout_message("user", enhanced_message) if respond_to?(:save_scout_message, true)

    # Determine model
    model = model_preference || session[:premium_model] || ENV.fetch("BEDROCK_DEFAULT_MODEL", "anthropic.claude-sonnet-4-v1")

    # Extract canvas context
    canvas_type = if current_canvas.is_a?(Hash) || current_canvas.is_a?(ActionController::Parameters)
                    current_canvas["type"] || current_canvas[:type]
                  elsif current_canvas.is_a?(String)
                    current_canvas
                  end

    # Create V3 agent loop
    agent = V3::AgentLoop.new(
      user: current_user,
      entity: current_entity,
      session_id: session[:scout_session_id],
      model: model
    )

    # Get conversation history
    conversation_history = respond_to?(:persisted_history_last_k, true) ?
      persisted_history_last_k(20) : []

    # Process with streaming
    result = agent.process_message_streaming(
      enhanced_message,
      method(:handle_v3_chunk),
      conversation_history,
      canvas_type
    )

    # Handle the result
    handle_v3_result(result)

  rescue ::Tools::AskUserTool::ExecutionSuspended => e
    # Handle ask_user suspension
    Rails.logger.info "[V3] Ask user suspension"
    stream_update(e.message) if respond_to?(:stream_update, true)
  rescue => e
    Rails.logger.error "[V3] Error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    stream_update("❌ An error occurred. Please try again.") if respond_to?(:stream_update, true)
  end

  # Handle streaming chunks from V3 agent loop
  def handle_v3_chunk(chunk)
    return unless chunk.is_a?(Hash)

    case chunk[:type]
    when :content
      # Stream text content to frontend
      if chunk[:text].present? && respond_to?(:stream_content, true)
        stream_content(chunk[:text])
      end
    when :canvas_suggestion
      # Broadcast canvas change
      if respond_to?(:stream_canvas, true)
        stream_canvas(chunk[:canvas], chunk[:data])
      end
    when :ask_user
      # Stream question to user
      if respond_to?(:stream_update, true)
        stream_update(chunk[:question])
      end
    when :status
      # Stream status update
      if respond_to?(:stream_update, true)
        stream_update(chunk[:text])
      end
    end
  end

  # Handle the final result from V3
  def handle_v3_result(result)
    return unless result.is_a?(Hash)

    response_message = result.dig(:final_response, :message)
    
    # Save assistant response
    if response_message.present? && respond_to?(:save_scout_message, true)
      save_scout_message("assistant", response_message)
    end

    # Stream canvas if suggested
    if result[:suggested_canvas] && respond_to?(:stream_canvas, true)
      stream_canvas(result[:suggested_canvas], result[:canvas_data])
    end

    # Log V3 metrics
    Rails.logger.info "[V3] Complete. Tools used: #{result[:tools_used]&.join(', ')}, " \
                      "Model: #{result[:model_used]}, Version: #{result[:version]}"
  end

  def build_v3_message(message, file_urls)
    return message if file_urls.blank? || file_urls.empty?

    file_details = file_urls.map do |f|
      id = f["asset_id"] || f["document_id"]
      asset_type = f["asset_type"] || "image"
      "📎 #{f['filename']} (asset_id: #{id}, asset_type: #{asset_type}, type: #{f['content_type']})"
    end.join(", ")

    "#{message}\n\n[Attached Files: #{file_details}]\n\nUse read_file to extract content from these files."
  end
end
