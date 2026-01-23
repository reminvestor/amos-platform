# frozen_string_literal: true

require "cgi"
require "net/http"

module Tools
  # WebPageViewTool
  # Displays a web page in the Scout canvas with multiple viewing modes:
  # - iframe: Direct embedding (for sites that allow it)
  # - screenshot: Static capture with text extraction (using Ferrum)
  # - interactive: Live browsing via server-side proxy (bypasses X-Frame-Options)
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
                     "BOTH modes are fully supported - there are NO restrictions on interactive mode! " \
                     "Ask user which mode they prefer: " \
                     "'screenshot' = static capture with extracted text (faster, good for design reference) or " \
                     "'interactive' = live browser session (allows clicking, navigation, form filling). " \
                     "When user says 'interactive', call this tool with mode='interactive' immediately.",
        category: "research",
        input_schema: {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "The URL of the web page to display (e.g., 'https://stripe.com' or 'stripe.com')"
            },
            mode: {
              type: "string",
              description: "REQUIRED - The user's chosen viewing mode. " \
                           "'screenshot' = static capture with text extraction (faster, good for design reference), " \
                           "'interactive' = live browsing session in canvas (allows clicking, navigation, form filling). " \
                           "BOTH modes work - no security restrictions!",
              enum: %w[screenshot interactive]
            }
          },
          required: %w[url mode]
        }
      }
    end

    def execute(args)
      log_execution(args)

      url = get_arg(args, :url)
      mode = get_arg(args, :mode) || get_arg(args, :capture_mode)

      # Validate required args
      if error = validate_required_args(args, [:url])
        return error
      end

      # Check if mode was provided - if not, prompt to ask user
      if mode.blank?
        return error_response(
          "Please ask the user which viewing mode they prefer: " \
          "'screenshot' (static capture, faster) or 'interactive' (live browsing, can click around). " \
          "Then call this tool again with their choice."
        )
      end

      # Normalize URL
      url = normalize_url(url)

      # Validate URL
      unless valid_url?(url)
        return error_response("Invalid URL provided. Please provide a valid web address.")
      end

      # Generate a unique request ID for tracking
      request_id = SecureRandom.uuid

      case mode.to_s.downcase
      when "interactive"
        execute_interactive_mode(url, request_id)
      when "screenshot"
        execute_screenshot_mode(url, request_id)
      when "embed"
        # Legacy support
        execute_embed_mode(url, request_id)
      when "auto"
        # Legacy support - default to screenshot for auto
        execute_screenshot_mode(url, request_id)
      else
        # Unknown mode - default to screenshot
        execute_screenshot_mode(url, request_id)
      end
    end

    private

    def execute_interactive_mode(url, request_id)
      # Interactive mode uses a server-side proxy to bypass X-Frame-Options
      # The proxy strips restrictive headers and rewrites links
      proxy_session_id = @context&.dig(:task_session_id) || @context&.dig("task_session_id") ||
                         @context&.dig(:session_id) || @context&.dig("session_id") ||
                         request_id

      # Pre-flight check: test if the site is accessible via proxy
      # Some sites (Cloudflare-protected) block simple HTTP requests
      if site_blocks_proxy?(url)
        Rails.logger.info "[WebPageViewTool] Site #{url} blocks proxy requests, falling back to screenshot mode"
        return execute_screenshot_mode_with_notice(url, request_id,
          "This site has bot protection that blocks our proxy. Taking a screenshot instead...")
      end

      canvas_data = {
        url: url,
        request_id: request_id,
        display_mode: "interactive",
        proxy_url: "/web_proxy?psid=#{CGI.escape(proxy_session_id.to_s)}&url=#{CGI.escape(url)}",
        status: "loading",
        message: "Loading #{extract_domain(url)} in interactive mode..."
      }

      load_canvas("web_page_viewer", canvas_data)

      success_response(
        message: "Opening #{extract_domain(url)} in interactive mode - you can click and navigate!",
        url: url,
        display_mode: "interactive",
        status: "loading",
        request_id: request_id
      )
    end

    def site_blocks_proxy?(url)
      # Quick HEAD request to check if site is accessible
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Head.new(uri.request_uri)
      request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
      request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

      response = http.request(request)

      # 403, 429, or Cloudflare challenge responses indicate blocking
      blocked_codes = [403, 429, 503]
      if blocked_codes.include?(response.code.to_i)
        Rails.logger.info "[WebPageViewTool] Site returned #{response.code} - likely bot protection"
        return true
      end

      # Check for Cloudflare challenge in response headers
      if response["cf-ray"] && response.code.to_i >= 400
        Rails.logger.info "[WebPageViewTool] Cloudflare challenge detected"
        return true
      end

      false
    rescue StandardError => e
      Rails.logger.warn "[WebPageViewTool] Pre-flight check failed: #{e.message}"
      # If we can't check, assume it might work
      false
    end

    def execute_screenshot_mode_with_notice(url, request_id, notice)
      schedule_capture(url, request_id)

      canvas_data = {
        url: url,
        request_id: request_id,
        display_mode: "screenshot",
        status: "capturing",
        message: notice
      }

      load_canvas("web_page_viewer", canvas_data)

      success_response(
        message: notice,
        url: url,
        display_mode: "screenshot",
        status: "capturing",
        request_id: request_id,
        fallback_reason: "Site has bot protection that blocks our interactive proxy"
      )
    end

    def execute_screenshot_mode(url, request_id)
      schedule_capture(url, request_id)

      canvas_data = {
        url: url,
        request_id: request_id,
        display_mode: "screenshot",
        status: "capturing",
        message: "Capturing screenshot of #{extract_domain(url)}..."
      }

      load_canvas("web_page_viewer", canvas_data)

      success_response(
        message: "Capturing screenshot of #{extract_domain(url)}",
        url: url,
        display_mode: "screenshot",
        status: "capturing",
        request_id: request_id
      )
    end

    def execute_embed_mode(url, request_id)
      canvas_data = {
        url: url,
        request_id: request_id,
        display_mode: "iframe",
        status: "ready",
        message: "Loading #{extract_domain(url)}..."
      }

      load_canvas("web_page_viewer", canvas_data)

      success_response(
        message: "Opening #{extract_domain(url)} in embedded mode",
        url: url,
        display_mode: "iframe",
        status: "ready",
        request_id: request_id
      )
    end

    def execute_auto_mode(url, request_id)
      # Check if site can be embedded
      can_embed = WebPageCaptureService.likely_embeddable?(url)

      if can_embed
        # Try iframe first
        execute_embed_mode(url, request_id)
      else
        # Fall back to screenshot
        execute_screenshot_mode(url, request_id)
      end
    end

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
      # Get entity and user from instance variables (set by BaseTool)
      # Fall back to context if not available
      entity_id = @entity&.id || @context&.dig(:entity_id) || @context&.dig("entity_id")
      user_id = @user&.id || @context&.dig(:user_id) || @context&.dig("user_id")
      task_session_id = @context&.dig(:task_session_id) || @context&.dig("task_session_id") ||
                        @context&.dig(:session_id) || @context&.dig("session_id")

      Rails.logger.info "[WebPageViewTool] Scheduling capture - entity: #{entity_id}, user: #{user_id}, session: #{task_session_id}"

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
      # Get session ID from context - try multiple keys
      session_id = @context&.dig(:task_session_id) || @context&.dig("task_session_id") ||
                   @context&.dig(:session_id) || @context&.dig("session_id")

      if session_id.present?
        # Broadcast canvas load to the active session
        begin
          ScoutChannel.broadcast_to(session_id, {
            type: 'load_canvas',
            canvas: canvas_type,
            canvas_data: canvas_data,
            message: "Loading web page..."
          })
          Rails.logger.info "?? [WebPageViewTool] Broadcast canvas load to session: #{session_id}"
        rescue => e
          Rails.logger.warn "?? [WebPageViewTool] Failed to broadcast canvas: #{e.message}"
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
                canvas: canvas_type,
                canvas_data: canvas_data,
                message: "Loading web page..."
              })
              Rails.logger.info "?? [WebPageViewTool] Broadcast canvas load to session: #{sid}"
            rescue => e
              Rails.logger.warn "?? [WebPageViewTool] Failed to broadcast to session #{sid}: #{e.message}"
            end
          end
        else
          Rails.logger.warn "?? [WebPageViewTool] No session_id or user available for canvas broadcast"
        end
      end
    end
  end
end
