# frozen_string_literal: true

# WebPageCaptureService
# Captures screenshots and extracts text from web pages using headless Chrome (Ferrum)
#
# Usage:
#   service = WebPageCaptureService.new(url: "https://example.com")
#   result = service.capture
#   # => { success: true, screenshot_url: "https://...", text_content: "...", title: "..." }
#
class WebPageCaptureService
  include ActiveSupport::Configurable

  # Configuration defaults
  config_accessor :viewport_width, default: 1280
  config_accessor :viewport_height, default: 800
  config_accessor :full_page_screenshot, default: true
  config_accessor :timeout, default: 30 # seconds
  config_accessor :user_agent, default: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  attr_reader :url, :entity_id, :options

  def initialize(url:, entity_id: nil, **options)
    @url = normalize_url(url)
    @entity_id = entity_id
    @options = options
  end

  # Main capture method - returns hash with screenshot URL and extracted text
  def capture
    Rails.logger.info "[WebPageCapture] Starting capture for: #{url}"

    validate_url!

    browser = nil
    begin
      browser = create_browser
      page = browser.create_page

      # Navigate to page
      Rails.logger.info "[WebPageCapture] Navigating to #{url}"
      page.go_to(url)

      # Wait for page to load
      wait_for_page_load(page)

      # Extract page info
      title = extract_title(page)
      text_content = extract_text(page)
      meta_description = extract_meta_description(page)

      # Take screenshot
      screenshot_data = take_screenshot(page)

      # Upload to S3
      screenshot_url = upload_screenshot(screenshot_data)

      Rails.logger.info "[WebPageCapture] Capture complete for: #{url}"

      {
        success: true,
        url: url,
        title: title,
        meta_description: meta_description,
        text_content: text_content.truncate(10_000), # Limit text for context window
        screenshot_url: screenshot_url,
        captured_at: Time.current.iso8601
      }
    rescue Ferrum::TimeoutError => e
      Rails.logger.error "[WebPageCapture] Timeout loading #{url}: #{e.message}"
      {
        success: false,
        url: url,
        error: "Page took too long to load",
        error_type: "timeout"
      }
    rescue Ferrum::StatusError => e
      Rails.logger.error "[WebPageCapture] HTTP error for #{url}: #{e.message}"
      {
        success: false,
        url: url,
        error: "Failed to load page (HTTP error)",
        error_type: "http_error"
      }
    rescue StandardError => e
      Rails.logger.error "[WebPageCapture] Error capturing #{url}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      {
        success: false,
        url: url,
        error: e.message,
        error_type: "capture_error"
      }
    ensure
      browser&.quit
    end
  end

  # Check if a URL can potentially be embedded in an iframe
  # This is a heuristic - actual embedding depends on X-Frame-Options/CSP headers
  def self.likely_embeddable?(url)
    # Known sites that typically block embedding
    blocked_domains = %w[
      google.com youtube.com facebook.com twitter.com x.com instagram.com
      linkedin.com github.com reddit.com amazon.com apple.com microsoft.com
      netflix.com spotify.com dropbox.com slack.com notion.so figma.com
    ]

    uri = URI.parse(url)
    host = uri.host&.downcase || ""

    # Check if domain matches any blocked pattern
    !blocked_domains.any? { |domain| host.include?(domain) }
  rescue URI::InvalidURIError
    false
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

  def validate_url!
    uri = URI.parse(url)
    raise ArgumentError, "Invalid URL scheme" unless %w[http https].include?(uri.scheme)
    raise ArgumentError, "Missing host" if uri.host.blank?

    # Block local/private IPs for security
    if private_ip?(uri.host)
      raise ArgumentError, "Cannot capture private/local addresses"
    end
  rescue URI::InvalidURIError => e
    raise ArgumentError, "Invalid URL: #{e.message}"
  end

  def private_ip?(host)
    return true if host == "localhost" || host == "127.0.0.1"
    return true if host.match?(/\A10\.\d+\.\d+\.\d+\z/)
    return true if host.match?(/\A172\.(1[6-9]|2\d|3[01])\.\d+\.\d+\z/)
    return true if host.match?(/\A192\.168\.\d+\.\d+\z/)
    false
  end

  def create_browser
    browser_options = {
      headless: true,
      timeout: config.timeout,
      window_size: [ config.viewport_width, config.viewport_height ],
      browser_options: {
        "no-sandbox": true,
        "disable-gpu": true,
        "disable-dev-shm-usage": true,
        "disable-setuid-sandbox": true
      }
    }

    # Add custom user agent
    browser_options[:browser_options]["user-agent"] = config.user_agent

    # Use custom Chrome path if set in environment
    if ENV["CHROME_PATH"].present?
      browser_options[:browser_path] = ENV["CHROME_PATH"]
    end

    Ferrum::Browser.new(**browser_options)
  end

  def wait_for_page_load(page)
    # Wait for network to be idle (no requests for 500ms)
    page.network.wait_for_idle(timeout: config.timeout)
  rescue Ferrum::TimeoutError
    # If network doesn't idle, just wait a bit and continue
    Rails.logger.warn "[WebPageCapture] Network didn't idle, continuing anyway"
    sleep 2
  end

  def extract_title(page)
    page.evaluate("document.title") || "Untitled"
  rescue StandardError => e
    Rails.logger.warn "[WebPageCapture] Failed to extract title: #{e.message}"
    "Untitled"
  end

  def extract_meta_description(page)
    page.evaluate(<<~JS)
      (function() {
        var meta = document.querySelector('meta[name="description"]');
        return meta ? meta.getAttribute('content') : null;
      })()
    JS
  rescue StandardError => e
    Rails.logger.warn "[WebPageCapture] Failed to extract meta description: #{e.message}"
    nil
  end

  def extract_text(page)
    # Extract visible text content, excluding scripts, styles, etc.
    page.evaluate(<<~JS)
      (function() {
        // Clone the body to avoid modifying the actual page
        var clone = document.body.cloneNode(true);

        // Remove unwanted elements
        var removeSelectors = ['script', 'style', 'noscript', 'iframe', 'svg', 'nav', 'footer', 'header'];
        removeSelectors.forEach(function(selector) {
          var elements = clone.querySelectorAll(selector);
          elements.forEach(function(el) { el.remove(); });
        });

        // Get text content and clean it up
        var text = clone.innerText || clone.textContent || '';

        // Clean up whitespace
        text = text.replace(/\\s+/g, ' ').trim();

        // Remove very long repeated characters (common in minified content)
        text = text.replace(/(.)\\1{20,}/g, '$1$1$1');

        return text;
      })()
    JS
  rescue StandardError => e
    Rails.logger.warn "[WebPageCapture] Failed to extract text: #{e.message}"
    ""
  end

  def take_screenshot(page)
    screenshot_options = {
      format: "png",
      quality: 80
    }

    if config.full_page_screenshot
      screenshot_options[:full] = true
    end

    page.screenshot(**screenshot_options)
  end

  def upload_screenshot(screenshot_data)
    filename = generate_filename
    content_type = "image/png"

    if defined?(ActiveStorage) && ActiveStorage::Blob.respond_to?(:create_and_upload!)
      # Use ActiveStorage
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(screenshot_data),
        filename: filename,
        content_type: content_type
      )

      # Generate a URL - use rails_blob_url if available, otherwise construct manually
      if Rails.application.routes.url_helpers.respond_to?(:rails_blob_url)
        Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: false, host: default_url_host)
      else
        Rails.application.routes.url_helpers.url_for(blob)
      end
    else
      # Fall back to direct S3 upload
      upload_to_s3(screenshot_data, filename, content_type)
    end
  rescue StandardError => e
    Rails.logger.error "[WebPageCapture] Failed to upload screenshot: #{e.message}"
    # Return a data URL as fallback (not ideal but works)
    "data:image/png;base64,#{Base64.strict_encode64(screenshot_data)}"
  end

  def upload_to_s3(data, filename, content_type)
    s3_client = Aws::S3::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
    )

    bucket_name = ENV["AWS_S3_BUCKET"] || "agent-marketing-rag-storage"
    key = "web_captures/#{filename}"

    s3_client.put_object(
      bucket: bucket_name,
      key: key,
      body: StringIO.new(data),
      content_type: content_type,
      acl: "public-read"
    )

    "https://#{bucket_name}.s3.amazonaws.com/#{key}"
  end

  def generate_filename
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    url_hash = Digest::MD5.hexdigest(url)[0..7]
    entity_prefix = entity_id ? "entity_#{entity_id}_" : ""
    "#{entity_prefix}webpage_#{url_hash}_#{timestamp}.png"
  end

  def default_url_host
    ENV["APP_HOST"] || ENV["RAILS_HOST"] || "localhost:3000"
  end
end
