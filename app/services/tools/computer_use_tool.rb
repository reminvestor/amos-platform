# frozen_string_literal: true

require "cgi"

module Tools
  # ComputerUseTool
  # Allows the AI to control a web browser - navigate, click, type, scroll, etc.
  # Uses a persistent browser session that maintains state across multiple actions.
  #
  # Example usage by AI:
  #   navigate to "https://example.com"
  #   click on "button.login"
  #   type "user@example.com" into "input[name='email']"
  #   press Enter
  #   take screenshot
  #
  class ComputerUseTool < BaseTool
    def self.read_only?
      false # This tool interacts with external websites
    end

    def self.metadata
      {
        name: "computer_use",
        description: "Control a web browser to interact with websites on behalf of the user. " \
                     "You can navigate to URLs, click buttons and links, fill out forms, scroll pages, and more. " \
                     "The browser maintains state (cookies, session) across actions within a conversation. " \
                     "After each action, you receive a screenshot showing the current page state. " \
                     "IMPORTANT: Always start with a 'navigate' action to go to a URL first.",
        category: "automation",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              description: "The browser action to perform",
              enum: %w[navigate click type press_key scroll hover select wait screenshot get_state sync_proxy_session close]
            },
            url: {
              type: "string",
              description: "URL to navigate to (required for 'navigate' action)"
            },
            selector: {
              type: "string",
              description: "CSS selector or XPath to target element (for click, type, hover, select). " \
                           "Examples: 'button.submit', '#login-form input[type=email]', 'text=Sign In'"
            },
            text: {
              type: "string",
              description: "Text to type (for 'type' action) or text to wait for (for 'wait' action)"
            },
            key: {
              type: "string",
              description: "Key to press (for 'press_key' action). Examples: 'Enter', 'Tab', 'Escape', 'ArrowDown'"
            },
            direction: {
              type: "string",
              description: "Scroll direction (for 'scroll' action)",
              enum: %w[up down left right top bottom]
            },
            value: {
              type: "string",
              description: "Value to select (for 'select' action in dropdowns)"
            },
            wait_seconds: {
              type: "number",
              description: "Seconds to wait (for 'wait' action). Use when page needs time to load."
            },
            clear_first: {
              type: "boolean",
              description: "Clear the input field before typing (for 'type' action)"
            },
            proxy_session_id: {
              type: "string",
              description: "Optional proxy session id (psid) used by the interactive web proxy. " \
                           "If omitted, the tool will use the current Scout session id."
            },
            proxy_host: {
              type: "string",
              description: "Host to sync cookies for (e.g. 'resy.com'). If omitted, derived from current_url."
            }
          },
          required: %w[action]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      action = get_arg(args, :action)&.to_sym
      
      unless action
        return error_response("Missing required 'action' parameter")
      end

      # Get or create browser session
      session_id = context[:session_id] || context[:task_session_id] || "scout_#{user.id}"
      
      browser_session = BrowserSessionService.find_or_create(
        user_id: user.id,
        session_id: session_id
      )

      result = case action
      when :navigate
        handle_navigate(browser_session, args)
      when :click
        handle_click(browser_session, args)
      when :type
        handle_type(browser_session, args)
      when :press_key
        handle_press_key(browser_session, args)
      when :scroll
        handle_scroll(browser_session, args)
      when :hover
        handle_hover(browser_session, args)
      when :select
        handle_select(browser_session, args)
      when :wait
        handle_wait(browser_session, args)
      when :screenshot
        handle_screenshot(browser_session)
      when :get_state
        handle_get_state(browser_session)
      when :sync_proxy_session
        handle_sync_proxy_session(browser_session, args)
      when :close
        handle_close(browser_session)
      else
        error_response("Unknown action: #{action}")
      end

      # Always broadcast the latest browser state to the canvas (do NOT include base64 in tool results).
      if result[:success] && action != :close
        broadcast_browser_state(result, args, browser_session)
      end

      result
    end

    private

    def handle_navigate(session, args)
      url = get_arg(args, :url)
      return error_response("Missing 'url' parameter for navigate action") unless url

      apply_persisted_user_cookies_for_url(session, url)

      result = session.navigate(url)
      
      if result[:success]
        success_response(
          {
            page_title: result[:title],
            current_url: result[:url],
            # Screenshot is broadcast to the canvas; omit from tool result to avoid massive logs.
            screenshot_available: true,
            interactive_elements: session.interactive_elements.first(15),
            hint: describe_page_state(session)
          },
          "Navigated to #{result[:url]}"
        )
      else
        error_response("Failed to navigate: #{result[:error]}")
      end
    end

    # Best-effort: if we have a persisted cookie jar for this host, apply it before navigating.
    # This allows reusing logged-in sessions across tasks (like a normal browser).
    def apply_persisted_user_cookies_for_url(session, url)
      return unless user&.id

      host = begin
        URI.parse(url.to_s).host
      rescue StandardError
        nil
      end
      return if host.blank?

      jar = Rails.cache.read("user_cookie_jar:#{user.id}:#{host}")
      return unless jar.is_a?(Hash) && jar.any?

      session.apply_cookie_jar("https://#{host}/", jar)
    rescue StandardError => e
      Rails.logger.debug "[ComputerUseTool] Failed to apply persisted user cookies: #{e.message}"
    end

    def handle_click(session, args)
      selector = get_arg(args, :selector)
      return error_response("Missing 'selector' parameter for click action") unless selector

      result = session.click(selector)
      
      if result[:success]
        success_response(
          {
            selector: selector,
            current_url: result[:url],
            page_title: result[:title],
            screenshot_available: true,
            hint: describe_page_state(session)
          },
          "Clicked on '#{selector}'"
        )
      else
        error_response("Failed to click: #{result[:error]}. The element may not exist or be visible.")
      end
    end

    def handle_type(session, args)
      selector = get_arg(args, :selector)
      text = get_arg(args, :text)
      
      return error_response("Missing 'selector' parameter for type action") unless selector
      return error_response("Missing 'text' parameter for type action") unless text

      options = { clear: get_arg(args, :clear_first) == true }
      result = session.type(selector, text, options)
      
      if result[:success]
        success_response(
          {
            selector: selector,
            text_length: text.length,
            screenshot_available: true
          },
          "Typed #{text.length} characters into '#{selector}'"
        )
      else
        error_response("Failed to type: #{result[:error]}. The input field may not exist or be focusable.")
      end
    end

    def handle_press_key(session, args)
      key = get_arg(args, :key)
      return error_response("Missing 'key' parameter for press_key action") unless key

      result = session.press_key(key)
      
      if result[:success]
        success_response(
          {
            key: key,
            current_url: result[:url],
            screenshot_available: true,
            hint: describe_page_state(session)
          },
          "Pressed '#{key}' key"
        )
      else
        error_response("Failed to press key: #{result[:error]}")
      end
    end

    def handle_scroll(session, args)
      direction = (get_arg(args, :direction) || "down").to_sym
      amount = get_arg(args, :amount) || 500
      
      result = session.scroll(direction: direction, amount: amount)
      
      if result[:success]
        success_response(
          {
            direction: direction,
            amount: amount,
            screenshot_available: true
          },
          "Scrolled #{direction} by #{amount}px"
        )
      else
        error_response("Failed to scroll: #{result[:error]}")
      end
    end

    def handle_hover(session, args)
      selector = get_arg(args, :selector)
      return error_response("Missing 'selector' parameter for hover action") unless selector

      result = session.hover(selector)
      
      if result[:success]
        success_response(
          {
            selector: selector,
            screenshot_available: true
          },
          "Hovered over '#{selector}'"
        )
      else
        error_response("Failed to hover: #{result[:error]}")
      end
    end

    def handle_select(session, args)
      selector = get_arg(args, :selector)
      value = get_arg(args, :value)
      
      return error_response("Missing 'selector' parameter for select action") unless selector
      return error_response("Missing 'value' parameter for select action") unless value

      result = session.select_option(selector, value)
      
      if result[:success]
        success_response(
          {
            selector: selector,
            value: value,
            screenshot_available: true
          },
          "Selected '#{value}' in '#{selector}'"
        )
      else
        error_response("Failed to select: #{result[:error]}")
      end
    end

    def handle_wait(session, args)
      wait_seconds = get_arg(args, :wait_seconds)
      selector = get_arg(args, :selector)
      text = get_arg(args, :text)
      
      if wait_seconds
        result = session.wait(seconds: wait_seconds)
        message = "Waited #{wait_seconds} seconds"
      elsif selector
        result = session.wait(selector: selector)
        message = "Element '#{selector}' appeared"
      elsif text
        result = session.wait(text: text)
        message = "Text '#{text}' appeared"
      else
        return error_response("Specify wait_seconds, selector, or text for wait action")
      end
      
      if result[:success]
        success_response({ screenshot_available: true }, message)
      else
        error_response("Wait failed: #{result[:error]}")
      end
    end

    def handle_screenshot(session)
      state = session.page_state
      
      success_response(
        {
          current_url: state[:url],
          page_title: state[:title],
          screenshot_available: true,
          interactive_elements: state[:interactive_elements].first(20),
          hint: describe_page_state(session)
        },
        "Screenshot captured"
      )
    end

    def handle_get_state(session)
      state = session.page_state
      
      success_response(
        {
          current_url: state[:url],
          page_title: state[:title],
          interactive_elements: state[:interactive_elements],
          text_preview: state[:text_preview],
          action_history: session.action_history.last(10),
          screenshot_available: true
        },
        "Browser state retrieved"
      )
    end

    def handle_close(session)
      session.close
      BrowserSessionService.close_session(session.session_id)
      
      success_response({}, "Browser session closed")
    end

    # Sync cookies from the interactive web proxy (web_proxy) into the Ferrum browser session.
    # This enables a "human logs in, agent continues" flow.
    def handle_sync_proxy_session(session, args)
      proxy_session_id =
        get_arg(args, :proxy_session_id) ||
        context[:task_session_id] ||
        context[:session_id]

      return error_response("Missing proxy_session_id (psid)") if proxy_session_id.blank?

      current_url = session.current_page_url
      host = get_arg(args, :proxy_host)

      if host.blank?
        begin
          host = URI.parse(current_url.to_s).host
        rescue StandardError
          host = nil
        end
      end

      return error_response("Missing proxy_host (unable to derive from current_url)") if host.blank?

      cache_key = "web_proxy_cookie_jar:#{proxy_session_id}:#{host}"
      jar = Rails.cache.read(cache_key)

      unless jar.is_a?(Hash) && jar.any?
        return error_response("No proxy cookies found for #{host}. Have you completed login in the interactive web view?")
      end

      # Apply cookies to the current URL's origin (or fallback to https://host)
      target_url = current_url.presence || "https://#{host}/"
      ok = session.apply_cookie_jar(target_url, jar)

      if ok
        success_response(
          {
            proxy_session_id: proxy_session_id,
            proxy_host: host,
            cookie_count: jar.size,
            screenshot_available: true
          },
          "Synced #{jar.size} cookies from interactive session for #{host}"
        )
      else
        error_response("Failed to apply cookies to browser session")
      end
    end

    def describe_page_state(session)
      elements = session.interactive_elements.first(10)
      return "" if elements.empty?

      descriptions = elements.map do |el|
        text = el["text"].presence || el["id"].presence || el["name"].presence || "unnamed"
        "#{el['type']}: '#{text.truncate(30)}'"
      end

      "Visible interactive elements: #{descriptions.join(', ')}"
    end

    def broadcast_browser_state(result, args, browser_session_instance)
      # The ActionCable stream is keyed by the Scout session id. In some execution paths
      # (e.g. tool calls from background agents), `context[:session_id]` may be missing even
      # though we created a browser session with a fallback id. Use the browser session id
      # as a reliable fallback so the canvas still updates.
      session_id = context[:task_session_id] || context[:session_id] || browser_session_instance.session_id
      return unless session_id.present?

      begin
        # Always fetch the most current state from the browser_session_instance
        # This ensures we have accurate URL/title even for actions that don't return them
        current_url = browser_session_instance.current_page_url
        page_title = browser_session_instance.page_title
        interactive_elements = browser_session_instance.interactive_elements.first(15)
        proxy_host = begin
          URI.parse(current_url.to_s).host
        rescue StandardError
          nil
        end

        # Skip login detection if cookies have already been synced from user's interactive session
        # This prevents showing the handoff banner again after the user has already logged in
        login_required = if browser_session_instance.respond_to?(:cookies_synced?) && browser_session_instance.cookies_synced?
          Rails.logger.debug "[ComputerUseTool] Skipping login detection - cookies already synced"
          false
        else
          login_required_signal?(
            current_url: current_url,
            page_title: page_title,
            interactive_elements: interactive_elements
          )
        end

        # Avoid broadcasting giant base64 screenshots (they bloat logs & DOM).
        # Capture raw PNG bytes and store in cache; broadcast only a short URL.
        screenshot_url = nil
        begin
          png_bytes = browser_session_instance.screenshot(format: :png, full_page: false)
          token = SecureRandom.hex(12)
          cache_key = "browser_session_screenshot:#{session_id}:#{token}"
          Rails.cache.write(cache_key, png_bytes, expires_in: 5.minutes)
          screenshot_url = "/scout/browser_session_screenshot/#{session_id}?token=#{token}"
        rescue StandardError => e
          Rails.logger.warn "[ComputerUseTool] Failed to capture/cache screenshot: #{e.message}"
        end

        if login_required
          # When login is required, switch to interactive (proxy-backed) mode immediately.
          # Relying on the browser_session canvas JS to auto-handoff can race with subsequent
          # ActionCable updates and lead to "Scout says to login" but the interactive canvas never appears.
          proxy_url = "/web_proxy?psid=#{CGI.escape(session_id.to_s)}&url=#{CGI.escape(current_url.to_s)}"

          ScoutChannel.broadcast_to(session_id, {
            type: "load_canvas",
            canvas: "web_page_viewer",
            canvas_data: {
              url: current_url,
              title: page_title,
              display_mode: "interactive",
              proxy_url: proxy_url,
              handoff: { session_id: session_id, proxy_host: proxy_host },
              status: "loading",
              message: "Login required — complete sign-in in interactive mode, then click “Continue agent”."
            }
          })
          Rails.logger.info "[ComputerUseTool] Broadcast interactive login handoff for session: #{session_id}. URL: #{current_url&.truncate(80)}"
        else
          # Load the browser_session canvas with the current state
          ScoutChannel.broadcast_to(session_id, {
            type: "load_canvas",
            canvas: "browser_session",
            canvas_data: {
              session_id: session_id,
              url: current_url,
              title: page_title,
              screenshot_url: screenshot_url,
              action: get_arg(args, :action),
              message: result[:message],
              interactive_elements: interactive_elements,
              login_required: login_required,
              proxy_session_id: session_id,
              proxy_host: proxy_host,
              status: "active"
            }
          })
          Rails.logger.info "[ComputerUseTool] Broadcast browser canvas for session: #{session_id}. URL: #{current_url&.truncate(80)}"
        end
      rescue StandardError => e
        Rails.logger.warn "[ComputerUseTool] Failed to broadcast browser state: #{e.message}"
      end
    end

    # Heuristic: if it looks like a login page, hint the UI to use the hybrid flow.
    def login_required_signal?(current_url:, page_title:, interactive_elements:)
      url = current_url.to_s.downcase
      title = page_title.to_s.downcase

      return true if url.match?(/\/(login|log-in|signin|sign-in|auth|session)\b/)
      return true if title.match?(/\b(log\s*in|login|sign\s*in|signin)\b/)

      # Some sites show a "Log in" button on many pages (not just /login).
      # If we see a visible log-in/sign-in control, present the UI hint.
      has_login_cta = interactive_elements.any? do |el|
        h = el.respond_to?(:to_h) ? el.to_h : {}
        text = (h["text"] || h[:text]).to_s.downcase
        type = (h["type"] || h[:type]).to_s.downcase
        text.include?("log in") || text.include?("login") || text.include?("sign in") || text.include?("signin") ||
          type.include?("login") || type.include?("signin") || type.include?("sign-in")
      end
      return true if has_login_cta

      # Many login forms expose an input[type=password]; our interactive element types/selectors
      # often include "password" (e.g. "input[type=password]").
      has_password = interactive_elements.any? do |el|
        h = el.respond_to?(:to_h) ? el.to_h : {}
        h.values.any? { |v| v.to_s.downcase.include?("password") }
      end

      has_password
    end
  end
end
