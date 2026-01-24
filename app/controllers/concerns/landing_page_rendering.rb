# frozen_string_literal: true

# Shared concern for rendering landing page HTML content
# Used by both LandingPagesController and LpController
module LandingPageRendering
  extend ActiveSupport::Concern

  private

  # Remove all editing-related attributes and classes for clean preview/public view
  def strip_editing_attributes(html_content)
    clean_html = html_content.dup

    # Remove contenteditable attributes
    clean_html.gsub!(/\s*contenteditable\s*=\s*["']true["']/i, "")
    clean_html.gsub!(/\s*contenteditable\s*=\s*["']false["']/i, "")
    clean_html.gsub!(/\s*contenteditable/i, "")

    # Remove spellcheck attributes
    clean_html.gsub!(/\s*spellcheck\s*=\s*["']false["']/i, "")
    clean_html.gsub!(/\s*spellcheck\s*=\s*["']true["']/i, "")

    # Remove data-original-content attributes
    clean_html.gsub!(/\s*data-original-content\s*=\s*["'][^"']*["']/i, "")

    # Remove editing-related classes
    clean_html.gsub!(/\s*editable-text\s*/, " ")
    clean_html.gsub!(/\s*editable-image\s*/, " ")
    clean_html.gsub!(/\s*editable-element\s*/, " ")

    # FIX: Add 'animated' class to all 'animate-on-scroll' elements so they're visible
    # Without this, elements with animate-on-scroll have opacity:0 and stay invisible
    clean_html.gsub!(/class\s*=\s*["']([^"']*animate-on-scroll[^"']*)["']/) do |match|
      classes = $1
      if classes.include?("animated")
        match
      else
        "class=\"#{classes} animated\""
      end
    end

    # Clean up any double spaces left by class removal
    clean_html.gsub!(/\s+/, " ")
    clean_html.gsub!(/class\s*=\s*["']\s*["']/, "")

    clean_html
  end

  # Fix truncated HTML by ensuring proper structure
  def ensure_html_structure(html)
    result = html.dup

    # Close any unclosed script tags (common truncation issue)
    open_scripts = result.scan(/<script[^>]*>/i).count
    close_scripts = result.scan(%r{</script>}i).count
    if open_scripts > close_scripts
      (open_scripts - close_scripts).times do
        result += "\n</script>"
      end
      Rails.logger.warn "⚠️ Fixed #{open_scripts - close_scripts} unclosed script tag(s)"
    end

    # Close any unclosed style tags
    open_styles = result.scan(/<style[^>]*>/i).count
    close_styles = result.scan(%r{</style>}i).count
    if open_styles > close_styles
      (open_styles - close_styles).times do
        result += "\n</style>"
      end
      Rails.logger.warn "⚠️ Fixed #{open_styles - close_styles} unclosed style tag(s)"
    end

    # Close any unclosed form tags
    open_forms = result.scan(/<form[^>]*>/i).count
    close_forms = result.scan(%r{</form>}i).count
    if open_forms > close_forms
      (open_forms - close_forms).times do
        result += "\n</form>"
      end
      Rails.logger.warn "⚠️ Fixed #{open_forms - close_forms} unclosed form tag(s)"
    end

    # Close any unclosed select tags (common in truncated forms)
    open_selects = result.scan(/<select[^>]*>/i).count
    close_selects = result.scan(%r{</select>}i).count
    if open_selects > close_selects
      (open_selects - close_selects).times do
        result += "\n</select>"
      end
      Rails.logger.warn "⚠️ Fixed #{open_selects - close_selects} unclosed select tag(s)"
    end

    # Ensure </body> tag exists
    unless result.include?("</body>")
      result += "\n</body>"
      Rails.logger.warn "⚠️ Added missing </body> tag"
    end

    # Ensure </html> tag exists
    unless result.include?("</html>")
      result += "\n</html>"
      Rails.logger.warn "⚠️ Added missing </html> tag"
    end

    result
  end

  # Remove action and method attributes from forms to prevent native submission
  def sanitize_form_attributes(html)
    sanitized = html.dup

    # Remove action attributes from form tags
    # Match: action="...", action='...', action=...
    sanitized.gsub!(/(<form[^>]*)\s+action\s*=\s*["'][^"']*["']/i, '\1')
    sanitized.gsub!(/(<form[^>]*)\s+action\s*=\s*[^\s>]+/i, '\1')

    # Remove method attributes from form tags
    sanitized.gsub!(/(<form[^>]*)\s+method\s*=\s*["'][^"']*["']/i, '\1')
    sanitized.gsub!(/(<form[^>]*)\s+method\s*=\s*[^\s>]+/i, '\1')

    # Remove inline onsubmit handlers
    sanitized.gsub!(/(<form[^>]*)\s+onsubmit\s*=\s*["'][^"']*["']/i, '\1')

    # Also handle cases where attribute is right after <form (no space before)
    # e.g., <form action="..."> or <formmethod="...">
    sanitized.gsub!(/<form\s+action\s*=\s*["'][^"']*["']/i, "<form")
    sanitized.gsub!(/<form\s+method\s*=\s*["'][^"']*["']/i, "<form")

    Rails.logger.info "✅ Form attributes sanitized for preview"
    sanitized
  end

  # Inject JavaScript to handle form submissions
  # Uses safe DOM methods instead of innerHTML to prevent XSS
  def inject_form_handling_script(html, slug)
    # Skip if script is already present
    return html if html.include?("data-lp-form-handler")

    # First, strip any malformed scripts from AI output that could cause syntax errors
    cleaned_html = strip_malformed_scripts(html)

    # Use type="module" for complete isolation from other scripts on the page
    # Modules have their own scope and won't be affected by syntax errors in other scripts
    # Uses safe DOM creation methods instead of innerHTML
    form_script = <<~JAVASCRIPT
      <script type="module" data-lp-form-handler="true">
      try {
        const slug = "#{slug}";
        const isPreview = location.pathname.includes("/preview") || location.pathname.includes("/landing_pages/");

        function showSuccessMessage(form, message) {
          // Clear form content safely using DOM methods
          while (form.firstChild) {
            form.removeChild(form.firstChild);
          }

          // Create success container using safe DOM methods
          const container = document.createElement("div");
          container.style.cssText = "padding:20px;background:#d4edda;border:1px solid #c3e6cb;border-radius:8px;color:#155724";

          const heading = document.createElement("h4");
          heading.style.cssText = "margin:0 0 10px";
          heading.textContent = "Thank you!";

          const paragraph = document.createElement("p");
          paragraph.style.margin = "0";
          paragraph.textContent = message;

          container.appendChild(heading);
          container.appendChild(paragraph);
          form.appendChild(container);
        }

        function handleSubmit(form) {
          const data = new FormData(form);
          const btn = form.querySelector("button[type=submit], input[type=submit], button:not([type])");
          const origText = btn ? (btn.textContent || btn.value) : "";

          if (btn) {
            btn.disabled = true;
            btn.tagName === "BUTTON" ? btn.textContent = "Sending..." : btn.value = "Sending...";
          }

          let url = "/api/v1/landing_pages/" + slug + "/submit";
          if (isPreview) url += "?preview=true";

          fetch(url, { method: "POST", body: data, headers: { "X-Requested-With": "XMLHttpRequest" } })
            .then(r => r.json())
            .then(d => {
              if (d.success) {
                showSuccessMessage(form, d.message || "Your submission has been received.");
              } else {
                alert(d.message || "Error submitting form.");
                if (btn) { btn.disabled = false; btn.tagName === "BUTTON" ? btn.textContent = origText : btn.value = origText; }
              }
            })
            .catch(e => {
              console.error("Form error:", e);
              alert("Error submitting form. Please try again.");
              if (btn) { btn.disabled = false; btn.tagName === "BUTTON" ? btn.textContent = origText : btn.value = origText; }
            });
        }

        function init() {
          document.querySelectorAll("form:not([data-lp-bound])").forEach(form => {
            const action = form.getAttribute("action");
            if (action && action.startsWith("http")) return;

            form.removeAttribute("action");
            form.removeAttribute("method");
            form.setAttribute("data-lp-bound", "1");

            form.querySelectorAll("input,textarea,select").forEach(el => {
              if (!el.name && el.id) el.name = el.id;
            });

            form.addEventListener("submit", e => {
              e.preventDefault();
              e.stopPropagation();
              handleSubmit(form);
              return false;
            }, true);
          });
        }

        if (document.readyState === "loading") {
          document.addEventListener("DOMContentLoaded", init);
        } else {
          init();
        }
        window.addEventListener("load", init);
      } catch(e) { console.error("LP form handler:", e); }
      </script>
    JAVASCRIPT

    # Inject before </body> or at end
    if cleaned_html.include?("</body>")
      cleaned_html.sub("</body>", "#{form_script}\n</body>")
    else
      cleaned_html + form_script
    end
  end

  # Remove any script tags that contain obvious syntax issues
  def strip_malformed_scripts(html)
    result = html.dup

    # Find and validate each script tag
    result.gsub!(/<script[^>]*>(.*?)<\/script>/im) do |match|
      script_content = $1

      # Check for obviously incomplete code patterns
      incomplete_patterns = [
        /function\s+\w+\s*\([^)]*\)\s*\{\s*[^}]*\z/,  # Unclosed function
        /if\s*\([^)]*\)\s*\{\s*[^}]*\z/,              # Unclosed if
        /for\s*\([^)]*\)\s*\{\s*[^}]*\z/,             # Unclosed for
        /while\s*\([^)]*\)\s*\{\s*[^}]*\z/,           # Unclosed while
        /\{\s*[^}]*\z/,                               # Unclosed brace at end
        /['"][^'"]*\z/                                # Unclosed string
      ]

      is_malformed = incomplete_patterns.any? { |pattern| script_content.match?(pattern) }

      # Also check for balanced braces
      open_braces = script_content.count("{")
      close_braces = script_content.count("}")
      is_malformed ||= (open_braces != close_braces)

      if is_malformed
        Rails.logger.warn "⚠️ Removed malformed script tag (#{open_braces} open, #{close_braces} close braces)"
        "<!-- Removed malformed script -->"
      else
        match
      end
    end

    result
  end

  # Prepare landing page HTML for display
  # @param landing_page [LandingPage] The landing page to render
  # @return [String] Clean HTML ready for display
  def prepare_landing_page_html(landing_page)
    return nil unless landing_page.html_content.present?

    clean_html = strip_editing_attributes(landing_page.html_content)
    clean_html = ensure_html_structure(clean_html)
    clean_html = sanitize_form_attributes(clean_html)
    # CRITICAL: Refresh expired S3 signed URLs before rendering
    clean_html = refresh_signed_urls(clean_html)
    clean_html = inject_form_handling_script(clean_html, landing_page.slug)
    # Apply page-specific font if set
    inject_page_font(clean_html, landing_page.page_font)
  end

  # Inject Google Font stylesheet and CSS to apply a specific font
  # @param html [String] The HTML content
  # @param page_font [String] The Google Font name to inject
  # @return [String] HTML with font injected
  def inject_page_font(html, page_font)
    return html if page_font.blank?
    
    # Build the Google Font link and style tag
    font_link = "<link href=\"https://fonts.googleapis.com/css2?family=#{ERB::Util.url_encode(page_font)}:wght@300;400;500;600;700;800;900&display=swap\" rel=\"stylesheet\">"
    font_style = <<~CSS
      <style id="page-font-style">
        body, body * {
          font-family: '#{page_font}', sans-serif !important;
        }
        /* Allow icons to keep their font */
        i[class*="fa-"],
        [class*="icon"],
        .material-icons {
          font-family: inherit !important;
        }
      </style>
    CSS
    
    # Inject into <head> if present, otherwise prepend to html
    if html.include?('</head>')
      html.sub('</head>', "#{font_link}\n#{font_style}\n</head>")
    else
      "#{font_link}\n#{font_style}\n#{html}"
    end
  end

  # Refresh any expired or expiring Active Storage signed URLs in the HTML
  # This is necessary because signed URLs embedded in html_content expire after 1 week
  # @param html [String] HTML content potentially containing signed S3 URLs
  # @return [String] HTML with refreshed URLs
  def refresh_signed_urls(html)
    return html if html.blank?

    result = html.dup
    refreshed_count = 0
    failed_count = 0

    # Pattern to match Active Storage blob URLs (both redirect and representation variants)
    # Matches URLs like:
    # - /rails/active_storage/blobs/redirect/SIGNED_ID/filename
    # - /rails/active_storage/representations/redirect/SIGNED_ID/filename
    # - Full URLs with domain: https://example.com/rails/active_storage/blobs/...
    url_pattern = %r{
      (["']?)                                           # Optional opening quote
      (https?://[^/\s"']+)?                             # Optional domain
      /rails/active_storage/                            # Active Storage path
      (blobs|representations)/                          # Type (blobs or representations)
      (redirect|proxy)/                                 # Redirect or proxy
      ([A-Za-z0-9\-_=]+)                                # Signed ID (base64url encoded)
      (?:/[^"'\s>]*)?                                   # Optional filename/path
      (["']?)                                           # Optional closing quote
    }x

    result.gsub!(url_pattern) do |match|
      open_quote = $1
      domain = $2
      storage_type = $3
      redirect_type = $4
      signed_id = $5
      close_quote = $6

      begin
        # Try to find the blob using the signed ID
        blob = ActiveStorage::Blob.find_signed(signed_id)
        
        if blob
          # Use public S3 URL in production (permanent, no expiration)
          if Rails.env.production? && blob.service_name.to_s.include?('amazon')
            bucket = ENV.fetch('AWS_BUCKET', 'amos-labs-production')
            region = ENV.fetch('AWS_REGION', 'us-west-2')
            fresh_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{blob.key}"
          elsif blob.service.respond_to?(:url)
            # Fallback to presigned URL with max 7 days (S3 limit)
            fresh_url = blob.url(expires_in: 7.days)
          else
            # Local storage - use rails path
            fresh_url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
            if domain.present?
              fresh_url = "#{domain}#{fresh_url}"
            end
          end
          
          refreshed_count += 1
          "#{open_quote}#{fresh_url}#{close_quote}"
        else
          # Blob not found - leave URL as-is (will still fail but logs will help debug)
          Rails.logger.warn "⚠️ Could not find blob for signed_id: #{signed_id[0..20]}..."
          failed_count += 1
          match
        end
      rescue ActiveStorage::FileNotFoundError, ActiveRecord::RecordNotFound => e
        Rails.logger.warn "⚠️ Blob missing or deleted: #{e.message}"
        failed_count += 1
        match
      rescue => e
        Rails.logger.error "⚠️ Error refreshing URL: #{e.message}"
        failed_count += 1
        match
      end
    end

    if refreshed_count > 0 || failed_count > 0
      Rails.logger.info "🔄 Refreshed #{refreshed_count} signed URLs (#{failed_count} failed)"
    end

    result
  end
end
