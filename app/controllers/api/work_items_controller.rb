module Api
  class WorkItemsController < ApplicationController
    include ActionView::Helpers::SanitizeHelper
    include ActionView::Helpers::TextHelper
    
    before_action :authenticate_user!
    before_action :set_work_item
    
    # GET /api/work_items/:id/content
    def content
      # Build title with metadata
      title = @work_item.title
      subtitle = "#{@work_item.agent_name} • #{@work_item.time_ago}"
      
      # Get the content - could be HTML, markdown, JSON, or Ruby hash string
      details = @work_item.details
      html_content = nil
      
      if details.present?
        # First, try to extract the actual content from various formats
        extracted_content = extract_content_from_details(details)
        
        if extracted_content.present?
          if looks_like_html?(extracted_content)
            html_content = extracted_content
          else
            # Treat as markdown and convert to HTML
            html_content = render_markdown_to_html(extracted_content)
          end
        else
          # Fallback - render details as-is with markdown conversion
          if looks_like_html?(details)
            html_content = details
          else
            html_content = render_markdown_to_html(details)
          end
        end
      end
      
      # Don't add summary - it's usually redundant with the content
      # The content itself should be self-explanatory
      
      # Add metadata footer (including download button for files)
      metadata_html = build_metadata_html
      
      # Combine content - metadata should ALWAYS be shown if available (for download links, etc)
      if html_content.present?
        html_content = "#{html_content}#{metadata_html}"
      elsif metadata_html.present?
        # Even if no details, show metadata (download buttons, etc)
        html_content = metadata_html
      end
      
      # Add summary as fallback content if nothing else
      if html_content.blank? && @work_item.summary.present?
        html_content = "<p>#{@work_item.summary}</p>"
      end
      
      render json: {
        success: true,
        title: title,
        subtitle: subtitle,
        html_content: html_content
      }
    end
    
    # POST /api/work_items/:id/toggle_star
    def toggle_star
      @work_item.toggle_starred!
      render json: { success: true, starred: @work_item.starred? }
    end
    
    # POST /api/work_items/:id/archive
    def archive
      @work_item.archive!
      render json: { success: true, archived: true }
    end
    
    # POST /api/work_items/:id/mark_read
    def mark_read
      @work_item.mark_as_read!
      render json: { success: true, read: true }
    end
    
    # POST /api/work_items/:id/mark_unread
    def mark_unread
      @work_item.mark_as_unread!
      render json: { success: true, read: false }
    end
    
    private
    
    def set_work_item
      @work_item = AgentWorkItem.find_by!(
        id: params[:id],
        user: current_user,
        entity: current_entity
      )
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Work item not found' }, status: :not_found
    end
    
    def extract_content_from_details(raw_details)
      return nil unless raw_details.present?
      
      details = raw_details.to_s.strip
      
      # Strategy 1: Try to parse as proper JSON
      begin
        if details.start_with?('{', '[')
          parsed = JSON.parse(details)
          content = extract_from_parsed(parsed)
          return unescape_content(content) if content.present?
        end
      rescue JSON::ParserError
        # Not valid JSON, continue to other extraction methods
      end
      
      # Strategy 2: Handle Ruby hash-like strings {message: "...", key: value}
      # These are common when Ruby hashes are stringified with .to_s or .inspect
      if details.start_with?('{') && details.include?('message')
        content = extract_message_from_ruby_hash_string(details)
        return unescape_content(content) if content.present?
      end
      
      # Strategy 3: If it looks like plain markdown/text, return as-is
      if looks_like_markdown?(details)
        return details
      end
      
      # Strategy 4: Return the raw content as a last resort
      # (better to show something than nothing)
      details
    end
    
    def extract_from_parsed(parsed)
      return nil unless parsed.is_a?(Hash)
      
      # Check for nested content structures
      # Format: {"content": {"message": "..."}} 
      if parsed['content'].is_a?(Hash)
        return parsed['content']['html_content'] || 
               parsed['content']['message'] || 
               parsed['content']['content']
      end
      
      # Format: {"content": "..."} or {"message": "..."} or {"html_content": "..."}
      parsed['html_content'] || parsed['message'] || parsed['content']
    end
    
    def extract_message_from_ruby_hash_string(details)
      # Ruby hash strings look like: {message: "content here", key: value}
      # The challenge is that the message content can contain escaped quotes
      
      # Find where the message value starts
      start_match = details.match(/message:\s*"/)
      return nil unless start_match
      
      start_pos = start_match.end(0)
      
      # Now find the end of the message string
      # We need to handle escaped quotes \" inside the string
      content = ""
      i = start_pos
      while i < details.length
        char = details[i]
        
        if char == '\\'
          # Escape sequence - take the next character literally
          if i + 1 < details.length
            next_char = details[i + 1]
            if next_char == 'n'
              content += "\n"
            elsif next_char == '"'
              content += '"'
            elsif next_char == '\\'
              content += '\\'
            else
              content += next_char
            end
            i += 2
          else
            i += 1
          end
        elsif char == '"'
          # End of string
          break
        else
          content += char
          i += 1
        end
      end
      
      content.presence
    end
    
    def unescape_content(content)
      return nil unless content.present?
      
      # Handle various escape sequences that might still be present
      content
        .gsub(/\\n/, "\n")
        .gsub(/\\"/, '"')
        .gsub(/\\'/, "'")
        .gsub(/\\u0026/, '&')
        .gsub(/\\u003c/, '<')
        .gsub(/\\u003e/, '>')
    end
    
    def looks_like_markdown?(text)
      return false unless text.present?
      
      # Check if it starts with markdown indicators
      text.strip.start_with?('#') ||
        text.include?('##') ||
        (text.include?('**') && !text.start_with?('{'))
    end
    
    def looks_like_html?(text)
      return false unless text.present?
      text.include?('<div') || text.include?('<table') || text.include?('<p>') || 
        text.include?('<h1') || text.include?('<h2') || text.include?('<ul') ||
        text.include?('<ol') || text.include?('<section')
    end
    
    def render_markdown_to_html(markdown_text)
      return "" unless markdown_text.present?
      
      # Use Redcarpet for proper markdown rendering
      renderer = Redcarpet::Render::HTML.new(
        hard_wrap: true,
        link_attributes: { target: "_blank", rel: "noopener noreferrer" }
      )
      
      markdown = Redcarpet::Markdown.new(
        renderer,
        autolink: true,
        tables: true,
        fenced_code_blocks: true,
        lax_spacing: true,
        no_intra_emphasis: true,
        strikethrough: true,
        superscript: true,
        highlight: true,
        quote: true
      )
      
      # Render markdown to HTML and sanitize
      html = markdown.render(markdown_text)
      
      # Sanitize the output
      sanitize(
        html,
        tags: %w[p h1 h2 h3 h4 h5 h6 em strong b i u br hr ul ol li div span a img blockquote code pre table thead tbody tr th td],
        attributes: {
          'a' => ['href', 'title', 'target', 'rel'],
          'img' => ['src', 'alt', 'width', 'height', 'loading'],
          'div' => ['class', 'id', 'style'],
          'span' => ['class', 'id', 'style'],
          'table' => ['class'],
          'td' => ['colspan', 'rowspan'],
          'th' => ['colspan', 'rowspan'],
          '*' => ['class', 'id']
        }
      )
    end
    
    def format_work_item_content(data)
      # Format structured data as readable markdown
      lines = []
      
      data.each do |key, value|
        next if key.in?(%w[html_content content])
        
        formatted_key = key.to_s.titleize
        if value.is_a?(Array)
          lines << "**#{formatted_key}:**"
          value.each { |v| lines << "- #{v}" }
        elsif value.is_a?(Hash)
          lines << "**#{formatted_key}:**"
          value.each { |k, v| lines << "- #{k.to_s.titleize}: #{v}" }
        else
          lines << "**#{formatted_key}:** #{value}"
        end
        lines << ""
      end
      
      lines.join("\n")
    end
    
    def build_metadata_html
      return "" unless @work_item.metadata.present? && @work_item.metadata.any?
      
      # Access metadata with indifferent access (handles both string and symbol keys)
      metadata = @work_item.metadata.with_indifferent_access
      
      Rails.logger.info "📄 [WorkItemContent] Building metadata HTML for work item #{@work_item.id}"
      Rails.logger.info "📄 [WorkItemContent] Metadata keys: #{metadata.keys.inspect}"
      Rails.logger.info "📄 [WorkItemContent] download_url present: #{metadata['download_url'].present?}"
      
      html = "<hr style='border-color: rgba(255,255,255,0.2); margin: 2rem 0;'>"
      
      # Show download button if there's a file attached
      if metadata['download_url'].present?
        filename = metadata['filename'] || 'Download File'
        format = metadata['format']&.upcase || 'FILE'
        download_url = metadata['download_url']
        
        # Use explicit inline styles to ensure the button is clickable and styled correctly
        # The dynamic canvas CSS has a `*` selector that overrides colors
        html += "<div style='margin-bottom: 1.5rem; text-align: center;'>"
        html += "<a href='#{download_url}' download "
        html += "style='display: inline-flex; align-items: center; gap: 8px; "
        html += "padding: 12px 24px; background-color: #198754; color: #fff !important; "
        html += "border-radius: 8px; text-decoration: none; font-weight: 600; font-size: 1rem; "
        html += "cursor: pointer; transition: background-color 0.2s; border: none;' "
        html += "onmouseover=\"this.style.backgroundColor='#157347'\" "
        html += "onmouseout=\"this.style.backgroundColor='#198754'\">"
        html += "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'/><polyline points='7 10 12 15 17 10'/><line x1='12' y1='15' x2='12' y2='3'/></svg>"
        html += "Download #{format}"
        html += "</a>"
        html += "<div style='margin-top: 0.5rem; font-size: 0.875rem; color: rgba(255,255,255,0.6);'>#{filename}</div>"
        html += "</div>"
      end
      
      html += "<div style='font-size: 0.875rem; color: rgba(255,255,255,0.7);'>"
      
      if metadata['tools_used'].present?
        tools = metadata['tools_used'].map { |t| "<span class='badge bg-secondary me-1'>#{t}</span>" }.join
        html += "<div class='mb-2'><strong>Tools Used:</strong> #{tools}</div>"
      end
      
      if metadata['task_type'].present?
        html += "<div class='mb-2'><strong>Task Type:</strong> #{metadata['task_type'].titleize}</div>"
      end
      
      # Show row count if present
      if metadata['row_count'].present?
        html += "<div class='mb-2'><strong>Rows:</strong> #{metadata['row_count']}</div>"
      end
      
      # Show sheet count if present (for Excel)
      if metadata['sheet_count'].present?
        html += "<div class='mb-2'><strong>Sheets:</strong> #{metadata['sheet_count']}</div>"
      end
      
      html += "</div>"
      html
    end
    
    def build_metadata_markdown
      return "" unless @work_item.metadata.present? && @work_item.metadata.any?
      
      metadata = @work_item.metadata.with_indifferent_access
      lines = ["---", ""]
      
      if metadata['tools_used'].present?
        lines << "**Tools Used:** #{metadata['tools_used'].join(', ')}"
      end
      
      if metadata['task_type'].present?
        lines << "**Task Type:** #{metadata['task_type'].titleize}"
      end
      
      lines.join("\n")
    end
  end
end

