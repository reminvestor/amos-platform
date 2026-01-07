# frozen_string_literal: true

module Tools
  # ReadViewedPageTool
  # Allows Amos to see/read the content of the page the user is currently viewing
  # in the interactive browser session. This enables Amos to understand context
  # and help with what the user is looking at.
  #
  class ReadViewedPageTool < BaseTool
    tool_name "read_viewed_page"
    description "Read the content of the web page the user is currently viewing in the interactive browser. " \
                "Use this when the user asks about something on the page they're looking at, or when you need " \
                "to understand what they're seeing. Returns the page's text content, headings, links, and forms."

    parameter :detail_level, type: "string", required: false,
              description: "Level of detail to extract: 'summary' (headings and key text), " \
                           "'full' (all readable text), or 'structured' (headings, links, forms). " \
                           "Default: 'summary'"

    def execute
      detail_level = arguments["detail_level"] || "summary"
      
      # Get the current proxy session URL
      current_url = get_current_viewed_url
      
      if current_url.blank?
        return {
          success: false,
          message: "No page is currently being viewed in the interactive browser. " \
                   "Ask the user to open a page first, or use the web_page_view tool to open one."
        }
      end

      Rails.logger.info "[ReadViewedPageTool] Reading page: #{current_url} (detail: #{detail_level})"

      # Fetch and parse the page
      begin
        content = fetch_and_parse_page(current_url, detail_level)
        
        {
          success: true,
          url: current_url,
          detail_level: detail_level,
          content: content,
          message: "Successfully read the page content from #{extract_domain(current_url)}"
        }
      rescue StandardError => e
        Rails.logger.error "[ReadViewedPageTool] Error reading page: #{e.message}"
        {
          success: false,
          url: current_url,
          error: e.message,
          message: "Could not read the page content: #{e.message}"
        }
      end
    end

    private

    def get_current_viewed_url
      # Try multiple sources to find the current viewed URL
      
      # 1. Check context for current viewed URL (passed from controller)
      url = @context[:current_viewed_url] || @context["current_viewed_url"]
      return url if url.present?
      
      # 2. Check for current_page_url (alternative key)
      url = @context[:current_page_url] || @context["current_page_url"]
      return url if url.present?

      # 3. Check session for last proxy URL (if session is passed)
      if @context[:session].present?
        url = @context[:session][:current_viewed_url] || @context[:session][:proxy_current_url]
        return url if url.present?
      end

      # 4. Check user's last canvas data
      if @context[:user].present?
        # Look for recent web_page_viewer canvas
        last_canvas = get_last_web_viewer_canvas
        return last_canvas[:url] if last_canvas.present? && last_canvas[:url].present?
      end

      nil
    end

    def get_last_web_viewer_canvas
      # This would need to be implemented based on how canvas state is stored
      # For now, we'll rely on session/context
      nil
    end

    def fetch_and_parse_page(url, detail_level)
      require 'nokogiri'
      require 'net/http'

      uri = URI.parse(url)
      
      # Use the same cookie jar as the proxy for authenticated sessions
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.request_uri)
      request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      request['Accept'] = 'text/html,application/xhtml+xml'
      
      # Add cookies from proxy session if available
      add_proxy_cookies(request, uri.host)

      response = http.request(request)
      
      # Follow redirects
      if response.is_a?(Net::HTTPRedirection)
        new_url = response['location']
        new_url = URI.join(url, new_url).to_s if new_url.start_with?('/')
        return fetch_and_parse_page(new_url, detail_level)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Page returned status #{response.code}"
      end

      html = response.body.force_encoding('UTF-8')
      doc = Nokogiri::HTML(html)

      # Remove script, style, and hidden elements
      doc.css('script, style, noscript, iframe, [hidden], [style*="display:none"], [style*="display: none"]').remove

      case detail_level
      when "full"
        extract_full_content(doc)
      when "structured"
        extract_structured_content(doc)
      else # summary
        extract_summary_content(doc)
      end
    end

    def extract_summary_content(doc)
      content = {}

      # Page title
      content[:title] = doc.at_css('title')&.text&.strip

      # Meta description
      content[:description] = doc.at_css('meta[name="description"]')&.[]('content')

      # Main headings (h1, h2)
      content[:headings] = []
      doc.css('h1, h2').each do |h|
        text = h.text.strip
        content[:headings] << { level: h.name, text: text } if text.present?
      end
      content[:headings] = content[:headings].first(10)

      # Main content - look for article, main, or body content
      main_element = doc.at_css('article') || doc.at_css('main') || doc.at_css('[role="main"]') || doc.at_css('body')
      
      if main_element
        # Get paragraphs
        paragraphs = main_element.css('p').map { |p| p.text.strip }.reject(&:blank?).first(5)
        content[:key_paragraphs] = paragraphs
      end

      # Key links
      content[:key_links] = doc.css('nav a, header a, [role="navigation"] a').map do |a|
        { text: a.text.strip, href: a['href'] }
      end.reject { |l| l[:text].blank? }.uniq { |l| l[:text] }.first(10)

      # Forms present
      content[:forms] = doc.css('form').map do |form|
        {
          action: form['action'],
          method: form['method'] || 'GET',
          inputs: form.css('input, select, textarea').map { |i| 
            { name: i['name'], type: i['type'] || i.name, placeholder: i['placeholder'] }
          }.reject { |i| i[:name].blank? }.first(5)
        }
      end.first(3)

      content
    end

    def extract_full_content(doc)
      content = extract_summary_content(doc)

      # Add all readable text
      main_element = doc.at_css('article') || doc.at_css('main') || doc.at_css('[role="main"]') || doc.at_css('body')
      
      if main_element
        full_text = main_element.text.gsub(/\s+/, ' ').strip
        # Truncate to reasonable size for AI context
        content[:full_text] = full_text.first(8000)
        content[:text_truncated] = full_text.length > 8000
      end

      content
    end

    def extract_structured_content(doc)
      content = extract_summary_content(doc)

      # All headings with hierarchy
      content[:all_headings] = doc.css('h1, h2, h3, h4, h5, h6').map do |h|
        { level: h.name.sub('h', '').to_i, text: h.text.strip }
      end.reject { |h| h[:text].blank? }.first(30)

      # All links grouped by section
      content[:all_links] = doc.css('a[href]').map do |a|
        href = a['href']
        next if href.blank? || href.start_with?('#') || href.start_with?('javascript:')
        { text: a.text.strip.presence || href, href: href }
      end.compact.uniq { |l| l[:href] }.first(50)

      # Images with alt text
      content[:images] = doc.css('img[alt]').map do |img|
        { alt: img['alt'], src: img['src'] }
      end.reject { |i| i[:alt].blank? }.first(10)

      # Buttons
      content[:buttons] = doc.css('button, input[type="submit"], input[type="button"], [role="button"]').map do |btn|
        btn.text.strip.presence || btn['value']
      end.compact.uniq.first(10)

      content
    end

    def add_proxy_cookies(request, host)
      # Try to get cookies from the proxy session
      return unless @context[:session].present?

      proxy_session_id = @context[:session][:proxy_session_id]
      return unless proxy_session_id.present?

      # Look up stored cookies for this proxy session
      cookie_key = "proxy_cookies:#{proxy_session_id}:#{host}"
      cookies = Rails.cache.read(cookie_key)
      
      if cookies.present?
        request['Cookie'] = cookies
      end
    end

    def extract_domain(url)
      URI.parse(url).host rescue url
    end
  end
end

