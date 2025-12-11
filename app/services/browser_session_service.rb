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
      
      if @@sessions[key] && @@sessions[key].alive?
        Rails.logger.info "[BrowserSession] Reusing existing session: #{key}"
        return @@sessions[key]
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

  # Check if browser is still running
  def alive?
    @browser && !@browser.crashed?
  rescue StandardError
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
    
    @page.go_to(url)
    wait_for_page_load
    
    @current_url = @page.current_url
    record_action(:navigate, { url: url })
    
    {
      success: true,
      action: :navigate,
      url: @current_url,
      title: page_title,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:navigate, e)
  end

  # Go back in history
  def go_back
    ensure_browser!
    Rails.logger.info "[BrowserSession] Going back"
    
    @page.back
    wait_for_page_load
    
    @current_url = @page.current_url
    record_action(:go_back, {})
    
    {
      success: true,
      action: :go_back,
      url: @current_url,
      title: page_title,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:go_back, e)
  end

  # Go forward in history
  def go_forward
    ensure_browser!
    Rails.logger.info "[BrowserSession] Going forward"
    
    @page.forward
    wait_for_page_load
    
    @current_url = @page.current_url
    record_action(:go_forward, {})
    
    {
      success: true,
      action: :go_forward,
      url: @current_url,
      title: page_title,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:go_forward, e)
  end

  # Refresh the page
  def refresh
    ensure_browser!
    Rails.logger.info "[BrowserSession] Refreshing page"
    
    @page.refresh
    wait_for_page_load
    
    record_action(:refresh, {})
    
    {
      success: true,
      action: :refresh,
      url: @current_url,
      title: page_title,
      screenshot: screenshot_base64
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
    
    element = find_element(selector)
    raise "Element not found: #{selector}" unless element
    
    # Scroll element into view first
    element.scroll_into_view
    sleep 0.1
    
    # Click the element
    element.click
    
    # Wait for any navigation or dynamic content
    sleep(options[:wait] || 0.5)
    
    @current_url = @page.current_url
    record_action(:click, { selector: selector })
    
    {
      success: true,
      action: :click,
      selector: selector,
      url: @current_url,
      title: page_title,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:click, e, { selector: selector })
  end

  # Type text into an element
  def type(selector, text, options = {})
    ensure_browser!
    Rails.logger.info "[BrowserSession] Typing into: #{selector}"
    
    element = find_element(selector)
    raise "Element not found: #{selector}" unless element
    
    # Focus the element
    element.focus
    
    # Clear existing content if requested
    if options[:clear]
      element.evaluate("this.value = ''")
    end
    
    # Type the text
    element.type(text, delay: options[:delay] || 0.05)
    
    record_action(:type, { selector: selector, text: text.truncate(50) })
    
    {
      success: true,
      action: :type,
      selector: selector,
      text_length: text.length,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:type, e, { selector: selector })
  end

  # Press a key (Enter, Tab, Escape, etc.)
  def press_key(key)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Pressing key: #{key}"
    
    @page.keyboard.type([], key.to_sym)
    sleep 0.3
    
    @current_url = @page.current_url
    record_action(:press_key, { key: key })
    
    {
      success: true,
      action: :press_key,
      key: key,
      url: @current_url,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:press_key, e, { key: key })
  end

  # Hover over an element
  def hover(selector)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Hovering over: #{selector}"
    
    element = find_element(selector)
    raise "Element not found: #{selector}" unless element
    
    element.scroll_into_view
    element.hover
    sleep 0.3
    
    record_action(:hover, { selector: selector })
    
    {
      success: true,
      action: :hover,
      selector: selector,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:hover, e, { selector: selector })
  end

  # Select an option from a dropdown
  def select_option(selector, value)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Selecting '#{value}' in: #{selector}"
    
    element = find_element(selector)
    raise "Element not found: #{selector}" unless element
    
    element.select(value)
    
    record_action(:select_option, { selector: selector, value: value })
    
    {
      success: true,
      action: :select_option,
      selector: selector,
      value: value,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:select_option, e, { selector: selector, value: value })
  end

  # Scroll the page
  def scroll(direction: :down, amount: 500)
    ensure_browser!
    Rails.logger.info "[BrowserSession] Scrolling #{direction} by #{amount}px"
    
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
    
    sleep 0.3
    record_action(:scroll, { direction: direction, amount: amount })
    
    {
      success: true,
      action: :scroll,
      direction: direction,
      amount: amount,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:scroll, e, { direction: direction })
  end

  # Wait for a condition or time
  def wait(seconds: nil, selector: nil, text: nil)
    ensure_browser!
    
    if seconds
      Rails.logger.info "[BrowserSession] Waiting #{seconds} seconds"
      sleep seconds
    elsif selector
      Rails.logger.info "[BrowserSession] Waiting for selector: #{selector}"
      wait_for_selector(selector)
    elsif text
      Rails.logger.info "[BrowserSession] Waiting for text: #{text}"
      wait_for_text(text)
    end
    
    record_action(:wait, { seconds: seconds, selector: selector, text: text })
    
    {
      success: true,
      action: :wait,
      screenshot: screenshot_base64
    }
  rescue StandardError => e
    handle_error(:wait, e)
  end

  # ============================================
  # Page State Methods
  # ============================================

  # Take a screenshot
  def screenshot(format: :png, full_page: false)
    ensure_browser!
    
    options = { format: format.to_s }
    options[:full] = true if full_page
    
    @page.screenshot(**options)
  end

  # Get screenshot as base64
  def screenshot_base64(full_page: false)
    data = screenshot(full_page: full_page)
    Base64.strict_encode64(data)
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
            
            elements.push({
              index: index,
              type: type,
              text: text,
              id: el.id || null,
              name: el.name || null,
              className: el.className ? el.className.split(' ').slice(0, 3).join(' ') : null,
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

    Rails.logger.info "[BrowserSession] Starting browser for session: #{session_id}"
    @browser = create_browser
    @page = @browser.create_page
  end

  def create_browser
    browser_options = {
      headless: "new",  # Use new headless mode
      timeout: config.timeout,
      window_size: [config.viewport_width, config.viewport_height],
      browser_options: {
        "no-sandbox": true,
        "disable-gpu": true,
        "disable-dev-shm-usage": true,
        "disable-setuid-sandbox": true,
        "user-agent": config.user_agent
      }
    }

    if ENV["CHROME_PATH"].present?
      browser_options[:browser_path] = ENV["CHROME_PATH"]
    end

    Ferrum::Browser.new(**browser_options)
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
    sleep 1
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
      screenshot: (screenshot_base64 rescue nil)
    }
  end
end
