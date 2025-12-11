# frozen_string_literal: true

module Tools
  # WebPageViewTool
  # Displays a web page in the Scout canvas. Tries iframe first, falls back to screenshot capture.
  #
  # Usage by AI:
  #   Use this tool when users want to view, preview, or see a website.
  #   Examples: "show me stripe.com", "open the Apple website", "let me see that page"
  #
  class WebPageViewTool < BaseTool
    def self.read_only?
      true # This tool only displays content
    end

    def self.metadata
      {
        name: "view_web_page",
        description: "Display a web page in the canvas. Use when users want to view, preview, or see a website. " \
                     "The page will be shown either embedded (if allowed) or as a screenshot with extracted text.",
        category: "research",
        input_schema: {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "The URL of the web page to display (e.g., 'https://stripe.com' or 'stripe.com')"
            },
            capture_mode: {
              type: "string",
              description: "How to display the page: 'auto' (try embed first, fallback to screenshot), " \
                           "'screenshot' (always capture screenshot), 'embed' (only try iframe, fail if blocked)",
              enum: %w[auto screenshot embed],
              default: "auto"
            }
          },
          required: [ "url" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      url = get_arg(args, :url)
      capture_mode = get_arg(args, :capture_mode, "auto")

      # Validate required args
      if error = validate_required_args(args, [ :url ])
        return error
      end

      # Normalize URL
      url = normalize_url(url)

      # Validate URL
      unless valid_url?(url)
        return error_response("Invalid URL provided. Please provide a valid web address.")
      end

      # Generate a unique request ID for tracking async captures
      request_id = SecureRandom.uuid

      # Determine display strategy
      can_embed = capture_mode != "screenshot" && WebPageCaptureService.likely_embeddable?(url)
      should_capture = capture_mode == "screenshot" || (capture_mode == "auto" && !can_embed)

      # Build canvas data
      canvas_data = {
        url: url,
        request_id: request_id,
        display_mode: can_embed ? "iframe" : "screenshot",
        capture_mode: capture_mode,
        show_fallback_option: capture_mode == "auto"
      }

      if should_capture
        # Start background capture job
        schedule_capture(url, request_id)
        canvas_data[:status] = "capturing"
        canvas_data[:message] = "Capturing screenshot of #{extract_domain(url)}..."
      else
        canvas_data[:status] = "ready"
        canvas_data[:message] = "Loading #{extract_domain(url)}..."
      end

      # Load the canvas with the web page viewer
      load_canvas("web_page_viewer", canvas_data)

      # Return success response
      success_response(
        message: "Opening #{extract_domain(url)} in canvas",
        url: url,
        display_mode: canvas_data[:display_mode],
        status: canvas_data[:status],
        request_id: request_id
      )
    end

    private

    def normalize_url(url)
      url = url.to_s.strip

      # Add protocol if missing
      unless url.match?(%r{\Ahttps?://}i)
        url = "https://#{url}"
      end

      url
    end

    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end

    def extract_domain(url)
      URI.parse(url).host
    rescue URI::InvalidURIError
      url
    end

    def schedule_capture(url, request_id)
      # Get entity and user from context
      entity_id = @context&.dig(:entity_id) || @context&.dig("entity_id")
      user_id = @context&.dig(:user_id) || @context&.dig("user_id")
      task_session_id = @context&.dig(:task_session_id) || @context&.dig("task_session_id")

      CaptureWebPageJob.perform_later(
        url: url,
        entity_id: entity_id,
        user_id: user_id,
        task_session_id: task_session_id,
        canvas_request_id: request_id
      )
    rescue StandardError => e
      Rails.logger.error "[WebPageViewTool] Failed to schedule capture: #{e.message}"
      # Non-fatal - the canvas will show an option to retry
    end

    def load_canvas(canvas_type, canvas_data)
      # Get session ID from context
      session_id = @context&.dig(:task_session_id) || @context&.dig("task_session_id")

      if session_id.present?
        # Broadcast canvas load to the active session
        begin
          ScoutChannel.broadcast_to(session_id, {
            type: 'load_canvas',
            canvas_name: canvas_type,
            canvas_data: canvas_data,
            message: "Loading web page..."
          })
          Rails.logger.info "📡 [WebPageViewTool] Broadcast canvas load to session: #{session_id}"
        rescue => e
          Rails.logger.warn "⚠️ [WebPageViewTool] Failed to broadcast canvas: #{e.message}"
        end
      else
        # Fallback: Find recent sessions for the user and broadcast to them
        if @user
          recent_sessions = ScoutMessage.where(user_id: @user.id)
                                        .order(created_at: :desc)
                                        .limit(20)
                                        .pluck(:session_id)
                                        .uniq
                                        .take(3)

          recent_sessions.each do |sid|
            begin
              ScoutChannel.broadcast_to(sid, {
                type: 'load_canvas',
                canvas_name: canvas_type,
                canvas_data: canvas_data,
                message: "Loading web page..."
              })
              Rails.logger.info "📡 [WebPageViewTool] Broadcast canvas load to session: #{sid}"
            rescue => e
              Rails.logger.warn "⚠️ [WebPageViewTool] Failed to broadcast to session #{sid}: #{e.message}"
            end
          end
        else
          Rails.logger.warn "⚠️ [WebPageViewTool] No session_id or user available for canvas broadcast"
        end
      end
    end
  end
end
