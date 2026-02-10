# frozen_string_literal: true

module V3
  # AgentEvents - Formal event type definitions for the agent loop
  #
  # Defines the contract between the agent loop and any consumer (SSE streaming,
  # WebSocket, tests, etc.). Inspired by Pi's typed EventStream.
  #
  # Events flow: AgentLoop -> progress_callback -> Controller -> SSE -> Frontend
  #
  # Usage:
  #   include V3::AgentEvents
  #   emit(content_event("Hello!"))
  #   emit(working_event("web_search"))
  #   emit(canvas_event("contact_viewer", { contact_id: 123 }))
  #
  module AgentEvents
    # ═══════════════════════════════════════════════════════════════
    # EVENT TYPES
    # ═══════════════════════════════════════════════════════════════

    # Content: text streamed to the user in real-time (the model talking)
    CONTENT = :content

    # Working: tool execution in progress (shows spinner/indicator)
    WORKING = :working

    # Canvas: load a canvas view in the UI
    CANVAS = :canvas_suggestion

    # Thinking: model is processing (before any output)
    THINKING = :thinking

    # Thinking Done: model has started producing output
    THINKING_DONE = :thinking_done

    # Status: informational status message (non-persistent)
    STATUS = :status

    # Clear Content: remove previously streamed content from the UI
    # (used when hallucination guard fires and model needs to retry)
    CLEAR_CONTENT = :clear_content

    # Ask User: model needs clarification from user
    ASK_USER = :ask_user

    # ═══════════════════════════════════════════════════════════════
    # EVENT CONSTRUCTORS
    #
    # Each method returns a hash that the progress_callback expects.
    # This is the formal contract — consumers can rely on these shapes.
    # ═══════════════════════════════════════════════════════════════

    # Text content being streamed to the user
    # @param text [String] The text chunk to stream
    # @return [Hash] { type: :content, text: "..." }
    def content_event(text)
      { type: CONTENT, text: text }
    end

    # Tool execution in progress
    # @param tool_name [String] Name of the tool being executed
    # @return [Hash] { type: :working, tool_name: "..." }
    def working_event(tool_name)
      { type: WORKING, tool_name: tool_name }
    end

    # Load a canvas view
    # @param canvas_name [String] The canvas to show
    # @param data [Hash] Data to pass to the canvas
    # @return [Hash] { type: :canvas_suggestion, canvas: "...", data: {...} }
    def canvas_event(canvas_name, data = {})
      { type: CANVAS, canvas: canvas_name, data: data }
    end

    # Thinking indicator (before any output)
    # @param message [String] Optional thinking message
    # @return [Hash] { type: :thinking, message: "..." }
    def thinking_event(message = "Thinking")
      { type: THINKING, message: message }
    end

    # Thinking done (model started producing)
    # @return [Hash] { type: :thinking_done }
    def thinking_done_event
      { type: THINKING_DONE }
    end

    # Status message (informational, non-persistent)
    # @param text [String] Status text
    # @return [Hash] { type: :status, text: "..." }
    def status_event(text)
      { type: STATUS, text: text }
    end

    # Clear previously streamed content from the UI
    # @return [Hash] { type: :clear_content }
    def clear_content_event
      { type: CLEAR_CONTENT }
    end

    # Ask user for clarification
    # @param question [String] The question to ask
    # @return [Hash] { type: :ask_user, question: "..." }
    def ask_user_event(question)
      { type: ASK_USER, question: question }
    end
  end
end
