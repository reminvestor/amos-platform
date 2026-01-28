# frozen_string_literal: true

module Amos
  # ResponseHtmlProcessor - Detects HTML in AI responses and routes to canvas
  #
  # When Amos outputs HTML directly in a response (instead of calling create_freeform_canvas),
  # this processor detects it and:
  # 1. Extracts the HTML content
  # 2. Converts it to a canvas suggestion
  # 3. Cleans the chat message to show a summary
  #
  # This takes the burden off the AI to always remember to use tools for HTML.
  #
  class ResponseHtmlProcessor
    # HTML patterns that indicate significant HTML content (not just simple formatting)
    SIGNIFICANT_HTML_PATTERNS = [
      /<div[^>]*>/i,
      /<table[^>]*>/i,
      /<ul[^>]*>/i,
      /<ol[^>]*>/i,
      /<section[^>]*>/i,
      /<article[^>]*>/i,
      /<h[1-6][^>]*>/i,
      /<card[^>]*>/i,
      /<strong>[^<]{20,}/i,  # Long content in strong tags
      /<li>[^<]{10,}/i,      # List items with content
    ].freeze

    # Minimum HTML content length to trigger canvas
    MIN_HTML_LENGTH = 200

    # Tags that indicate data display (tables, lists with items, cards)
    DATA_DISPLAY_PATTERNS = [
      /<table/i,
      /<tbody/i,
      /<ul>\s*<li>/i,
      /<ol>\s*<li>/i,
      /class=['"]card/i,
      /class=['"]row/i,
      /class=['"]container/i,
    ].freeze

    class << self
      # Process a response and extract HTML if present
      # Returns: { content: cleaned_content, canvas_suggestion: canvas_data or nil }
      def process(content, metadata = {})
        return { content: content, canvas_suggestion: nil } if content.blank?

        # Check if this response contains significant HTML
        html_match = detect_significant_html(content)
        
        if html_match
          Rails.logger.info "[ResponseHtmlProcessor] Detected HTML in response, extracting to canvas"
          extract_html_to_canvas(content, html_match, metadata)
        else
          { content: content, canvas_suggestion: nil }
        end
      end

      private

      def detect_significant_html(content)
        # First check if there's any HTML at all
        return nil unless content.match?(/<[a-zA-Z][^>]*>/)
        
        # Check for significant HTML patterns
        has_significant_html = SIGNIFICANT_HTML_PATTERNS.any? { |pattern| content.match?(pattern) }
        return nil unless has_significant_html

        # Extract the HTML portion
        html_content = extract_html_portion(content)
        return nil unless html_content && html_content.length >= MIN_HTML_LENGTH

        # Check if it's data display content
        is_data_display = DATA_DISPLAY_PATTERNS.any? { |pattern| html_content.match?(pattern) }
        
        {
          html: html_content,
          is_data_display: is_data_display,
          length: html_content.length
        }
      end

      def extract_html_portion(content)
        # Try to extract the HTML portion from mixed content
        # Look for content between the first significant tag and last closing tag
        
        # Find where HTML starts (first significant tag)
        first_tag_match = content.match(/<(div|table|ul|ol|section|article|h[1-6])[^>]*>/i)
        return nil unless first_tag_match

        start_idx = first_tag_match.begin(0)
        
        # Find where HTML ends (try to find matching closing tag or last closing tag)
        tag_name = first_tag_match[1].downcase
        
        # Simple approach: find the last occurrence of common closing tags
        last_close_idx = [
          content.rindex('</div>'),
          content.rindex('</table>'),
          content.rindex('</ul>'),
          content.rindex('</ol>'),
          content.rindex('</section>'),
          content.rindex('</article>'),
        ].compact.max

        return nil unless last_close_idx

        # Add the length of the closing tag
        end_idx = last_close_idx + 6 + (content[last_close_idx..last_close_idx + 20].match(/<\/(\w+)>/)[1].length rescue 3)
        
        content[start_idx..end_idx]
      end

      def extract_html_to_canvas(content, html_match, metadata)
        html_content = html_match[:html]
        
        # Extract a title from the content if possible
        title = extract_title(content, html_content)
        
        # Create a clean message without the HTML
        clean_message = create_clean_message(content, html_content, title)
        
        # Build canvas suggestion
        canvas_suggestion = {
          canvas: 'freeform_canvas',
          canvas_data: {
            title: title,
            html: wrap_html_with_bootstrap(html_content),
            css: '',
            javascript: '',
            library_scripts: '',
            library_css: '',
            data_script: '',
            artifact_type: 'auto_extracted_visualization'
          }
        }

        Rails.logger.info "[ResponseHtmlProcessor] Extracted #{html_match[:length]} chars of HTML, title: #{title}"

        {
          content: clean_message,
          canvas_suggestion: canvas_suggestion
        }
      end

      def extract_title(content, html_content)
        # Try to find a title from heading tags
        if heading_match = html_content.match(/<h[1-3][^>]*>([^<]+)<\/h[1-3]>/i)
          return heading_match[1].strip.truncate(50)
        end
        
        # Try to find a title from text before the HTML
        before_html_idx = content.index(html_content) || 0
        before_text = content[0...before_html_idx].strip
        
        if before_text.present?
          # Look for a colon pattern like "Here's your timeline:"
          if colon_match = before_text.match(/(?:here'?s?|showing|displaying|created?)\s+(?:your?\s+)?(.+?):/i)
            return colon_match[1].strip.titleize.truncate(50)
          end
          
          # Just use the last line as title
          last_line = before_text.split("\n").last&.strip
          if last_line && last_line.length < 60 && last_line.length > 5
            return last_line.gsub(/[:\.]$/, '').titleize
          end
        end
        
        # Default title
        "Visualization"
      end

      def create_clean_message(content, html_content, title)
        # Remove the HTML from the content
        clean = content.gsub(html_content, '').strip
        
        # If there's remaining text, use it
        if clean.present? && clean.length > 10
          # Add a note about the canvas
          "#{clean}\n\n📊 *I've displayed the #{title.downcase} in a canvas for you.*"
        else
          # Generate a simple message
          "📊 *I've created a visual #{title.downcase} for you - check the canvas!*"
        end
      end

      def wrap_html_with_bootstrap(html)
        # Ensure the HTML is wrapped properly for the canvas
        if html.match?(/class=['"]container/i)
          html
        else
          "<div class=\"container py-4\">#{html}</div>"
        end
      end
    end
  end
end
