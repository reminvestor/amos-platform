# frozen_string_literal: true

# WebProxyController
# Proxies external web pages to allow embedding in iframes
# Proxies ALL resources (HTML, CSS, JS, images) to bypass CORS and X-Frame-Options
#
class WebProxyController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:proxy, :next_proxy, :service_worker_stub, :generic_proxy]

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
      response = fetch_resource(url)

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
          Rails.logger.info "[WebProxy] Stored proxy base URL in session: #{base_url}"
          
          body = rewrite_html_urls(body, final_uri)
        elsif content_type.include?("text/css")
          body = rewrite_css_urls(body, final_uri)
        elsif content_type.include?("javascript")
          # Ensure proper encoding for JS
          body = body.force_encoding("UTF-8") rescue body
        end

        # Set permissive CORS headers on the Rails response
        headers["Access-Control-Allow-Origin"] = "*"
        headers["X-Frame-Options"] = "ALLOWALL"
        headers["Cross-Origin-Resource-Policy"] = "cross-origin"
        headers.delete("Content-Security-Policy")

        # Send response with correct content type and charset
        if content_type.include?("text/") || content_type.include?("javascript") || content_type.include?("json")
          send_data body, type: "#{content_type}; charset=utf-8", disposition: "inline"
        else
          send_data body, type: content_type, disposition: "inline"
        end
      else
        render plain: "Failed to fetch: #{response[:error]}", status: :bad_gateway
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

  def fetch_resource(url, max_redirects: 5)
    require "net/http"

    uri = URI.parse(url)
    redirect_count = 0

    Rails.logger.info "[WebProxy] Fetching: #{url}"

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

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      request["Accept"] = "*/*"
      request["Accept-Language"] = "en-US,en;q=0.9"
      request["Accept-Encoding"] = "identity" # Don't accept gzip to simplify handling
      request["Referer"] = "#{uri.scheme}://#{uri.host}/"

      response = http.request(request)

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
        return { success: false, error: "Too many redirects" } if redirect_count > max_redirects

        location = response["Location"]
        Rails.logger.info "[WebProxy] Redirect: #{location}"
        uri = if location.start_with?("http")
                URI.parse(location)
              else
                URI.join("#{uri.scheme}://#{uri.host}", location)
              end
      else
        Rails.logger.warn "[WebProxy] Failed: #{url} - HTTP #{response.code}"
        return { success: false, error: "HTTP #{response.code}: #{response.message}" }
      end
    end
  rescue => e
    Rails.logger.error "[WebProxy] fetch_resource error: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  def rewrite_html_urls(html, base_uri)
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    proxy_base = "/web_proxy?url="

    # Helper to make absolute URL
    make_absolute = ->(href) {
      return href if href.nil? || href.empty?
      return href if href.start_with?("data:") || href.start_with?("javascript:") || href.start_with?("#") || href.start_with?("mailto:") || href.start_with?("tel:")
      
      if href.start_with?("//")
        "#{base_uri.scheme}:#{href}"
      elsif href.start_with?("/")
        "#{base_url}#{href}"
      elsif href.start_with?("http")
        href
      else
        # Relative URL
        base_path = base_uri.path.sub(/\/[^\/]*$/, "/")
        "#{base_url}#{base_path}#{href}"
      end
    }

    # Rewrite src attributes (scripts, images, iframes, etc.)
    html = html.gsub(/(<(?:script|img|iframe|source|video|audio|embed)[^>]*\s)src\s*=\s*["']([^"']+)["']/i) do |match|
      prefix = $1
      src = $2
      absolute_url = make_absolute.call(src)
      if absolute_url.start_with?("http")
        "#{prefix}src=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
      else
        match
      end
    end

    # Rewrite ALL link href attributes (stylesheets, preloads, icons, etc.)
    html = html.gsub(/(<link[^>]*\s)href\s*=\s*["']([^"']+)["']/i) do |match|
      prefix = $1
      href = $2
      absolute_url = make_absolute.call(href)
      if absolute_url.start_with?("http")
        "#{prefix}href=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
      else
        match
      end
    end

    # Rewrite href for navigation links (to stay in proxy)
    html = html.gsub(/(<a[^>]*\s)href\s*=\s*["']([^"']+)["']/i) do |match|
      prefix = $1
      href = $2
      absolute_url = make_absolute.call(href)
      if absolute_url.start_with?("http")
        "#{prefix}href=\"#{proxy_base}#{CGI.escape(absolute_url)}\""
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
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    intercept_script = <<~SCRIPT
      <script>
        // Comprehensive proxy intercept for dynamic resource loading
        (function() {
          const proxyBase = '/web_proxy?url=';
          const originalBaseUrl = '#{base_url}';
          const currentOrigin = window.location.origin;
          
          // Store the base URL for this proxied page
          window.__PROXY_BASE_URL__ = originalBaseUrl;
          sessionStorage.setItem('__proxy_base_url__', originalBaseUrl);
          
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
            // If URL contains the proxy origin (app.localhost) but should be the original site
            if (url.includes(currentOrigin) && !url.includes('/web_proxy')) {
              // Extract the path and redirect to original domain
              const urlObj = new URL(url);
              return originalBaseUrl + urlObj.pathname + urlObj.search;
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
            if (url.startsWith('//')) {
              absoluteUrl = '#{base_uri.scheme}:' + url;
            } else if (url.startsWith('/')) {
              absoluteUrl = originalBaseUrl + url;
            } else if (url.startsWith('http://') || url.startsWith('https://')) {
              absoluteUrl = url;
            } else {
              // Relative URL - this shouldn't happen often for chunks
              absoluteUrl = originalBaseUrl + '/' + url;
            }
            
            return proxyBase + encodeURIComponent(absoluteUrl);
          }
          
          // Intercept fetch
          const originalFetch = window.fetch;
          window.fetch = function(input, options) {
            let url = typeof input === 'string' ? input : (input.url || input);
            if (typeof url === 'string') {
              if (url.startsWith('/') && !url.startsWith('/web_proxy')) {
                url = proxyUrl(url);
                if (typeof input === 'string') {
                  input = url;
                } else if (input.url) {
                  input = new Request(url, input);
                }
              } else if (url.startsWith('http') && !url.includes('/web_proxy')) {
                url = proxyBase + encodeURIComponent(url);
                if (typeof input === 'string') {
                  input = url;
                } else if (input.url) {
                  input = new Request(url, input);
                }
              }
            }
            return originalFetch.call(this, input, options);
          };
          
          // Intercept XMLHttpRequest
          const originalXHROpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url, ...rest) {
            if (typeof url === 'string') {
              if (url.startsWith('/') && !url.startsWith('/web_proxy')) {
                url = proxyUrl(url);
              } else if (url.startsWith('http') && !url.includes('/web_proxy')) {
                url = proxyBase + encodeURIComponent(url);
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
                    if (value.startsWith('/') && !value.startsWith('/web_proxy')) {
                      value = proxyUrl(value);
                    } else if (value.startsWith('http') && !value.includes('/web_proxy')) {
                      value = proxyBase + encodeURIComponent(value);
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
            if (form.action && form.action.startsWith('http')) {
              e.preventDefault();
              const newAction = proxyBase + encodeURIComponent(form.action);
              if (form.method.toLowerCase() === 'get') {
                const formData = new FormData(form);
                const params = new URLSearchParams(formData).toString();
                const url = form.action + (form.action.includes('?') ? '&' : '?') + params;
                window.location.href = proxyBase + encodeURIComponent(url);
              } else {
                form.action = newAction;
                form.submit();
              }
            }
          }, true);
          
          // Intercept script loading via document.write (some sites use this)
          const originalDocWrite = document.write.bind(document);
          document.write = function(html) {
            if (typeof html === 'string') {
              // Rewrite src attributes in the HTML
              html = html.replace(/\\ssrc=["'](\\/[^"']+)["']/gi, function(match, url) {
                return ' src="' + proxyUrl(url) + '"';
              });
              html = html.replace(/\\shref=["'](\\/[^"']+)["']/gi, function(match, url) {
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
    when ".mp3"
      "audio/mpeg"
    when ".wav"
      "audio/wav"
    else
      "text/html" # Default to HTML for unknown
    end
  rescue
    "text/html"
  end

  def rewrite_css_urls(css, base_uri)
    base_url = "#{base_uri.scheme}://#{base_uri.host}"
    proxy_base = "/web_proxy?url="

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
end
