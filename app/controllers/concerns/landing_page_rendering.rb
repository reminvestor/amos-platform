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
    inject_form_handling_script(clean_html, landing_page.slug)
  end
end
