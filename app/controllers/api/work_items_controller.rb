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
      
      # Check if there's a pending input request for this work item
      # The input_request_id is stored in asset_data when the work item is created
      input_request = nil
      asset_data = @work_item.asset_data&.with_indifferent_access || {}
      
      # First, try to find by input_request_id in asset_data
      if asset_data['input_request_id'].present?
        input_request = AgentInputRequest.find_by(
          id: asset_data['input_request_id'],
          status: 'pending'
        )
      end
      
      # Fallback: try to find by execution_id in asset_data
      if input_request.nil? && asset_data['execution_id'].present?
        input_request = AgentInputRequest.where(
          agent_plugin_execution_id: asset_data['execution_id'],
          status: 'pending'
        ).first
      end
      
      # Final fallback: try agent_plugin_execution_id on work item
      if input_request.nil? && @work_item.agent_plugin_execution_id.present?
        input_request = AgentInputRequest.where(
          agent_plugin_execution_id: @work_item.agent_plugin_execution_id,
          status: 'pending'
        ).first
      end
      
      # Add response form if there's a pending input request
      if input_request.present?
        html_content ||= ""
        html_content += build_response_form(input_request)
      end
      
      # Include file info for header action buttons
      file_info = nil
      if asset_data['download_url'].present? || @work_item.metadata&.dig('download_url').present?
        metadata = @work_item.metadata&.with_indifferent_access || {}
        file_info = {
          download_url: metadata['download_url'],
          filename: metadata['filename'],
          format: metadata['format'],
          saved_to_documents: metadata['saved_to_documents'] == true,
          work_item_id: @work_item.id
        }
      end
      
      render json: {
        success: true,
        title: title,
        subtitle: subtitle,
        html_content: html_content,
        has_pending_input: input_request.present?,
        input_request_id: input_request&.id,
        file_info: file_info
      }
    end
    
    # POST /api/work_items/:id/respond
    def respond_to_input
      # Find the pending input request for this work item
      input_request = find_pending_input_request
      
      unless input_request
        return render json: { success: false, error: 'No pending input request found for this work item' }, status: :not_found
      end
      
      response_content = params[:response]&.strip
      if response_content.blank?
        return render json: { success: false, error: 'Response cannot be empty' }, status: :unprocessable_entity
      end
      
      # Answer the input request (this will broadcast updates and resume execution)
      input_request.answer!(response_content)
      
      # Mark the work item as no longer requiring action
      @work_item.update(requires_action: false)
      
      # Broadcast update to work inbox
      broadcast_work_inbox_update
      
      render json: { 
        success: true, 
        message: 'Response submitted successfully',
        input_request_id: input_request.id
      }
    rescue => e
      Rails.logger.error "Error responding to input: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
    
    # POST /api/work_items/:id/skip_input
    def skip_input
      # Find the pending input request for this work item
      input_request = find_pending_input_request
      
      unless input_request
        return render json: { success: false, error: 'No pending input request found for this work item' }, status: :not_found
      end
      
      # Skip the input request
      input_request.skip!(reason: 'Skipped from work inbox')
      
      # Mark the work item as no longer requiring action
      @work_item.update(requires_action: false)
      
      render json: { success: true, message: 'Input skipped' }
    rescue => e
      Rails.logger.error "Error skipping input: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
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
    
    # POST /api/work_items/:id/save_to_documents
    # Save an exported file (CSV, Excel, PDF) to the Document Store for Scout to query
    def save_to_documents
      metadata = @work_item.metadata&.with_indifferent_access || {}
      download_url = metadata['download_url']
      filename = metadata['filename'] || "export_#{@work_item.id}"
      format = metadata['format']&.downcase || 'csv'
      
      unless download_url.present?
        return render json: { 
          success: false, 
          error: 'No downloadable file attached to this work item' 
        }, status: :unprocessable_entity
      end
      
      begin
        # Download the file - handle both relative Active Storage URLs and full S3 URLs
        Rails.logger.info "📥 Downloading file from: #{download_url}"
        
        file_content = nil
        
        if download_url.start_with?('/') || download_url.start_with?('http://localhost') || download_url.include?('active_storage')
          # This is an Active Storage URL - we need to find the blob and download directly
          # Extract blob ID from the URL if possible, or find via work item's associated export
          
          # Try to find the DataExport associated with this work item
          export_id = metadata['export_id'] || metadata['work_item_id']
          data_export = DataExport.find_by(id: export_id) if export_id.present?
          
          if data_export&.file&.attached?
            Rails.logger.info "📥 Found DataExport ##{data_export.id} with attached file"
            file_content = data_export.file.download
          else
            # Try to find by matching filename in recent exports
            recent_export = DataExport.where(entity: current_entity, user: current_user)
                                      .where('created_at > ?', 1.hour.ago)
                                      .order(created_at: :desc)
                                      .find { |e| e.file.attached? && e.file.filename.to_s == filename }
            
            if recent_export&.file&.attached?
              Rails.logger.info "📥 Found recent DataExport by filename: #{filename}"
              file_content = recent_export.file.download
            else
              # Last resort: try to follow the redirect and download
              Rails.logger.info "📥 Attempting to download via HTTP from relative URL"
              base_url = ENV['APP_HOST'] || "http://localhost:3000"
              full_url = download_url.start_with?('http') ? download_url : "#{base_url}#{download_url}"
              
              uri = URI.parse(full_url)
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = (uri.scheme == 'https')
              http.open_timeout = 10
              http.read_timeout = 30
              
              # Follow redirects (Active Storage uses redirects)
              max_redirects = 5
              current_uri = uri
              max_redirects.times do
                request = Net::HTTP::Get.new(current_uri.request_uri)
                response = http.request(request)
                
                if response.is_a?(Net::HTTPRedirection)
                  redirect_url = response['location']
                  current_uri = URI.parse(redirect_url)
                  http = Net::HTTP.new(current_uri.host, current_uri.port)
                  http.use_ssl = (current_uri.scheme == 'https')
                elsif response.is_a?(Net::HTTPSuccess)
                  file_content = response.body
                  break
                else
                  raise "HTTP #{response.code}: #{response.message}"
                end
              end
            end
          end
        else
          # Full external URL (S3, etc.)
          uri = URI.parse(download_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.open_timeout = 10
          http.read_timeout = 30
          
          request = Net::HTTP::Get.new(uri.request_uri)
          response = http.request(request)
          
          unless response.is_a?(Net::HTTPSuccess)
            return render json: { 
              success: false, 
              error: "Failed to download file: HTTP #{response.code}" 
            }, status: :unprocessable_entity
          end
          
          file_content = response.body
        end
        
        unless file_content.present?
          return render json: { 
            success: false, 
            error: 'Could not download file content' 
          }, status: :unprocessable_entity
        end
        
        file_hash = Digest::SHA256.hexdigest(file_content)
        
        # Determine content type
        content_type = case format
        when 'csv' then 'text/csv'
        when 'xlsx', 'excel' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        when 'pdf' then 'application/pdf'
        else 'application/octet-stream'
        end
        
        # Find or create a RagStore for work item exports
        rag_store = RagStore.find_or_create_by!(
          entity: current_entity,
          app_name: 'Work Item Exports'
        ) do |store|
          store.name = 'Work Item Exports'
          store.store_type = 'entity'
          store.pinecone_index = "amos-rag-#{Rails.env}"
          store.pinecone_namespace = "entity_#{current_entity.id}_exports"
          store.status = 'active'
        end
        
        # Check if document already exists (by file hash)
        existing_doc = rag_store.rag_documents.find_by(file_hash: file_hash)
        if existing_doc
          return render json: {
            success: true,
            message: 'This file is already in your Document Store',
            document_id: existing_doc.id,
            already_exists: true
          }
        end
        
        # Create a temp file to attach
        extension = ".#{format}"
        temp_file = Tempfile.new([filename, extension])
        temp_file.binmode
        temp_file.write(file_content)
        temp_file.rewind
        
        # Create the RagDocument
        rag_document = rag_store.rag_documents.create!(
          original_filename: "#{filename}#{extension}",
          file_hash: file_hash,
          content_type: content_type,
          file_size_bytes: file_content.bytesize,
          processing_status: 'pending',
          metadata: {
            source: 'work_item_export',
            work_item_id: @work_item.id,
            agent_name: @work_item.agent_name,
            exported_at: @work_item.created_at,
            row_count: metadata['row_count'],
            column_count: metadata['column_count']
          }.compact
        )
        
        # Attach the file using Active Storage
        rag_document.file.attach(
          io: temp_file,
          filename: "#{filename}#{extension}",
          content_type: content_type
        )
        
        temp_file.close
        temp_file.unlink
        
        # Queue for processing (chunking and embedding)
        Rag::DocumentPipelineJob.perform_later(rag_document.id)
        
        # Update work item metadata to track that it was saved
        @work_item.update!(
          metadata: @work_item.metadata.merge(
            'saved_to_documents' => true,
            'rag_document_id' => rag_document.id,
            'saved_at' => Time.current.iso8601
          )
        )
        
        Rails.logger.info "✅ Saved work item #{@work_item.id} to Document Store as document #{rag_document.id}"
        
        render json: {
          success: true,
          message: 'File saved to Document Store! Scout can now search and analyze this data.',
          document_id: rag_document.id,
          document_name: rag_document.original_filename
        }
        
      rescue StandardError => e
        Rails.logger.error "❌ Failed to save work item to documents: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        render json: { 
          success: false, 
          error: "Failed to save file: #{e.message}" 
        }, status: :internal_server_error
      end
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
    
    def find_pending_input_request
      asset_data = @work_item.asset_data&.with_indifferent_access || {}
      Rails.logger.info "🔍 [WorkItem] Finding input request for work item #{@work_item.id}"
      Rails.logger.info "🔍 [WorkItem] asset_data: #{asset_data.inspect}"
      
      # First, try to find by input_request_id in asset_data
      if asset_data['input_request_id'].present?
        Rails.logger.info "🔍 [WorkItem] Looking up by input_request_id: #{asset_data['input_request_id']}"
        request = AgentInputRequest.find_by(id: asset_data['input_request_id'])
        if request
          Rails.logger.info "🔍 [WorkItem] Found input request #{request.id} with status: #{request.status}"
          return request if request.status == 'pending'
          Rails.logger.info "🔍 [WorkItem] Input request not pending (status: #{request.status})"
        end
      end
      
      # Fallback: try to find by execution_id in asset_data
      if asset_data['execution_id'].present?
        Rails.logger.info "🔍 [WorkItem] Looking up by execution_id: #{asset_data['execution_id']}"
        request = AgentInputRequest.where(
          agent_plugin_execution_id: asset_data['execution_id'],
          status: 'pending'
        ).first
        return request if request
      end
      
      # Final fallback: try agent_plugin_execution_id on work item
      if @work_item.agent_plugin_execution_id.present?
        Rails.logger.info "🔍 [WorkItem] Looking up by agent_plugin_execution_id: #{@work_item.agent_plugin_execution_id}"
        AgentInputRequest.where(
          agent_plugin_execution_id: @work_item.agent_plugin_execution_id,
          status: 'pending'
        ).first
      end
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
      
      # Show action buttons if there's a file attached
      if metadata['download_url'].present?
        filename = metadata['filename'] || 'Download File'
        format = metadata['format']&.upcase || 'FILE'
        download_url = metadata['download_url']
        already_saved = metadata['saved_to_documents'] == true
        
        # Button container with both actions
        html += "<div style='margin-bottom: 1.5rem; text-align: center;'>"
        html += "<div style='display: flex; justify-content: center; gap: 12px; flex-wrap: wrap;'>"
        
        # Download button
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
        
        # Save to Document Store button
        if already_saved
          html += "<button type='button' disabled "
          html += "style='display: inline-flex; align-items: center; gap: 8px; "
          html += "padding: 12px 24px; background-color: #6c757d; color: #fff !important; "
          html += "border-radius: 8px; font-weight: 600; font-size: 1rem; "
          html += "cursor: not-allowed; border: none; opacity: 0.7;'>"
          html += "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polyline points='20 6 9 17 4 12'/></svg>"
          html += "Saved to Documents"
          html += "</button>"
        else
          html += "<button type='button' onclick='saveWorkItemToDocuments(#{@work_item.id}, this)' "
          html += "style='display: inline-flex; align-items: center; gap: 8px; "
          html += "padding: 12px 24px; background-color: #6366f1; color: #fff !important; "
          html += "border-radius: 8px; font-weight: 600; font-size: 1rem; "
          html += "cursor: pointer; transition: background-color 0.2s; border: none;' "
          html += "onmouseover=\"this.style.backgroundColor='#4f46e5'\" "
          html += "onmouseout=\"this.style.backgroundColor='#6366f1'\">"
          html += "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z'/><polyline points='14 2 14 8 20 8'/><line x1='12' y1='18' x2='12' y2='12'/><line x1='9' y1='15' x2='15' y2='15'/></svg>"
          html += "Save to Documents"
          html += "</button>"
        end
        
        html += "</div>"
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
    
    def build_response_form(input_request)
      # Note: The JavaScript functions (submitWorkItemResponse, skipWorkItemInput) are defined
      # globally in _work_inbox.html.erb since inline scripts in innerHTML don't execute
      <<~HTML
        <div class="input-response-form" style="margin-top: 1.5rem; padding: 1rem; background: rgba(99, 102, 241, 0.1); border: 1px solid rgba(99, 102, 241, 0.3); border-radius: 12px;">
          <div style="font-size: 0.9rem; color: rgba(255,255,255,0.8); margin-bottom: 0.75rem;">
            <strong>🔔 Waiting for your response</strong>
          </div>
          <textarea 
            id="work-item-response-#{@work_item.id}" 
            class="form-control work-item-response-input" 
            placeholder="Type your response..."
            rows="3"
            style="background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.2); color: #fff; resize: none; margin-bottom: 0.75rem;"
          ></textarea>
          <div style="display: flex; justify-content: flex-end; gap: 0.5rem;">
            <button 
              type="button" 
              class="btn btn-outline-secondary btn-sm work-item-skip-btn"
              data-work-item-id="#{@work_item.id}"
              data-input-request-id="#{input_request.id}"
              onclick="skipWorkItemInput(#{@work_item.id})"
              style="color: rgba(255,255,255,0.7); border-color: rgba(255,255,255,0.3);">
              Skip
            </button>
            <button 
              type="button" 
              class="btn btn-primary btn-sm work-item-respond-btn"
              data-work-item-id="#{@work_item.id}"
              onclick="submitWorkItemResponse(#{@work_item.id})"
              style="background: #6366f1; border-color: #6366f1;">
              <i data-lucide="send" style="width: 14px; height: 14px; margin-right: 4px;"></i>
              Send Response
            </button>
          </div>
        </div>
      HTML
    end
    
    def broadcast_work_inbox_update
      # Broadcast to ActionCable if available
      if defined?(ScoutChannel)
        session_id = session[:scout_session_id]
        if session_id.present?
          ScoutChannel.broadcast_to(session_id, {
            type: 'work_inbox_update',
            action: 'response_sent',
            work_item_id: @work_item.id
          })
        end
      end
    end
  end
end

