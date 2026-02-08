# frozen_string_literal: true

module V3
  module Tools
    # BrowserUseTool - Autonomous AI-driven web browsing
    #
    # This is "computer use" — Amos autonomously controls a headless browser:
    #   1. Navigate to a URL
    #   2. Take a screenshot
    #   3. Analyze what's on screen (via the LLM seeing the result)
    #   4. Perform actions (click, type, scroll, etc.)
    #   5. Take another screenshot to see what changed
    #   6. Repeat until the task is done
    #
    # Supports handoff: user browses interactively to log in, then Amos
    # takes over with the user's cookies for autonomous work.
    #
    # Each call performs ONE action and returns the result + screenshot.
    # The agent loop naturally handles the iteration (call tool -> see result -> call again).
    #
    class BrowserUseTool < ::Tools::BaseTool
      MAX_SCREENSHOT_CACHE_TTL = 5.minutes

      def self.metadata
        {
          name: "browser_use",
          description: <<~DESC.strip,
            Interactive web browser for tasks that REQUIRE clicking, typing, or navigating a real website.
            Use ONLY when you need to interact with a webpage (fill forms, click buttons, take screenshots, log in).
            Do NOT use for simple information lookups -- use web_search instead.
            Each call performs ONE action and returns page state. Supports user handoff for login.
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: "The browser action to perform",
                enum: %w[navigate click type scroll screenshot press_key wait page_state handoff_to_user resume_from_user close]
              },
              url: {
                type: "string",
                description: "For navigate: the URL to visit"
              },
              selector: {
                type: "string",
                description: "For click/type: CSS selector, or 'text=Click Me' for text-based selection"
              },
              text: {
                type: "string",
                description: "For type: the text to enter. For wait: text to wait for on page."
              },
              key: {
                type: "string",
                description: "For press_key: key name (Enter, Tab, Escape, etc.)"
              },
              direction: {
                type: "string",
                description: "For scroll: direction (up, down, top, bottom)",
                enum: %w[up down top bottom]
              },
              clear: {
                type: "boolean",
                description: "For type: clear existing text before typing (default: true)"
              },
              wait_seconds: {
                type: "number",
                description: "For wait: seconds to wait (default: 2)"
              }
            },
            required: ["action"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        action = get_arg(args, :action)&.to_s&.downcase
        return error_response("Missing: action") if action.blank?

        case action
        when "navigate"
          do_navigate(args)
        when "click"
          do_click(args)
        when "type"
          do_type(args)
        when "scroll"
          do_scroll(args)
        when "screenshot"
          do_screenshot
        when "press_key"
          do_press_key(args)
        when "wait"
          do_wait(args)
        when "page_state"
          do_page_state
        when "handoff_to_user"
          do_handoff_to_user(args)
        when "resume_from_user"
          do_resume_from_user(args)
        when "close"
          do_close
        else
          error_response("Unknown action: #{action}. Use: navigate, click, type, scroll, screenshot, press_key, wait, page_state, handoff_to_user, resume_from_user, close")
        end
      rescue => e
        Rails.logger.error "[V3::BrowserUse] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Browser error: #{e.message}")
      end

      private

      # ═══════════════════════════════════════════════════════════════
      # ACTIONS
      # ═══════════════════════════════════════════════════════════════

      def do_navigate(args)
        url = get_arg(args, :url)
        return error_response("Missing: url") if url.blank?

        result = browser_session.navigate(url)
        build_action_response("navigate", result)
      end

      def do_click(args)
        selector = get_arg(args, :selector)
        return error_response("Missing: selector") if selector.blank?

        result = browser_session.click(selector)
        build_action_response("click", result)
      end

      def do_type(args)
        selector = get_arg(args, :selector)
        text = get_arg(args, :text)
        clear = get_arg(args, :clear, true)
        return error_response("Missing: selector") if selector.blank?
        return error_response("Missing: text") if text.blank?

        result = browser_session.type(selector, text, clear: clear)
        build_action_response("type", result)
      end

      def do_scroll(args)
        direction = get_arg(args, :direction, "down")
        result = browser_session.scroll(direction: direction.to_sym)
        build_action_response("scroll", result)
      end

      def do_screenshot
        build_action_response("screenshot", { success: true, action: :screenshot })
      end

      def do_press_key(args)
        key = get_arg(args, :key)
        return error_response("Missing: key") if key.blank?

        result = browser_session.press_key(key)
        build_action_response("press_key", result)
      end

      def do_wait(args)
        seconds = get_arg(args, :wait_seconds, 2).to_f
        text = get_arg(args, :text)

        if text.present?
          result = browser_session.wait(text: text)
        else
          result = browser_session.wait(seconds: [seconds, 30].min)
        end
        build_action_response("wait", result)
      end

      def do_page_state
        state = browser_session.page_state
        elements = state[:interactive_elements] || []

        # Format elements for the AI to understand
        element_summary = elements.first(30).map do |el|
          parts = [el[:type]]
          parts << "\"#{el[:text]}\"" if el[:text].present?
          parts << "##{el[:id]}" if el[:id].present?
          parts << ".#{el[:className]}" if el[:className].present?
          parts << "→ #{el[:href]}" if el[:href].present?
          "  [#{el[:index]}] #{parts.join(' ')}"
        end.join("\n")

        success_response(
          action: "page_state",
          url: state[:url],
          title: state[:title],
          text_preview: state[:text_preview],
          interactive_elements_count: elements.length,
          interactive_elements: element_summary,
          message: "Page has #{elements.length} interactive elements. Use selector to target them."
        )
      end

      def do_handoff_to_user(args)
        url = browser_session.current_page_url || get_arg(args, :url)

        # Open interactive view for user to browse/log in
        session_id = browser_session.session_id
        domain = begin
          URI.parse(url.to_s).host
        rescue
          url
        end

        # Show the browser session canvas with handoff UI
        @context[:canvas_suggestion] = "browser_session"

        canvas_data = {
          session_id: session_id,
          url: url,
          title: "Log in to #{domain}",
          status: "handoff",
          message: "I need you to log in to #{domain}. Use the interactive browser above to sign in, then click 'Hand Back to Amos' when you're done.",
          login_required: true,
          proxy_host: domain
        }

        # Cache screenshot for display
        cache_screenshot(session_id)

        progress_callback = @context[:progress_callback]
        progress_callback&.call({
          type: :canvas_suggestion,
          canvas: "browser_session",
          data: canvas_data
        })

        success_response(
          action: "handoff_to_user",
          session_id: session_id,
          url: url,
          domain: domain,
          message: "I've opened #{domain} for you to log in. After signing in, tell me to continue and I'll pick up where you left off.",
          canvas_type: "browser_session",
          canvas_data: canvas_data
        )
      end

      def do_resume_from_user(args)
        session_id = browser_session.session_id
        url = browser_session.current_page_url

        domain = begin
          URI.parse(url.to_s).host
        rescue
          nil
        end

        # Sync cookies from the interactive proxy session
        if domain.present?
          proxy_session_id = context[:session_id] || session_id
          cache_key = "web_proxy_cookie_jar:#{proxy_session_id}:#{domain}"
          cookie_jar = Rails.cache.read(cache_key)

          if cookie_jar.is_a?(Hash) && cookie_jar.any?
            browser_session.apply_cookie_jar(url, cookie_jar)
            Rails.logger.info "[V3::BrowserUse] Synced #{cookie_jar.size} cookies from interactive session for #{domain}"

            # Refresh the page with new cookies
            browser_session.refresh
          else
            Rails.logger.warn "[V3::BrowserUse] No cookies found for #{domain} — user may not have logged in"
          end
        end

        build_action_response("resume_from_user", {
          success: true,
          action: :resume_from_user,
          message: "Resumed control. Cookies synced from your session."
        })
      end

      def do_close
        session_id = browser_session.session_id
        BrowserSessionService.close_session(session_id)

        success_response(
          action: "close",
          message: "Browser session closed."
        )
      end

      # ═══════════════════════════════════════════════════════════════
      # HELPERS
      # ═══════════════════════════════════════════════════════════════

      def browser_session
        @browser_session ||= BrowserSessionService.find_or_create(
          user_id: user.id,
          session_id: context[:session_id] || "browser_#{user.id}"
        )
      end

      def build_action_response(action_name, result)
        return error_response("Action failed: #{result[:error]}") unless result[:success] != false

        session_id = browser_session.session_id

        # Cache a screenshot for the browser_session canvas
        screenshot_url = cache_screenshot(session_id)

        # Get page state for AI context (text + elements)
        state = browser_session.page_state rescue {}
        elements = state[:interactive_elements] || []
        text = state[:text_preview] || ""

        # Show browser session canvas
        @context[:canvas_suggestion] = "browser_session"

        canvas_data = {
          session_id: session_id,
          url: browser_session.current_page_url,
          title: browser_session.page_title,
          screenshot_url: screenshot_url,
          action: action_name,
          status: "ready",
          message: "Action '#{action_name}' completed"
        }

        progress_callback = @context[:progress_callback]
        progress_callback&.call({
          type: :canvas_suggestion,
          canvas: "browser_session",
          data: canvas_data
        })

        # Build response with enough context for AI to decide next action
        response = {
          action: action_name,
          url: browser_session.current_page_url,
          title: browser_session.page_title,
          page_text: text.truncate(3000),
          interactive_elements_count: elements.length,
          canvas_type: "browser_session",
          canvas_data: canvas_data,
          message: "#{action_name} completed on #{browser_session.current_page_url}"
        }

        # Include top interactive elements for AI to know what's clickable
        if elements.any?
          top_elements = elements.first(20).map do |el|
            parts = [el[:type]]
            parts << "\"#{el[:text]}\"" if el[:text].present?
            parts << "##{el[:id]}" if el[:id].present?
            parts << "→ #{el[:href]}" if el[:href].present?
            parts.join(" ")
          end
          response[:clickable_elements] = top_elements
        end

        success_response(**response)
      end

      def cache_screenshot(session_id)
        png_bytes = browser_session.screenshot(format: :png)
        token = SecureRandom.hex(12)
        cache_key = "browser_session_screenshot:#{session_id}:#{token}"
        Rails.cache.write(cache_key, png_bytes, expires_in: MAX_SCREENSHOT_CACHE_TTL)

        "/scout/browser_session_screenshot/#{session_id}?token=#{token}"
      rescue => e
        Rails.logger.warn "[V3::BrowserUse] Screenshot cache failed: #{e.message}"
        nil
      end
    end
  end
end
