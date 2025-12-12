# frozen_string_literal: true

# BrowserSessionService
# Manages persistent headless browser sessions for computer use agent
# Provides action methods: click, type, scroll, hover, select, wait
#
# Usage:
#   session = BrowserSessionService.new(user_id: 1, session_id: "abc123")
#   session.navigate("https://example.com")
#   session.click("button.submit")
#   session.type("input[name='email']", "user@example.com")
#   screenshot = session.screenshot
#   session.close
#
class BrowserSessionService
  include ActiveSupport::Configurable

  # Configuration
  config_accessor :viewport_width, default: 1280
  config_accessor :viewport_height, default: 800
  config_accessor :timeout, default: 30
  config_accessor :user_agent, default: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  # Session storage (in-memory for now, could be Redis later)
  @@sessions = {}
  @@session_mutex = Mutex.new

  attr_reader :user_id, :session_id, :current_url, :last_action, :action_history

  def initialize(user_id:, session_id: nil)
    @user_id = user_id
    @session_id = session_id || SecureRandom.uuid
    @browser = nil
    @page = nil
    @current_url = nil
    @last_action = nil
    @action_history = []
    @created_at = Time.current
  end

  # Get or create a session for a user
  def self.find_or_create(user_id:, session_id: nil)
    @@session_mutex.synchronize do
      key = session_id || "user_#{user_id}_default"
      
      existing_session = @@sessions[key]

      if existing_session && existing_session.alive?
        Rails.logger.info "[BrowserSession] Reusing existing session: #{key}"
        return existing_session
      elsif existing_session && !existing_session.alive?
        # Clean up dead session before creating a new one
        Rails.logger.warn "[BrowserSession] Found dead session '#{key}', closing it before creating new one."
        existing_session.close rescue nil
        @@sessions.delete(key)
      end

      Rails.logger.info "[BrowserSession] Creating new session: #{key}"
      session = new(user_id: user_id, session_id: session_id)
      @@sessions[key] = session
      session
    end
  end

  # Close a specific session
  def self.close_session(session_id)
    @@session_mutex.synchronize do
      if @@sessions[session_id]
        @@sessions[session_id].close
        @@sessions.delete(session_id)
      end
    end
  end

  # Close all sessions for a user
  def self.close_user_sessions(user_id)
    @@session_mutex.synchronize do
      @@sessions.each do |key, session|
        if session.user_id == user_id
          session.close
          @@sessions.delete(key)
        end
      end
    end
  end

  # Clean up stale sessions (older than 30 minutes)
  def self.cleanup_stale_sessions(max_age: 30.minutes)
    @@session_mutex.synchronize do
      cutoff = Time.current - max_age
      @@sessions.each do |key, session|
        if session.instance_variable_get(:@created_at) < cutoff
          Rails.logger.info "[BrowserSession] Cleaning up stale session: #{key}"
          session.close rescue nil
          @@sessions.delete(key)
        end
      end
    end
  end

  # Check if browser is still running - more robust check
  def alive?
    return false unless @browser

    # Ferrum versions differ: some don't implement `crashed?` on Browser.
    if @browser.respond_to?(:crashed?) && @browser.crashed?
      return false
    end

    # If Ferrum exposes a process handle, use it as an additional signal.
    if @browser.respond_to?(:process) && (proc = @browser.process)
      if proc.respond_to?(:alive?) && !proc.alive?
        return false
      end
    end

    # Try to actually ping the browser/page to verify it's responsive.
    @page&.current_url if @page
    true
  rescue Ferrum::DeadBrowserError, Ferrum::BrowserError, Ferrum::TimeoutError, StandardError => e
    Rails.logger.warn "[BrowserSession] Browser health check failed: #{e.class.name} - #{e.message}"
    false
  end

  # ============================================
  # Navigation Actions
  # ============================================

  # Navigate to a URL
  def navigate(url)
    ensure_browser!
    
    url = normalize_url(url)
    Rails.logger.info "[BrowserSession] Navigating to: #{url}"

    with_browser_recovery do
      @page.go_to(url)
      wait_for_page_load
    end
    
    @current_url = @page.current_url
    record_action(:navigate, { url: url })
    log_page_diagnostics("navigate")
    
    {
      success: true,
      action: :navigate,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:navigate, e)
  end

  # Go back in history
  def go_back
    ensure_browser!
    Rails.logger.info "[BrowserSession] Going back"

    with_browser_recovery do
      @page.back
      wait_for_page_load
    end
    
    @current_url = @page.current_url
    record_action(:go_back, {})
    log_page_diagnostics("go_back")
    
    {
      success: true,
      action: :go_back,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:go_back, e)
  end

  # Go forward in history
  def go_forward
    ensure_browser!
    Rails.logger.info "[BrowserSession] Going forward"

    with_browser_recovery do
      @page.forward
      wait_for_page_load
    end
    
    @current_url = @page.current_url
    record_action(:go_forward, {})
    log_page_diagnostics("go_forward")
    
    {
      success: true,
      action: :go_forward,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:go_forward, e)
  end

  # Refresh the page
  def refresh
    ensure_browser!
    Rails.logger.info "[BrowserSession] Refreshing page"

    with_browser_recovery do
      @page.refresh
      wait_for_page_load
    end
    
    record_action(:refresh, {})
    log_page_diagnostics("refresh")
    
    {
      success: true,
      action: :refresh,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:refresh, e)
  end

  # ============================================
  # Interaction Actions
  # ============================================

  # Click on an element
  def click(selector, options = {})
    ensure_browser!
    Rails.logger.info "[BrowserSession] Clicking: #{selector}"

    with_browser_recovery do
      element = find_element(selector)
      raise "Element not found: #{selector}" unless element
      
      # Scroll element into view first
      element.scroll_into_view
      sleep 0.1
      
      # Click the element
      element.click
    end
    
    # Wait for any navigation or dynamic content
    sleep(options[:wait] || 0.5)
    
    @current_url = @page.current_url
    record_action(:click, { selector: selector })
    log_page_diagnostics("click")
    
    {
      success: true,
      action: :click,
      selector: selector,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:click, e, { selector: selector })
  end

  # Type text into an element
  def type(selector, text, options = {})
    ensure_browser!
    Rails.logger.info "[BrowserSession] Typing into: #{selector}"
    
    with_browser_recovery do
      element = find_element(selector)
      raise "Element not found: #{selector}" unless element
      
      # Focus the element (some sites require click for real focus)
      begin
        element.focus
      rescue StandardError
        # ignore
      end

      begin
        element.click
      rescue StandardError
        # ignore
      end

      text = text.to_s
      delay = options[:delay].to_f if options[:delay]

      # Clear existing content if requested
      if options[:clear]
        begin
          # Clear common form fields via JS when possible
          element.evaluate(<<~JS)
            (function(el){
              if (!el) return;
              if ('value' in el) el.value = '';
              if (el.isContentEditable) el.innerText = '';
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            })(this)
          JS
        rescue StandardError
          # ignore
        end

        # Also try select-all + backspace (more realistic, works on many controlled inputs)
        begin
          # Prefer Control on Linux containers; fall back to Meta for macOS.
          modifier = :Control
          @page.keyboard.down(modifier)
          @page.keyboard.type("a")
          @page.keyboard.up(modifier)
          @page.keyboard.type(:Backspace)
        rescue StandardError
          begin
            modifier = :Meta
            @page.keyboard.down(modifier)
            @page.keyboard.type("a")
            @page.keyboard.up(modifier)
            @page.keyboard.type(:Backspace)
          rescue StandardError
            # ignore
          end
        end
      end

      # Ferrum 0.17 doesn't support Node#type options like `delay:`
      if delay && delay.positive?
        text.each_char do |ch|
          @page.keyboard.type(ch)
          sleep(delay)
        end
      else
        @page.keyboard.type(text)
      end
    end
    
    @current_url = @page.current_url rescue @current_url
    record_action(:type, { selector: selector, text: text.truncate(50) })
    
    {
      success: true,
      action: :type,
      selector: selector,
      text_length: text.length,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:type, e, { selector: selector })
  end

  # Press a key (Enter, Tab, Escape, etc.)
  def press_key(key)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Pressing key: #{key}"

    with_browser_recovery do
      k = key.to_s
      key_sym =
        case k.downcase
        when "enter", "return" then :Enter
        when "tab" then :Tab
        when "escape", "esc" then :Escape
        when "backspace" then :Backspace
        when "delete", "del" then :Delete
        when "arrowup" then :ArrowUp
        when "arrowdown" then :ArrowDown
        when "arrowleft" then :ArrowLeft
        when "arrowright" then :ArrowRight
        else
          nil
        end

      if key_sym
        @page.keyboard.type(key_sym)
      else
        # If it's a single character or text, type it directly.
        @page.keyboard.type(k)
      end
      sleep 0.3
    end
    
    @current_url = @page.current_url
    record_action(:press_key, { key: key })
    log_page_diagnostics("press_key")
    
    {
      success: true,
      action: :press_key,
      key: key,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:press_key, e, { key: key })
  end

  # Hover over an element
  def hover(selector)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Hovering over: #{selector}"
    
    with_browser_recovery do
      element = find_element(selector)
      raise "Element not found: #{selector}" unless element
      
      element.scroll_into_view
      element.hover
    end
    
    sleep 0.3
    @current_url = @page.current_url rescue @current_url
    record_action(:hover, { selector: selector })
    
    {
      success: true,
      action: :hover,
      selector: selector,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:hover, e, { selector: selector })
  end

  # Select an option from a dropdown
  def select_option(selector, value)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Selecting '#{value}' in: #{selector}"
    
    with_browser_recovery do
      element = find_element(selector)
      raise "Element not found: #{selector}" unless element
      
      element.select(value)
    end
    
    @current_url = @page.current_url rescue @current_url
    record_action(:select_option, { selector: selector, value: value })
    
    {
      success: true,
      action: :select_option,
      selector: selector,
      value: value,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:select_option, e, { selector: selector, value: value })
  end

  # Scroll the page
  def scroll(direction: :down, amount: 500)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Scrolling #{direction} by #{amount}px"
    
    with_browser_recovery do
      case direction.to_sym
      when :down
        @page.execute("window.scrollBy(0, #{amount})")
      when :up
        @page.execute("window.scrollBy(0, -#{amount})")
      when :left
        @page.execute("window.scrollBy(-#{amount}, 0)")
      when :right
        @page.execute("window.scrollBy(#{amount}, 0)")
      when :top
        @page.execute("window.scrollTo(0, 0)")
      when :bottom
        @page.execute("window.scrollTo(0, document.body.scrollHeight)")
      end
    end
    
    sleep 0.3
    @current_url = @page.current_url rescue @current_url
    record_action(:scroll, { direction: direction, amount: amount })
    
    {
      success: true,
      action: :scroll,
      direction: direction,
      amount: amount,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:scroll, e, { direction: direction })
  end

  # Wait for a condition or time - keeps browser alive during wait
  def wait(seconds: nil, selector: nil, text: nil)
    ensure_browser!
    
    if seconds
      Rails.logger.info "[BrowserSession] Waiting #{seconds} seconds (with keepalive)"
      wait_with_keepalive(seconds.to_f)
    elsif selector
      Rails.logger.info "[BrowserSession] Waiting for selector: #{selector}"
      wait_for_selector(selector)
    elsif text
      Rails.logger.info "[BrowserSession] Waiting for text: #{text}"
      wait_for_text(text)
    end
    
    # Update current URL after wait (page may have changed)
    @current_url = @page.current_url rescue @current_url
    
    record_action(:wait, { seconds: seconds, selector: selector, text: text })
    
    {
      success: true,
      action: :wait,
      url: @current_url,
      title: page_title
    }
  rescue StandardError => e
    handle_error(:wait, e)
  end

  # ============================================
  # Page State Methods
  # ============================================

  # Take a screenshot with retry logic
  def screenshot(format: :png, full_page: false)
    retries = 0
    max_retries = 2
    
    begin
      ensure_browser!
      
      options = { format: format.to_s }
      options[:full] = true if full_page
      
      @page.screenshot(**options)
    rescue Ferrum::DeadBrowserError, Ferrum::BrowserError, Ferrum::TimeoutError => e
      retries += 1
      if retries <= max_retries
        Rails.logger.warn "[BrowserSession] Screenshot failed (attempt #{retries}): #{e.message}. Retrying..."
        @browser = nil # Force browser restart
        ensure_browser!
        retry
      else
        Rails.logger.error "[BrowserSession] Screenshot failed after #{max_retries} retries"
        raise
      end
    end
  end

  # Get screenshot as base64
  def screenshot_base64(full_page: false)
    data = screenshot(full_page: full_page)
    Base64.strict_encode64(data)
  rescue StandardError => e
    Rails.logger.error "[BrowserSession] Failed to capture screenshot: #{e.message}"
    # Return a minimal valid PNG (1x1 transparent pixel) as fallback
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  end

  # Get screenshot as data URL
  def screenshot_data_url(full_page: false)
    "data:image/png;base64,#{screenshot_base64(full_page: full_page)}"
  end

  # Get page title
  def page_title
    @page&.evaluate("document.title") || "Unknown"
  rescue StandardError
    "Unknown"
  end

  # Get current URL
  def current_page_url
    @page&.current_url || @current_url
  rescue StandardError
    @current_url
  end

  # Get visible text content
  def page_text
    @page.evaluate(<<~JS)
      (function() {
        var clone = document.body.cloneNode(true);
        ['script', 'style', 'noscript', 'iframe', 'svg'].forEach(function(tag) {
          clone.querySelectorAll(tag).forEach(function(el) { el.remove(); });
        });
        return clone.innerText.replace(/\\s+/g, ' ').trim().substring(0, 10000);
      })()
    JS
  rescue StandardError => e
    Rails.logger.warn "[BrowserSession] Failed to extract text: #{e.message}"
    ""
  end

  # Get interactive elements on the page (for AI to understand what's clickable)
  def interactive_elements
    @page.evaluate(<<~JS)
      (function() {
        var elements = [];
        var selectors = 'a, button, input, select, textarea, [onclick], [role="button"], [role="link"]';
        
        document.querySelectorAll(selectors).forEach(function(el, index) {
          var rect = el.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            var text = (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || '').trim().substring(0, 100);
            var type = el.tagName.toLowerCase();
            if (el.type) type += '[type=' + el.type + ']';
            
            var className = null;
            try {
              if (typeof el.className === 'string') {
                className = el.className;
              } else if (el.className && typeof el.className.baseVal === 'string') {
                // SVGAnimatedString
                className = el.className.baseVal;
              } else if (el.getAttribute) {
                className = el.getAttribute('class') || '';
              }
            } catch (e) {
              className = '';
            }

            var classSnippet = null;
            if (className && typeof className === 'string') {
              classSnippet = className.split(' ').slice(0, 3).join(' ');
            }

            elements.push({
              index: index,
              type: type,
              text: text,
              id: el.id || null,
              name: el.name || null,
              className: classSnippet,
              href: el.href || null,
              x: Math.round(rect.x),
              y: Math.round(rect.y),
              width: Math.round(rect.width),
              height: Math.round(rect.height)
            });
          }
        });
        
        return elements.slice(0, 100); // Limit to first 100 elements
      })()
    JS
  rescue StandardError => e
    Rails.logger.warn "[BrowserSession] Failed to get interactive elements: #{e.message}"
    []
  end

  # Get page state summary (for AI context)
  def page_state
    {
      url: current_page_url,
      title: page_title,
      interactive_elements: interactive_elements,
      text_preview: page_text.truncate(2000)
    }
  end

  # Close the browser session
  def close
    Rails.logger.info "[BrowserSession] Closing session: #{session_id}"
    @browser&.quit
    @browser = nil
    @page = nil
  rescue StandardError => e
    Rails.logger.warn "[BrowserSession] Error closing browser: #{e.message}"
  end

  private

  def ensure_browser!
    return if alive?

    # Preserve the last known URL before creating new browser
    last_known_url = @current_url
    was_browser_restart = @browser.present?

    # Log a warning if we had a browser that died unexpectedly
    if was_browser_restart
      Rails.logger.warn "[BrowserSession] Browser not alive for session: #{session_id}. Re-initializing browser instance."
    end

    Rails.logger.info "[BrowserSession] Starting browser for session: #{session_id}"
    @browser = create_browser
    @page = @browser.create_page
    
    # Apply stealth mode to the new page
    apply_page_stealth(@page)

    # Try to restore the last URL if browser was restarted unexpectedly
    if was_browser_restart && last_known_url.present? && last_known_url != "about:blank"
      Rails.logger.info "[BrowserSession] Restoring previous URL: #{last_known_url.truncate(100)}"
      begin
        @page.go_to(last_known_url)
        wait_for_page_load
        @current_url = @page.current_url
      rescue StandardError => e
        Rails.logger.warn "[BrowserSession] Failed to restore URL: #{e.message}"
        @current_url = @page.current_url
      end
    else
      @current_url = @page.current_url
    end
  end
  
  # Apply stealth settings to a page to avoid bot detection
  def apply_page_stealth(page)
    return unless page
    
    page.evaluate(<<~JS)
      // Hide webdriver property
      Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
      
      // Add realistic plugins
      Object.defineProperty(navigator, 'plugins', {
        get: () => [
          { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
          { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
          { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' }
        ]
      });
      
      // Set realistic languages
      Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
      
      // Override permissions query
      const originalQuery = window.navigator.permissions.query;
      window.navigator.permissions.query = (parameters) => (
        parameters.name === 'notifications' ?
          Promise.resolve({ state: Notification.permission }) :
          originalQuery(parameters)
      );
    JS
  rescue StandardError => e
    Rails.logger.debug "[BrowserSession] Failed to apply page stealth: #{e.message}"
  end

  def create_browser
    # Use a realistic user agent that matches a real Chrome browser
    realistic_user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    browser_options = {
      # "new" headless has been flaky in containerized environments; classic headless is more stable.
      headless: true,
      timeout: config.timeout,
      window_size: [config.viewport_width, config.viewport_height],
      process_timeout: 60,
      browser_options: {
        "no-sandbox": true,
        "disable-gpu": true,
        "disable-dev-shm-usage": true,
        "disable-setuid-sandbox": true,
        "disable-blink-features": "AutomationControlled",
        "disable-infobars": true,
        "disable-background-timer-throttling": true,
        "disable-backgrounding-occluded-windows": true,
        "disable-renderer-backgrounding": true,
        # Site isolation can trigger extra processes / memory in Docker.
        "disable-site-isolation-trials": true,
        "disable-features": "TranslateUI,site-per-process",
        "hide-scrollbars": true,
        "mute-audio": true,
        "no-first-run": true,
        "user-agent": realistic_user_agent
      }
    }

    if ENV["CHROME_PATH"].present?
      browser_options[:browser_path] = ENV["CHROME_PATH"]
    end

    Ferrum::Browser.new(**browser_options)
  end

  # Apply stealth settings to avoid bot detection
  def apply_stealth_mode(browser)
    page = browser.create_page
    
    # Override navigator.webdriver to return undefined
    page.evaluate(<<~JS)
      Object.defineProperty(navigator, 'webdriver', {
        get: () => undefined
      });
    JS
    
    # Override navigator.plugins to look like a real browser
    page.evaluate(<<~JS)
      Object.defineProperty(navigator, 'plugins', {
        get: () => [
          { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
          { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
          { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' }
        ]
      });
    JS
    
    # Override navigator.languages
    page.evaluate(<<~JS)
      Object.defineProperty(navigator, 'languages', {
        get: () => ['en-US', 'en']
      });
    JS
    
    # Remove automation-related properties from window
    page.evaluate(<<~JS)
      delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
      delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise;
      delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol;
    JS
    
    page.close
  rescue StandardError => e
    Rails.logger.warn "[BrowserSession] Failed to apply stealth mode: #{e.message}"
  end

  def find_element(selector)
    # Try CSS selector first
    element = @page.at_css(selector)
    return element if element

    # Try XPath if CSS fails
    if selector.start_with?("//") || selector.start_with?("(//")
      element = @page.at_xpath(selector)
      return element if element
    end

    # Try finding by text content
    if selector.start_with?("text=")
      text = selector.sub("text=", "")
      element = @page.at_xpath("//*[contains(text(), '#{text}')]")
      return element if element
    end

    nil
  end

  def wait_for_page_load
    @page.network.wait_for_idle(timeout: 10)
  rescue Ferrum::TimeoutError
    Rails.logger.warn "[BrowserSession] Network didn't idle, continuing"
    sleep 0.5
  end

  # Lightweight diagnostics to distinguish "blank shell / bot challenge" vs actual browser crash.
  def page_diagnostics
    return {} unless @page

    {
      url: (@page.current_url rescue nil),
      title: (page_title rescue nil),
      ready_state: (@page.evaluate("document.readyState") rescue nil),
      html_length: (@page.evaluate("document.documentElement ? document.documentElement.outerHTML.length : 0") rescue nil),
      body_text_length: (@page.evaluate("document.body ? document.body.innerText.length : 0") rescue nil)
    }
  rescue StandardError => e
    { error: "#{e.class.name}: #{e.message}" }
  end

  def log_page_diagnostics(context_label)
    diag = page_diagnostics
    return if diag.blank?

    Rails.logger.info(
      "[BrowserSession] Diagnostics(#{context_label}) url=#{diag[:url].to_s.truncate(120)} " \
      "title=#{diag[:title].to_s.truncate(80)} ready=#{diag[:ready_state]} " \
      "html_len=#{diag[:html_length]} text_len=#{diag[:body_text_length]}"
    )
  rescue StandardError
    # never fail an action due to diagnostics
  end

  # Wait with keepalive - periodically check browser health
  def wait_with_keepalive(total_seconds)
    return if total_seconds <= 0
    
    interval = 1.0 # Check browser health every 1 second (less intrusive)
    elapsed = 0.0
    
    while elapsed < total_seconds
      sleep_time = [interval, total_seconds - elapsed].min
      sleep(sleep_time)
      elapsed += sleep_time
      
      # Check browser health using a non-intrusive method (just check if page exists)
      begin
        # Just access current_url to verify the connection is alive
        # This is less likely to trigger bot detection than evaluate()
        @page.current_url if @page
      rescue Ferrum::DeadBrowserError, Ferrum::BrowserError => e
        Rails.logger.warn "[BrowserSession] Browser died during wait at #{elapsed}s: #{e.message}"
        ensure_browser! # This will restart and restore URL
        break # Exit the wait loop after recovery
      rescue StandardError => e
        Rails.logger.debug "[BrowserSession] Keepalive check error (non-fatal): #{e.message}"
      end
    end
  end

  def wait_for_selector(selector, timeout: 10)
    start_time = Time.current
    while Time.current - start_time < timeout
      return true if find_element(selector)
      sleep 0.2
    end
    raise "Timeout waiting for selector: #{selector}"
  end

  def wait_for_text(text, timeout: 10)
    start_time = Time.current
    while Time.current - start_time < timeout
      return true if page_text.include?(text)
      sleep 0.2
    end
    raise "Timeout waiting for text: #{text}"
  end

  def normalize_url(url)
    url = url.to_s.strip
    url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
    url
  end

  def record_action(action_type, details)
    @last_action = {
      action: action_type,
      details: details,
      timestamp: Time.current.iso8601,
      url: @current_url
    }
    @action_history << @last_action
    @action_history = @action_history.last(50) # Keep last 50 actions
  end

  def handle_error(action, error, details = {})
    Rails.logger.error "[BrowserSession] Error in #{action}: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")
    
    {
      success: false,
      action: action,
      error: error.message,
      error_type: error.class.name,
      details: details,
      url: @current_url,
      title: page_title
    }
  end

  # Execute a block with browser recovery - retries on browser death
  def with_browser_recovery(max_retries: 2)
    retries = 0
    begin
      yield
    rescue Ferrum::DeadBrowserError, Ferrum::BrowserError => e
      retries += 1
      if retries <= max_retries
        Rails.logger.warn "[BrowserSession] Browser error (attempt #{retries}): #{e.message}. Recovering..."
        @browser = nil # Force full browser restart
        ensure_browser!
        retry
      else
        raise
      end
    end
  end
end
