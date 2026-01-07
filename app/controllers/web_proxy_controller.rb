# frozen_string_literal: true

# WebProxyController
# Proxies external web pages to allow embedding in iframes
# Proxies ALL resources (HTML, CSS, JS, images) to bypass CORS and X-Frame-Options
#
class WebProxyController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:proxy, :next_proxy, :service_worker_stub, :generic_proxy, :tracking_pixel]

  COOKIE_JAR_TTL = 30.minutes

  # GET /_next/*path - Catch-all for Next.js chunks that bypass the proxy
  # This handles dynamically loaded chunks that use relative URLs
  def next_proxy
    # Get the base URL from session or referer
    base_url = session[:proxy_base_url]
    
    # Try to extract from referer if not in session
    if base_url.blank? && request.referer.present?
      if request.referer.include?("/web_proxy?url=")
        # Extract the original URL from the referer
        match = request.referer.match(/web_proxy\?url=([^&]+)/)
        if match
          original_url = CGI.unescape(match[1])
          uri = URI.parse(original_url)
          base_url = "#{uri.scheme}://#{uri.host}"
        end
      end
    end
    
    if base_url.blank?
      Rails.logger.warn "[WebProxy] No base URL found for Next.js proxy request: #{request.fullpath}"
      render plain: "No proxy context available", status: :not_found
      return
    end
    
    # Build the full URL from the path
    # With format: false in the route, the full path including extension is in params[:path]
    path = "/_next/#{params[:path]}"
    
    # Preserve query string parameters (important for /_next/image which uses url, w, q params)
    query_string = request.query_string
    full_url = if query_string.present?
                 "#{base_url}#{path}?#{query_string}"
               else
                 "#{base_url}#{path}"
               end
    
    Rails.logger.info "[WebProxy] Next.js proxy: #{request.fullpath} -> #{full_url}"
    
    # Proxy directly instead of redirecting (scripts don't follow redirects well)
    begin
      response = fetch_resource(full_url)
      
      if response[:success]
        content_type = response[:content_type] || detect_content_type(full_url)
        body = response[:body]
        
        # Ensure proper encoding for text content
        if content_type.include?("javascript") || content_type.include?("text/")
          body = body.force_encoding("UTF-8") rescue body
        end
        
        # Set permissive headers
        headers["Access-Control-Allow-Origin"] = "*"
        headers["X-Frame-Options"] = "ALLOWALL"
        headers["Cross-Origin-Resource-Policy"] = "cross-origin"
        headers.delete("Content-Security-Policy")
        
        if content_type.include?("text/") || content_type.include?("javascript") || content_type.include?("json")
          send_data body, type: "#{content_type}; charset=utf-8", disposition: "inline"
        else
          send_data body, type: content_type, disposition: "inline"
        end
      else
        Rails.logger.warn "[WebProxy] Failed to fetch Next.js resource: #{full_url} - #{response[:error]}"
        render plain: "Failed to fetch: #{response[:error]}", status: :bad_gateway
      end
    rescue StandardError => e
      Rails.logger.error "[WebProxy] Error in next_proxy: #{e.message}"
      render plain: "Error: #{e.message}", status: :internal_server_error
    end
  end

  # GET /service-worker.js or /sw.js - Return empty service worker to prevent errors
  def service_worker_stub
    Rails.logger.info "[WebProxy] Service worker stub requested - returning no-op"
    
    # Return a minimal no-op service worker that unregisters itself
    stub_js = <<~JS
      // No-op service worker for proxied pages
      // This prevents errors when sites try to register service workers
      self.addEventListener('install', function(e) {
        self.skipWaiting();
      });
      self.addEventListener('activate', function(e) {
        // Unregister this service worker
        self.registration.unregister();
      });
    JS
    
    headers["Content-Type"] = "application/javascript"
    headers["Service-Worker-Allowed"] = "/"
    render plain: stub_js
  end

  # GET /watch/*path, /espn/*path, etc. - Generic proxy for site-specific paths
  def generic_proxy
    base_url = session[:proxy_base_url]
    
    if base_url.blank?
      Rails.logger.warn "[WebProxy] No base URL for generic proxy: #{request.fullpath}"
      render plain: "No proxy context available", status: :not_found
      return
    end
    
    # Build the full URL from the request path
    full_url = "#{base_url}#{request.fullpath}"
    
    Rails.logger.info "[WebProxy] Generic proxy: #{request.fullpath} -> #{full_url}"
    
    # Redirect to the main proxy endpoint
    redirect_to web_proxy_path(url: full_url), allow_other_host: true
  end

  # GET /akam/*path, /error/e.gif - Return transparent 1x1 gif for tracking pixels
  def tracking_pixel
    # 1x1 transparent GIF
    transparent_gif = Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
    
    headers["Content-Type"] = "image/gif"
    headers["Cache-Control"] = "public, max-age=86400"
    render body: transparent_gif
  end

  # GET /web_proxy?url=https://example.com
  def proxy
    url = params[:url]

    if url.blank?
      render plain: "Missing URL parameter", status: :bad_request
      return
    end
    
    # Decode HTML entities (e.g., &amp; -> &) that may be in URLs from HTML attributes
    url = CGI.unescapeHTML(url)

    # Validate and normalize URL
    begin
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        render plain: "Invalid URL", status: :bad_request
        return
      end
    rescue URI::InvalidURIError
      render plain: "Invalid URL format", status: :bad_request
      return
    end

    # Fetch the resource
    begin
      proxy_session_id = proxy_session_id_from_params
      request_method = request.request_method.to_s.upcase
      upstream_headers = extract_upstream_headers
      upstream_body = request.raw_post

      response = fetch_resource(
        url,
        method: request_method,
        headers: upstream_headers,
        body: upstream_body,
        proxy_session_id: proxy_session_id
      )

      if response[:success]
        # Determine content type - use response header, fallback to extension-based detection
        content_type = response[:content_type] || detect_content_type(url)
        body = response[:body]
        
        # Use the final URI after redirects for URL rewriting
        final_uri = response[:final_uri] || uri

        # Rewrite URLs in HTML and CSS content
        if content_type.include?("text/html")
          # Store the base URL in session for Next.js chunk fallback routing
          base_url = "#{final_uri.scheme}://#{final_uri.host}"
          session[:proxy_base_url] = base_url
          
          # Store the full URL so Amos can read the current viewed page
          session[:current_viewed_url] = final_uri.to_s
          session[:current_viewed_at] = Time.current
          Rails.logger.info "[WebProxy] Stored proxy base URL in session: #{base_url}"
          Rails.logger.info "[WebProxy] Current viewed URL: #{final_uri}"
          
          body = rewrite_html_urls(body, final_uri, proxy_session_id: proxy_session_id)
        elsif content_type.include?("text/css")
          body = rewrite_css_urls(body, final_uri, proxy_session_id: proxy_session_id)
        elsif content_type.include?("javascript")
          # Ensure proper encoding for JS
          body = body.force_encoding("UTF-8") rescue body
        elsif hls_manifest?(content_type, final_uri)
          # HLS manifest - rewrite segment URLs
          Rails.logger.info "[WebProxy] Rewriting HLS manifest: #{final_uri}"
          body = rewrite_hls_manifest(body, final_uri)
        elsif dash_manifest?(content_type, final_uri)
          # DASH manifest - rewrite segment URLs
          Rails.logger.info "[WebProxy] Rewriting DASH manifest: #{final_uri}"
          body = rewrite_dash_manifest(body, final_uri)
        end

        # Set permissive CORS headers on the Rails response
        headers["Access-Control-Allow-Origin"] = "*"
        headers["X-Frame-Options"] = "ALLOWALL"
        headers["Cross-Origin-Resource-Policy"] = "cross-origin"
        headers.delete("Content-Security-Policy")

        headers["X-Proxy-Session-Id"] = proxy_session_id.to_s if proxy_session_id.present?

        # Send response with correct content type and charset
        if content_type.include?("text/") || content_type.include?("javascript") || content_type.include?("json")
          send_data body, type: "#{content_type}; charset=utf-8", disposition: "inline"
        else
          send_data body, type: content_type, disposition: "inline"
        end
      else
        status = response[:status].presence || :bad_gateway
        content_type = response[:content_type] || detect_content_type(url)
        body = response[:body].presence || "Failed to fetch: #{response[:error]}"

        # Still set permissive headers so the iframe can render error pages/assets.
        headers["Access-Control-Allow-Origin"] = "*"
        headers["X-Frame-Options"] = "ALLOWALL"
        headers["Cross-Origin-Resource-Policy"] = "cross-origin"
        headers.delete("Content-Security-Policy")
        headers["X-Proxy-Session-Id"] = proxy_session_id.to_s if proxy_session_id.present?

        if content_type.include?("text/") || content_type.include?("javascript") || content_type.include?("json")
          send_data body, type: "#{content_type}; charset=utf-8", disposition: "inline", status: status
        else
          send_data body, type: content_type, disposition: "inline", status: status
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "[WebProxy] Timeout fetching #{url}: #{e.message}"
      render plain: "Timeout fetching resource", status: :gateway_timeout
    rescue OpenSSL::SSL::SSLError => e
      Rails.logger.error "[WebProxy] SSL error fetching #{url}: #{e.message}"
      render plain: "SSL error", status: :bad_gateway
    rescue SocketError, Errno::ECONNREFUSED => e
      Rails.logger.error "[WebProxy] Connection error fetching #{url}: #{e.message}"
      render plain: "Connection error", status: :bad_gateway
    rescue StandardError => e
      Rails.logger.error "[WebProxy] Error fetching #{url}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      render plain: "Error: #{e.message}", status: :internal_server_error
    end
  end

  private

  def fetch_resource(url, method: "GET", headers: {}, body: nil, proxy_session_id: nil, max_redirects: 5)
    require "net/http"

    uri = URI.parse(url)
    redirect_count = 0

    Rails.logger.info "[WebProxy] Fetching: #{url}"

    # Determine resource type from URL to set appropriate headers
    resource_type = detect_resource_type(uri.path)

    loop do
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 30

      # More lenient SSL verification for problematic sites
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_hostname = true
      end

      method = method.to_s.upcase
      request = Net::HTTPGenericRequest.new(method, !!body, true, uri.request_uri)

      if body.present? && request.request_body_permitted?
        request.body = body
      end

      # Comprehensive browser-like headers to avoid bot detection
      request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      request["Accept-Language"] = "en-US,en;q=0.9"
      request["Accept-Encoding"] = "identity" # Don't accept gzip to simplify handling
      request["Cache-Control"] = "no-cache"
      request["Pragma"] = "no-cache"
      request["Sec-Ch-Ua"] = '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"'
      request["Sec-Ch-Ua-Mobile"] = "?0"
      request["Sec-Ch-Ua-Platform"] = '"macOS"'
      
      # Set appropriate headers based on resource type
      case resource_type
      when :stylesheet
        request["Accept"] = "text/css,*/*;q=0.1"
        request["Sec-Fetch-Dest"] = "style"
        request["Sec-Fetch-Mode"] = "no-cors"
        request["Sec-Fetch-Site"] = "same-origin"
      when :script
        request["Accept"] = "*/*"
        request["Sec-Fetch-Dest"] = "script"
        request["Sec-Fetch-Mode"] = "no-cors"
        request["Sec-Fetch-Site"] = "same-origin"
      when :image
        request["Accept"] = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
        request["Sec-Fetch-Dest"] = "image"
        request["Sec-Fetch-Mode"] = "no-cors"
        request["Sec-Fetch-Site"] = "same-origin"
      when :font
        request["Accept"] = "*/*"
        request["Sec-Fetch-Dest"] = "font"
        request["Sec-Fetch-Mode"] = "cors"
        request["Sec-Fetch-Site"] = "same-origin"
      else
        request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"
        request["Sec-Fetch-Dest"] = "document"
        request["Sec-Fetch-Mode"] = "navigate"
        request["Sec-Fetch-Site"] = "none"
        request["Sec-Fetch-User"] = "?1"
        request["Upgrade-Insecure-Requests"] = "1"
        # Add DNT header that some sites check for
        request["DNT"] = "1"
      end
      
      # Set referer to look like direct navigation from the same site
      request["Referer"] = "https://www.google.com/"

      headers.to_h.each do |k, v|
        next if k.blank? || v.blank?
        next if k.to_s.downcase == "host"
        next if k.to_s.downcase == "cookie"
        request[k] = v.to_s
      end

      if proxy_session_id.present?
        cookie_header = cookie_jar_cookie_header(proxy_session_id, uri.host)
        request["Cookie"] = cookie_header if cookie_header.present?
      end

      response = http.request(request)

      store_set_cookie_headers(proxy_session_id, uri.host, response) if proxy_session_id.present?

      case response
      when Net::HTTPSuccess
        Rails.logger.info "[WebProxy] Success: #{uri} (#{response["Content-Type"]})"
        return {
          success: true,
          body: response.body,
          content_type: response["Content-Type"]&.split(";")&.first&.strip,
          final_uri: uri  # Return the final URI after any redirects
        }
      when Net::HTTPRedirection
        redirect_count += 1
        if redirect_count > max_redirects
          return {
            success: false,
            status: 508,
            error: "Too many redirects",
            body: response.body,
            content_type: response["Content-Type"]&.split(";")&.first&.strip,
            final_uri: uri
          }
        end

        location = response["Location"]
        Rails.logger.info "[WebProxy] Redirect: #{location}"

        # Mimic browser redirect semantics:
        # - For 301/302/303, browsers switch to GET for non-GET requests.
        # - For 307/308, method and body are preserved.
        begin
          code = response.code.to_s
          if %w[301 302 303].include?(code) && method != "GET" && method != "HEAD"
            method = "GET"
            body = nil
          end
        rescue StandardError
          # ignore
        end

        current_uri = uri
        redirect_uri = if location.start_with?("http")
                         URI.parse(location)
                       else
                         URI.join("#{current_uri.scheme}://#{current_uri.host}", location)
                       end

        # Some upstream apps build absolute redirects from client-provided origins.
        # When proxied, those can incorrectly point at localhost / *.localhost, which
        # is not reachable from inside the Rails container. If we detect that, rewrite
        # the redirect host back to the current upstream host.
        begin
          rh = redirect_uri.host.to_s.downcase
          if rh == "localhost" || rh.end_with?(".localhost")
            redirect_uri = URI::Generic.build(
              scheme: current_uri.scheme,
              host: current_uri.host,
              port: ([80, 443].include?(current_uri.port) ? nil : current_uri.port),
              path: redirect_uri.path.presence || "/",
              query: redirect_uri.query,
              fragment: redirect_uri.fragment
            )
          end
        rescue StandardError
          # ignore and proceed with redirect_uri as-is
        end

        uri = redirect_uri
      else
        Rails.logger.warn "[WebProxy] Failed: #{url} - HTTP #{response.code}"
        return {
          success: false,
          status: response.code.to_i,
          error: "HTTP #{response.code}: #{response.message}",
          body: response.body,
          content_type: response["Content-Type"]&.split(";")&.first&.strip,
          final_uri: uri
        }
      end
    end
  rescue => e
    Rails.logger.error "[WebProxy] fetch_resource error: #{e.class} - #{e.message}"
    { success: false, status: 502, error: e.message }
  end

  def rewrite_html_urls(html, base_uri, proxy_session_id: nil)
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    proxy_base = if proxy_session_id.present?
                   "/web_proxy?psid=#{CGI.escape(proxy_session_id.to_s)}&url="
                 else
                   "/web_proxy?url="
                 end

    # Check for <base href="..."> tag and use it for URL resolution if present.
    # Browsers resolve all relative URLs against the <base> href, not the page URL.
    effective_base_uri = base_uri
    begin
      base_tag_match = html.match(/<base[^>]+href\s*=\s*["']([^"']+)["']/i)
      if base_tag_match
        base_href = base_tag_match[1].strip
        if base_href.start_with?("http")
          effective_base_uri = URI.parse(base_href)
        elsif base_href.start_with?("//")
          effective_base_uri = URI.parse("#{base_uri.scheme}:#{base_href}")
        elsif base_href.start_with?("/")
          effective_base_uri = URI.parse("#{base_url}#{base_href}")
        else
          # Relative base (rare) - resolve against page
          effective_base_uri = URI.join(base_uri.to_s, base_href)
        end
        Rails.logger.debug "[WebProxy] Found <base> tag, effective base: #{effective_base_uri}"
      end
    rescue StandardError => e
      Rails.logger.debug "[WebProxy] Failed to parse <base> tag: #{e.message}"
    end

    # Helper to make absolute URL using the effective base
    make_absolute = ->(href) {
      return href if href.nil? || href.empty?
      return href if href.start_with?("data:") || href.start_with?("javascript:") || href.start_with?("#") || href.start_with?("mailto:") || href.start_with?("tel:")

      if href.start_with?("//")
        "#{effective_base_uri.scheme}:#{href}"
      elsif href.start_with?("/")
        # Absolute path - always resolve against origin (not base path)
        "#{effective_base_uri.scheme}://#{effective_base_uri.host}#{href}"
      elsif href.start_with?("http")
        href
      else
        # Relative URL - resolve against effective base (respects <base> tag)
        begin
          URI.join(effective_base_uri.to_s, href).to_s
        rescue StandardError
          # Fallback: treat as root-relative
          "#{base_url}/#{href}"
        end
      end
    }

    # Rewrite src attributes (scripts, images, iframes, etc.)
    html = html.gsub(/(<(?:script|img|iframe|source|video|audio|embed)[^>]*\s)src\s*=\s*["']([^"']+)["']/i) do |match|
      prefix = $1
      src = $2
      next match if src.include?("/web_proxy") || src.include?("web_proxy?url=")
      absolute_url = make_absolute.call(src)
      if absolute_url.start_with?("http")
        "#{prefix}src=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
      else
        match
      end
    end

    # Rewrite unquoted src attributes (some apps emit src=/path without quotes)
    html = html.gsub(/(<(?:script|img|iframe|source|video|audio|embed)[^>]*\s)src\s*=\s*([^"'\s>]+)([^>]*>)/i) do |match|
      prefix = $1
      src = $2
      suffix = $3
      next match if src.include?("/web_proxy") || src.include?("web_proxy?url=")
      absolute_url = make_absolute.call(src)
      if absolute_url.start_with?("http")
        "#{prefix}src=\"#{proxy_base}#{CGI.escape(absolute_url)}\"#{suffix}"
      else
        match
      end
    end

    # Rewrite ALL link href attributes (stylesheets, preloads, icons, etc.)
    html = html.gsub(/(<link[^>]*\s)href\s*=\s*["']([^"']+)["']/i) do |match|
      prefix = $1
      href = $2
      next match if href.include?("/web_proxy") || href.include?("web_proxy?url=")
      absolute_url = make_absolute.call(href)
      if absolute_url.start_with?("http")
        "#{prefix}href=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
      else
        match
      end
    end

    # Rewrite unquoted link href attributes (e.g., href=/trix.css)
    html = html.gsub(/(<link[^>]*\s)href\s*=\s*([^"'\s>]+)([^>]*>)/i) do |match|
      prefix = $1
      href = $2
      suffix = $3
      next match if href.include?("/web_proxy") || href.include?("web_proxy?url=")
      absolute_url = make_absolute.call(href)
      if absolute_url.start_with?("http")
        "#{prefix}href=\"#{proxy_base}#{CGI.escape(absolute_url)}\"#{suffix}"
      else
        match
      end
    end

    # Rewrite href for navigation links (to stay in proxy)
    html = html.gsub(/(<a[^>]*\s)href\s*=\s*["']([^"']+)["']/i) do |match|
      prefix = $1
      href = $2
      next match if href.include?("/web_proxy") || href.include?("web_proxy?url=")
      absolute_url = make_absolute.call(href)
      if absolute_url.start_with?("http")
        "#{prefix}href=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
      else
        match
      end
    end

    # Rewrite unquoted <a href=/path> navigation links
    html = html.gsub(/(<a[^>]*\s)href\s*=\s*([^"'\s>]+)([^>]*>)/i) do |match|
      prefix = $1
      href = $2
      suffix = $3
      next match if href.include?("/web_proxy") || href.include?("web_proxy?url=")
      absolute_url = make_absolute.call(href)
      if absolute_url.start_with?("http")
        "#{prefix}href=\"#{proxy_base}#{CGI.escape(absolute_url)}\"#{suffix}"
      else
        match
      end
    end

    # Rewrite srcset attributes
    html = html.gsub(/srcset\s*=\s*["']([^"']+)["']/i) do |match|
      srcset = $1
      new_srcset = srcset.split(",").map do |src_descriptor|
        parts = src_descriptor.strip.split(/\s+/)
        if parts.any?
          url = parts[0]
          descriptor = parts[1..-1].join(" ")
          absolute_url = make_absolute.call(url)
          if absolute_url.start_with?("http")
            "#{proxy_base}#{CGI.escape(absolute_url)} #{descriptor}".strip
          else
            src_descriptor
          end
        else
          src_descriptor
        end
      end.join(", ")
      "srcset=\"#{new_srcset}\""
    end

    # Rewrite inline style url() references
    html = html.gsub(/url\s*\(\s*["']?([^)"']+)["']?\s*\)/i) do |match|
      url = $1
      absolute_url = make_absolute.call(url)
      if absolute_url.start_with?("http")
        "url('#{proxy_base}#{CGI.escape(absolute_url)}')"
      else
        match
      end
    end

    # Add script to handle dynamic content, form submissions, and Webpack chunk loading
    # Pass the effective base (respecting <base> tag) to JS for dynamic request resolution
    effective_base_url = "#{effective_base_uri.scheme}://#{effective_base_uri.host}"
    effective_base_full = effective_base_uri.to_s
    page_url = base_uri.to_s
    intercept_script = <<~SCRIPT
      <script>
        // Comprehensive proxy intercept for dynamic resource loading
        (function() {
          const proxyBase = '#{proxy_base}';
          const originalBaseUrl = '#{effective_base_url}';
          const originalPageUrl = '#{page_url}';
          const currentOrigin = window.location.origin;

          // Effective base for URL resolution (respects <base> tag if present)
          // This is computed server-side from any <base href="..."> in the HTML.
          let effectiveBaseForResolution = '#{effective_base_full}';

          // Also check DOM for <base> tag in case it was injected dynamically
          function getEffectiveBase() {
            const baseEl = document.querySelector('base[href]');
            if (baseEl) {
              const href = baseEl.getAttribute('href');
              if (href) {
                try {
                  return new URL(href, originalBaseUrl).toString();
                } catch (e) {}
              }
            }
            return effectiveBaseForResolution;
          }
          
          // Store the base URL for this proxied page
          window.__PROXY_BASE_URL__ = originalBaseUrl;
          sessionStorage.setItem('__proxy_base_url__', originalBaseUrl);
          
          // ========== LOCATION SPOOFING FOR SPA ROUTERS ==========
          // Parse the original page URL to create a fake location object
          const originalUrlObj = new URL(originalPageUrl);
          
          // CRITICAL: Use history.replaceState to change the URL to use the original path
          // This makes window.location.pathname return the correct value for SPA routers
          // We keep the psid in a hash fragment so we can recover it if needed
          try {
            const psidMatch = window.location.search.match(/psid=([^&]+)/);
            const psid = psidMatch ? psidMatch[1] : '';
            // Replace the URL to use the original path but keep it on our origin
            // This makes window.location.pathname return /cities/austin-tx/... instead of /web_proxy
            const newPath = originalUrlObj.pathname + originalUrlObj.search;
            const stateData = { 
              proxyUrl: window.location.href,
              originalUrl: originalPageUrl,
              psid: psid
            };
            // Only do this if we're still on the /web_proxy path
            if (window.location.pathname === '/web_proxy') {
              history.replaceState(stateData, '', newPath);
              console.log('[WebProxy] Replaced URL path to:', newPath);
            }
          } catch (e) {
            console.warn('[WebProxy] Could not replaceState:', e);
          }
          
          // Track current "virtual" path for SPA navigation
          let virtualPath = originalUrlObj.pathname;
          let virtualSearch = originalUrlObj.search;
          let virtualHash = originalUrlObj.hash;
          
          // Create a fake location object that SPAs can read
          const fakeLocation = {
            get href() { return originalUrlObj.origin + virtualPath + virtualSearch + virtualHash; },
            get origin() { return originalUrlObj.origin; },
            get protocol() { return originalUrlObj.protocol; },
            get host() { return originalUrlObj.host; },
            get hostname() { return originalUrlObj.hostname; },
            get port() { return originalUrlObj.port; },
            get pathname() { return virtualPath; },
            get search() { return virtualSearch; },
            get hash() { return virtualHash; },
            set hash(val) { 
              virtualHash = val.startsWith('#') ? val : '#' + val;
              window.dispatchEvent(new HashChangeEvent('hashchange'));
            },
            set href(val) {
              // Navigate via proxy
              const targetUrl = new URL(val, originalUrlObj.origin + virtualPath).toString();
              window.location.href = proxyBase + encodeURIComponent(targetUrl);
            },
            assign: function(url) { this.href = url; },
            replace: function(url) { 
              const targetUrl = new URL(url, originalUrlObj.origin + virtualPath).toString();
              window.location.replace(proxyBase + encodeURIComponent(targetUrl));
            },
            reload: function() { window.location.reload(); },
            toString: function() { return this.href; }
          };
          
          // Try to expose fake location for Angular and other frameworks
          // This works by making __fakeLocation available and patching some common access patterns
          window.__PROXY_FAKE_LOCATION__ = fakeLocation;
          window.__PROXY_ORIGINAL_URL__ = originalPageUrl;
          
          // Intercept history.pushState and history.replaceState
          const originalPushState = history.pushState.bind(history);
          const originalReplaceState = history.replaceState.bind(history);
          
          history.pushState = function(state, title, url) {
            if (url) {
              try {
                // Parse the URL relative to original site
                const newUrl = new URL(url, originalUrlObj.origin + virtualPath);
                
                // If this is a same-origin navigation (relative to original site)
                if (newUrl.origin === originalUrlObj.origin || 
                    newUrl.hostname === 'localhost' || 
                    newUrl.hostname.endsWith('.localhost')) {
                  virtualPath = newUrl.pathname;
                  virtualSearch = newUrl.search;
                  virtualHash = newUrl.hash;
                  
                  // For same-origin SPA navigation, we can just update the path
                  // The actual navigation will happen when fetch/XHR intercepts kick in
                  const localPath = virtualPath + virtualSearch + virtualHash;
                  return originalPushState(state, title, localPath);
                }
              } catch (e) {
                console.warn('[WebProxy] pushState error:', e);
              }
            }
            return originalPushState(state, title, url);
          };
          
          history.replaceState = function(state, title, url) {
            if (url) {
              try {
                const newUrl = new URL(url, originalUrlObj.origin + virtualPath);
                if (newUrl.origin === originalUrlObj.origin ||
                    newUrl.hostname === 'localhost' ||
                    newUrl.hostname.endsWith('.localhost')) {
                  virtualPath = newUrl.pathname;
                  virtualSearch = newUrl.search;
                  virtualHash = newUrl.hash;
                  
                  const localPath = virtualPath + virtualSearch + virtualHash;
                  return originalReplaceState(state, title, localPath);
                }
              } catch (e) {
                console.warn('[WebProxy] replaceState error:', e);
              }
            }
            return originalReplaceState(state, title, url);
          };
          
          // Handle popstate events to update virtual location
          window.addEventListener('popstate', function(e) {
            // Try to extract the original URL from the proxy URL
            const params = new URLSearchParams(window.location.search);
            const urlParam = params.get('url');
            if (urlParam) {
              try {
                const decoded = decodeURIComponent(urlParam);
                const newUrl = new URL(decoded);
                if (newUrl.origin === originalUrlObj.origin) {
                  virtualPath = newUrl.pathname;
                  virtualSearch = newUrl.search;
                  virtualHash = newUrl.hash;
                }
              } catch (e) {}
            }
          });
          
          // Intercept link clicks to handle SPA navigation
          document.addEventListener('click', function(e) {
            const link = e.target.closest('a[href]');
            if (!link) return;
            
            const href = link.getAttribute('href');
            if (!href || href.startsWith('javascript:') || href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('tel:')) {
              return;
            }
            
            // Skip if already proxied
            if (isAlreadyProxied(href)) return;
            
            // Resolve the URL
            let targetUrl;
            try {
              targetUrl = new URL(href, originalUrlObj.origin + virtualPath).toString();
            } catch (ex) {
              return;
            }
            
            // Fix any localhost mangling
            targetUrl = fixMangledUrl(targetUrl);
            
            // If it's a same-origin navigation, route through proxy
            try {
              const targetObj = new URL(targetUrl);
              if (targetObj.origin === originalUrlObj.origin || targetObj.hostname.endsWith('.localhost') || targetObj.hostname === 'localhost') {
                e.preventDefault();
                // Navigate via proxy
                const proxiedUrl = proxyBase + encodeURIComponent(targetUrl.startsWith('http') ? targetUrl : originalUrlObj.origin + targetUrl);
                if (link.target === '_blank') {
                  window.open(proxiedUrl, '_blank');
                } else {
                  window.location.href = proxiedUrl;
                }
              }
            } catch (ex) {}
          }, true);
          
          // ========== END LOCATION SPOOFING ==========
          
          // Block Service Worker registration (they don't work through proxy)
          if (navigator.serviceWorker) {
            navigator.serviceWorker.register = function() {
              console.log('[WebProxy] Service Worker registration blocked');
              return Promise.reject(new Error('Service Workers disabled in proxy mode'));
            };
          }
          
          // Helper to check if URL is already proxied or is a local path
          function isAlreadyProxied(url) {
            return url.includes('/web_proxy') || url.includes('web_proxy?url=');
          }
          
          // Helper to fix URLs that incorrectly use the proxy origin
          function fixMangledUrl(url) {
            try {
              const urlObj = new URL(url, originalPageUrl);

              // If URL contains the proxy origin (localhost/app.localhost) but should be the original site
              const isProxyHost =
                (urlObj.origin === currentOrigin) ||
                (urlObj.hostname === 'localhost') ||
                (urlObj.hostname && urlObj.hostname.endsWith('.localhost'));

              if (isProxyHost && !urlObj.pathname.startsWith('/web_proxy')) {
                return originalBaseUrl + urlObj.pathname + urlObj.search + (urlObj.hash || '');
              }
            } catch (e) {
              // ignore
            }

            return url;
          }
          
          // Helper to convert relative URLs to proxied absolute URLs
          function proxyUrl(url) {
            if (!url || url.startsWith('data:') || url.startsWith('blob:') || url.startsWith('javascript:')) {
              return url;
            }
            
            // Skip if already proxied
            if (isAlreadyProxied(url)) {
              return url;
            }
            
            // Fix URLs that were incorrectly built using proxy origin
            url = fixMangledUrl(url);
            
            let absoluteUrl;
            try {
              // Resolve against the effective base (respects <base> tag)
              const base = getEffectiveBase();
              absoluteUrl = new URL(url, base).toString();
            } catch (e) {
              // Fallbacks
              if (url.startsWith('//')) {
                absoluteUrl = '#{effective_base_uri.scheme}:' + url;
              } else if (url.startsWith('/')) {
                absoluteUrl = originalBaseUrl + url;
              } else if (url.startsWith('http://') || url.startsWith('https://')) {
                absoluteUrl = url;
              } else {
                absoluteUrl = originalBaseUrl + '/' + url;
              }
            }
            
            return proxyBase + encodeURIComponent(absoluteUrl);
          }
          
          // Intercept fetch
          const originalFetch = window.fetch;
          window.fetch = function(input, options) {
            let url = typeof input === 'string' ? input : (input.url || input);
            if (typeof url === 'string') {
              if (!isAlreadyProxied(url)) {
                const proxied = proxyUrl(url);
                if (proxied && proxied !== url) {
                  url = proxied;
                  if (typeof input === 'string') {
                    input = url;
                  } else if (input.url) {
                    input = new Request(url, input);
                  }
                }
              }
            }
            return originalFetch.call(this, input, options);
          };
          
          // Intercept XMLHttpRequest
          const originalXHROpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url, ...rest) {
            if (typeof url === 'string') {
              if (!isAlreadyProxied(url)) {
                const proxied = proxyUrl(url);
                if (proxied && proxied !== url) url = proxied;
              }
            }
            return originalXHROpen.call(this, method, url, ...rest);
          };
          
          // Intercept dynamic script/link/img creation
          const originalCreateElement = document.createElement.bind(document);
          document.createElement = function(tagName, options) {
            const element = originalCreateElement(tagName, options);
            const tag = tagName.toLowerCase();
            
            if (tag === 'script' || tag === 'link' || tag === 'img') {
              // Use a property descriptor to intercept src/href assignment
              const srcAttr = tag === 'link' ? 'href' : 'src';
              let internalValue = '';
              
              Object.defineProperty(element, srcAttr, {
                get: function() { return internalValue; },
                set: function(value) {
                  if (value && typeof value === 'string') {
                    if (!isAlreadyProxied(value)) {
                      const proxied = proxyUrl(value);
                      if (proxied && proxied !== value) value = proxied;
                    }
                  }
                  internalValue = value;
                  element.setAttribute(srcAttr, value);
                },
                configurable: true
              });
            }
            
            return element;
          };
          
          // Store original HTMLImageElement.prototype.src descriptor BEFORE patching
          const originalImgSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
          
          // Patch HTMLImageElement.prototype.src to intercept ALL image src assignments
          if (originalImgSrcDescriptor && originalImgSrcDescriptor.set) {
            Object.defineProperty(HTMLImageElement.prototype, 'src', {
              get: originalImgSrcDescriptor.get,
              set: function(value) {
                if (value && typeof value === 'string') {
                  if (!isAlreadyProxied(value)) {
                    const proxied = proxyUrl(value);
                    if (proxied && proxied !== value) value = proxied;
                  }
                }
                return originalImgSrcDescriptor.set.call(this, value);
              },
              configurable: true,
              enumerable: true
            });
          }
          
          // Intercept Image constructor (used by many JS frameworks)
          const OriginalImage = window.Image;
          window.Image = function(width, height) {
            // Just create via original - the prototype.src patch handles interception
            return new OriginalImage(width, height);
          };
          window.Image.prototype = OriginalImage.prototype;
          
          // Also intercept setAttribute for img elements (some code bypasses .src property)
          const originalSetAttribute = Element.prototype.setAttribute;
          Element.prototype.setAttribute = function(name, value) {
            if (this.tagName === 'IMG' && name.toLowerCase() === 'src') {
              if (value && typeof value === 'string') {
                if (!isAlreadyProxied(value)) {
                  const proxied = proxyUrl(value);
                  if (proxied && proxied !== value) value = proxied;
                }
              }
            } else if (this.tagName === 'SCRIPT' && name.toLowerCase() === 'src') {
              if (value && typeof value === 'string') {
                if (!isAlreadyProxied(value)) {
                  const proxied = proxyUrl(value);
                  if (proxied && proxied !== value) value = proxied;
                }
              }
            } else if (this.tagName === 'LINK' && name.toLowerCase() === 'href') {
              if (value && typeof value === 'string') {
                if (!isAlreadyProxied(value)) {
                  const proxied = proxyUrl(value);
                  if (proxied && proxied !== value) value = proxied;
                }
              }
            }
            return originalSetAttribute.call(this, name, value);
          };
          
          // Override Webpack's public path if it exists
          // This is set before any Webpack code runs
          Object.defineProperty(window, '__webpack_public_path__', {
            get: function() { return proxyBase + encodeURIComponent(originalBaseUrl); },
            set: function(v) { /* ignore */ },
            configurable: true
          });
          
          // Also try to intercept __webpack_require__.p (Next.js uses this)
          if (typeof __webpack_require__ !== 'undefined' && __webpack_require__.p) {
            __webpack_require__.p = proxyBase + encodeURIComponent(originalBaseUrl);
          }
          
          // Intercept dynamic imports (import())
          // This patches the import() mechanism used by Webpack/Next.js for code splitting
          const originalImport = window.import || function(){};
          
          // Handle form submissions
          document.addEventListener('submit', function(e) {
            const form = e.target;
            if (!form || form.tagName !== 'FORM') return;

            // Determine action (can be relative, blank, or incorrectly rooted at localhost).
            const rawAction = (form.getAttribute('action') || form.action || '').trim();
            const method = (form.getAttribute('method') || form.method || 'get').toLowerCase();

            // If already proxied, let it proceed.
            if (rawAction && isAlreadyProxied(rawAction)) return;

            // Resolve to an upstream absolute URL and fix any localhost/app.localhost mangling.
            let absoluteAction = rawAction;
            try {
              absoluteAction = new URL(rawAction || originalPageUrl, originalPageUrl).toString();
            } catch (err) {
              // If parsing fails, fall back to original page URL.
              absoluteAction = originalPageUrl;
            }
            absoluteAction = fixMangledUrl(absoluteAction);

            // If we still don't have an upstream absolute URL, bail.
            if (!absoluteAction || !absoluteAction.startsWith('http')) return;

            e.preventDefault();

            if (method === 'get') {
              const formData = new FormData(form);
              const params = new URLSearchParams(formData).toString();
              const fullUrl = absoluteAction + (absoluteAction.includes('?') ? '&' : '?') + params;
              window.location.href = proxyBase + encodeURIComponent(fullUrl);
              return;
            }

            // Non-GET: post through the proxy endpoint.
            form.action = proxyBase + encodeURIComponent(absoluteAction);
            form.submit();
          }, true);
          
          // Intercept script loading via document.write (some sites use this)
          const originalDocWrite = document.write.bind(document);
          document.write = function(html) {
            if (typeof html === 'string') {
              // Rewrite src/href attributes in the HTML (including relative URLs)
              html = html.replace(/\\ssrc=["']([^"']+)["']/gi, function(match, url) {
                if (!url || isAlreadyProxied(url) || url.startsWith('data:') || url.startsWith('blob:') || url.startsWith('javascript:')) return match;
                return ' src="' + proxyUrl(url) + '"';
              });
              html = html.replace(/\\shref=["']([^"']+)["']/gi, function(match, url) {
                if (!url || isAlreadyProxied(url) || url.startsWith('data:') || url.startsWith('blob:') || url.startsWith('javascript:') || url.startsWith('#')) return match;
                return ' href="' + proxyUrl(url) + '"';
              });
            }
            return originalDocWrite(html);
          };
          
          console.log('[WebProxy] Intercept script loaded for:', originalBaseUrl);
        })();
      </script>
    SCRIPT

    # Insert IMMEDIATELY after <head> so it runs BEFORE any other scripts
    # This is critical for intercepting dynamic imports in Next.js/Webpack
    if html.match?(/<head[^>]*>/i)
      html = html.sub(/(<head[^>]*>)/i, "\\1#{intercept_script}")
    elsif html.include?("<html")
      # If no head tag, insert after html tag
      html = html.sub(/(<html[^>]*>)/i, "\\1<head>#{intercept_script}</head>")
    else
      # Fallback: prepend to document
      html = "#{intercept_script}#{html}"
    end

    html
  end

  # Detect content type from URL/file extension
  def detect_content_type(url)
    extension = File.extname(URI.parse(url).path).downcase
    
    case extension
    when ".html", ".htm"
      "text/html"
    when ".css"
      "text/css"
    when ".js", ".mjs"
      "application/javascript"
    when ".json"
      "application/json"
    when ".png"
      "image/png"
    when ".jpg", ".jpeg"
      "image/jpeg"
    when ".gif"
      "image/gif"
    when ".svg"
      "image/svg+xml"
    when ".webp"
      "image/webp"
    when ".ico"
      "image/x-icon"
    when ".woff"
      "font/woff"
    when ".woff2"
      "font/woff2"
    when ".ttf"
      "font/ttf"
    when ".eot"
      "application/vnd.ms-fontobject"
    when ".otf"
      "font/otf"
    when ".xml"
      "application/xml"
    when ".pdf"
      "application/pdf"
    when ".mp4"
      "video/mp4"
    when ".webm"
      "video/webm"
    when ".m3u8"
      "application/vnd.apple.mpegurl"
    when ".mpd"
      "application/dash+xml"
    when ".ts"
      "video/mp2t"
    when ".m4s"
      "video/iso.segment"
    when ".mp3"
      "audio/mpeg"
    when ".wav"
      "audio/wav"
    when ".aac"
      "audio/aac"
    when ".m4a"
      "audio/mp4"
    else
      "text/html" # Default to HTML for unknown
    end
  rescue
    "text/html"
  end

  def rewrite_css_urls(css, base_uri, proxy_session_id: nil)
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    proxy_base = if proxy_session_id.present?
                   "/web_proxy?psid=#{CGI.escape(proxy_session_id.to_s)}&url="
                 else
                   "/web_proxy?url="
                 end

    # Rewrite url() references in CSS
    css.gsub(/url\s*\(\s*["']?([^)"']+)["']?\s*\)/i) do |match|
      url = $1
      next match if url.start_with?("data:")

      absolute_url = if url.start_with?("//")
                       "#{base_uri.scheme}:#{url}"
                     elsif url.start_with?("/")
                       "#{base_url}#{url}"
                     elsif url.start_with?("http")
                       url
                     else
                       # Relative URL - resolve from CSS file location
                       base_path = base_uri.path.sub(/\/[^\/]*$/, "/")
                       "#{base_url}#{base_path}#{url}"
                     end

      if absolute_url.start_with?("http")
        "url('#{proxy_base}#{CGI.escape(absolute_url)}')"
      else
        match
      end
    end
  end

  def proxy_session_id_from_params
    psid = params[:psid].presence || params[:proxy_session_id].presence
    psid ||= session[:proxy_session_id].presence
    psid ||= session.id.to_s
    session[:proxy_session_id] = psid
    psid
  end

  def extract_upstream_headers
    # NOTE: Do NOT include Accept-Encoding - we need uncompressed responses to rewrite URLs
    allowed = %w[
      Accept
      Accept-Language
      Content-Type
      Origin
      Referer
      X-Requested-With
      Authorization
      Cache-Control
      Pragma
    ]

    # Also forward any X- prefixed headers (common for APIs)
    out = {}
    
    allowed.each do |name|
      val = request.headers[name]
      out[name] = val if val.present?
    end
    
    # Forward X-* headers (like X-Resy-Auth-Token, X-API-Key, etc.)
    request.headers.each do |key, value|
      next unless key.is_a?(String)
      next unless key.start_with?("HTTP_X_") || key.start_with?("X-")
      
      # Convert HTTP_X_FOO_BAR to X-Foo-Bar
      header_name = if key.start_with?("HTTP_X_")
                      key.sub("HTTP_X_", "X-").split("_").map(&:capitalize).join("-")
                    else
                      key
                    end
      
      # Skip certain internal headers
      next if header_name.downcase.include?("frame") || header_name.downcase.include?("csrf")
      
      out[header_name] = value if value.present?
    end
    
    # Fix Referer to point to original site, not our proxy
    if out["Referer"]&.include?("/web_proxy")
      begin
        referer_params = CGI.parse(URI.parse(out["Referer"]).query || "")
        if referer_params["url"]&.first
          out["Referer"] = referer_params["url"].first
        end
      rescue StandardError
        # Leave as-is
      end
    end
    
    out
  end

  def cookie_jar_cache_key(proxy_session_id, host)
    "web_proxy_cookie_jar:#{proxy_session_id}:#{host}"
  end

  def cookie_jar_read(proxy_session_id, host)
    Rails.cache.read(cookie_jar_cache_key(proxy_session_id, host)) || {}
  end

  def cookie_jar_write(proxy_session_id, host, jar)
    Rails.cache.write(cookie_jar_cache_key(proxy_session_id, host), jar, expires_in: COOKIE_JAR_TTL)
  end

  def cookie_jar_cookie_header(proxy_session_id, host)
    jar = cookie_jar_read(proxy_session_id, host)
    return "" unless jar.is_a?(Hash) && jar.any?

    jar.map do |k, v|
      val =
        if v.is_a?(Hash)
          v["value"] || v[:value]
        else
          v
        end
      "#{k}=#{val}"
    end.join("; ")
  end

  def store_set_cookie_headers(proxy_session_id, host, response)
    set_cookies = response.get_fields("set-cookie")
    return if set_cookies.blank?

    set_cookies.each do |set_cookie|
      raw = set_cookie.to_s
      parts = raw.split(";").map(&:strip)
      name_value = parts.shift.to_s
      name, value = name_value.split("=", 2)
      next if name.blank?
      next if value.nil?

      attrs = {}
      begin
        parts.each do |part|
          k, v = part.split("=", 2)
          k = k.to_s.strip
          v = v.to_s.strip
          next if k.blank?

          case k.downcase
          when "domain"
            attrs[:domain] = v.sub(/\A\./, "").downcase if v.present?
          when "path"
            attrs[:path] = v if v.present?
          when "secure"
            attrs[:secure] = true
          when "httponly"
            attrs[:http_only] = true
          when "samesite"
            attrs[:same_site] = v if v.present?
          when "expires"
            begin
              # CDP expects seconds since epoch
              attrs[:expires] = Time.parse(v).to_f if v.present?
            rescue StandardError
              # ignore
            end
          when "max-age"
            begin
              attrs[:expires] = (Time.now + v.to_i).to_f if v.present?
            rescue StandardError
              # ignore
            end
          end
        end
      rescue StandardError
        # ignore
      end

      # If the upstream cookie specifies a Domain attribute, store it under that domain too.
      # This matters for login flows that hop across subdomains (e.g. auth.example.com setting Domain=.example.com).
      domains = [host.to_s.downcase]
      begin
        dom = attrs[:domain].to_s.strip.downcase
        domains << dom if dom.present?
      rescue StandardError
        # ignore
      end

      cookie_record = { "value" => value }.merge(attrs.compact.transform_keys(&:to_s))

      domains.uniq.each do |dom|
        jar = cookie_jar_read(proxy_session_id, dom)
        jar = {} unless jar.is_a?(Hash)
        jar[name] = cookie_record
        cookie_jar_write(proxy_session_id, dom, jar)
      end
    end
  rescue StandardError => e
    Rails.logger.debug "[WebProxy] Failed to store cookies: #{e.message}"
  end

  # ============================================
  # Video Streaming Support (HLS / DASH)
  # ============================================

  # Check if content is an HLS manifest
  def hls_manifest?(content_type, uri)
    return true if content_type&.include?("application/vnd.apple.mpegurl")
    return true if content_type&.include?("application/x-mpegurl")
    return true if content_type&.include?("audio/mpegurl")
    return true if uri.path&.end_with?(".m3u8")
    false
  end

  # Check if content is a DASH manifest
  def dash_manifest?(content_type, uri)
    return true if content_type&.include?("application/dash+xml")
    return true if uri.path&.end_with?(".mpd")
    false
  end

  # Rewrite HLS manifest to proxy all URLs
  # HLS manifests contain URLs for segments and variant playlists
  def rewrite_hls_manifest(content, base_uri)
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    base_path = base_uri.path.sub(/\/[^\/]*$/, "/")
    proxy_base = "/web_proxy?url="

    lines = content.lines.map do |line|
      line = line.chomp
      
      # Skip comments and empty lines
      if line.start_with?("#") || line.strip.empty?
        # Check for URI= in EXT-X-KEY or EXT-X-MAP tags
        if line.include?("URI=")
          line = line.gsub(/URI="([^"]+)"/) do |match|
            url = $1
            absolute_url = resolve_url(url, base_url, base_path, base_uri.scheme)
            "URI=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
          end
          line = line.gsub(/URI='([^']+)'/) do |match|
            url = $1
            absolute_url = resolve_url(url, base_url, base_path, base_uri.scheme)
            "URI='#{proxy_base}#{CGI.escape(absolute_url)}'"
          end
        end
        line + "\n"
      else
        # This line is a URL (segment or variant playlist)
        url = line.strip
        absolute_url = resolve_url(url, base_url, base_path, base_uri.scheme)
        "#{proxy_base}#{CGI.escape(absolute_url)}\n"
      end
    end

    lines.join
  end

  # Rewrite DASH manifest to proxy all URLs
  # DASH manifests are XML with URLs in various attributes
  def rewrite_dash_manifest(content, base_uri)
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    base_path = base_uri.path.sub(/\/[^\/]*$/, "/")
    proxy_base = "/web_proxy?url="

    # Parse as XML if possible, otherwise use regex
    begin
      require "nokogiri"
      doc = Nokogiri::XML(content)
      
      # Rewrite BaseURL elements
      doc.css("BaseURL").each do |node|
        url = node.text.strip
        next if url.empty?
        absolute_url = resolve_url(url, base_url, base_path, base_uri.scheme)
        node.content = "#{proxy_base}#{CGI.escape(absolute_url)}"
      end

      # Rewrite media/initialization/sourceURL attributes
      %w[media initialization sourceURL].each do |attr|
        doc.xpath("//*[@#{attr}]").each do |node|
          url = node[attr]
          next if url.nil? || url.empty? || url.include?("$")  # Skip template URLs
          absolute_url = resolve_url(url, base_url, base_path, base_uri.scheme)
          node[attr] = "#{proxy_base}#{CGI.escape(absolute_url)}"
        end
      end

      doc.to_xml
    rescue LoadError
      # Nokogiri not available - use regex fallback
      Rails.logger.warn "[WebProxy] Nokogiri not available for DASH parsing, using regex"
      rewrite_dash_manifest_regex(content, base_url, base_path, base_uri.scheme, proxy_base)
    rescue StandardError => e
      Rails.logger.error "[WebProxy] Error parsing DASH manifest: #{e.message}"
      content
    end
  end

  # Fallback regex-based DASH rewriting
  def rewrite_dash_manifest_regex(content, base_url, base_path, scheme, proxy_base)
    # Rewrite BaseURL content
    content = content.gsub(/<BaseURL>([^<]+)<\/BaseURL>/i) do |match|
      url = $1.strip
      absolute_url = resolve_url(url, base_url, base_path, scheme)
      "<BaseURL>#{proxy_base}#{CGI.escape(absolute_url)}</BaseURL>"
    end

    # Rewrite media attribute
    content = content.gsub(/media="([^"]+)"/i) do |match|
      url = $1
      next match if url.include?("$")  # Skip template URLs with variables
      absolute_url = resolve_url(url, base_url, base_path, scheme)
      "media=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
    end

    # Rewrite initialization attribute
    content = content.gsub(/initialization="([^"]+)"/i) do |match|
      url = $1
      next match if url.include?("$")  # Skip template URLs
      absolute_url = resolve_url(url, base_url, base_path, scheme)
      "initialization=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
    end

    content
  end

  # Resolve a URL to absolute form
  def resolve_url(url, base_url, base_path, scheme)
    return url if url.start_with?("http://") || url.start_with?("https://")
    
    if url.start_with?("//")
      "#{scheme}:#{url}"
    elsif url.start_with?("/")
      "#{base_url}#{url}"
    else
      # Relative URL
      "#{base_url}#{base_path}#{url}"
    end
  end

  # Detect resource type from URL path for proper header handling
  def detect_resource_type(path)
    return :document if path.nil? || path.empty?
    
    extension = File.extname(path).downcase
    
    case extension
    when ".css"
      :stylesheet
    when ".js", ".mjs"
      :script
    when ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".avif"
      :image
    when ".woff", ".woff2", ".ttf", ".otf", ".eot"
      :font
    when ".json"
      :json
    when ".mp4", ".webm", ".ogg", ".m3u8", ".mpd"
      :media
    else
      # Check for common patterns in path
      if path.include?("/styles/") || path.include?("/css/")
        :stylesheet
      elsif path.include?("/scripts/") || path.include?("/js/") || path.include?("/modules/")
        :script
      elsif path.include?("/images/") || path.include?("/img/") || path.include?("/assets/")
        :image
      elsif path.include?("/fonts/")
        :font
      else
        :document
      end
    end
  end
end
