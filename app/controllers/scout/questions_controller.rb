# frozen_string_literal: true

module Scout
  class QuestionsController < ApplicationController
    before_action :authenticate_user!, except: [:broadcast_question]
    before_action :set_question, only: [:answer, :skip]
    
    # Skip CSRF for internal worker-to-web callbacks
    skip_before_action :verify_authenticity_token, only: [:broadcast_question, :broadcast_completion]

    # GET /scout/questions/pending
    def pending
      # Get pending questions for this user's session
      session_id = params[:session_id] || session[:scout_session_id]
      
      questions = AgentInputRequest.joins(agent_plugin_execution: :user)
                                   .where(agent_plugin_executions: { user_id: current_user.id })
                                   .active
                                   .by_priority

      # Filter by session if provided
      if session_id.present?
        questions = questions.for_session(session_id)
      end

      render json: {
        success: true,
        questions: questions.map(&:as_queue_json),
        count: questions.count
      }
    end

    # POST /scout/questions/:id/answer
    def answer
      answer_content = params[:answer]
      attachment = params[:attachment]
      
      # Allow empty answer if there's an attachment
      if answer_content.blank? && attachment.blank?
        render json: { success: false, error: "Answer cannot be empty" }, status: :unprocessable_entity
        return
      end

      # Handle attachment if present
      attachment_info = nil
      if attachment.present?
        attachment_info = process_answer_attachment(attachment)
        Rails.logger.info "📎 Answer includes attachment: #{attachment_info[:filename]}"
      end

      # Build the full answer with attachment reference and extracted content
      full_answer = answer_content.to_s
      if attachment_info
        full_answer += "\n\n[Attached: #{attachment_info[:filename]}]"
        full_answer += "\n[Attachment URL: #{attachment_info[:url]}]" if attachment_info[:url]
        
        # Include extracted content so the agent can understand the file
        if attachment_info[:extracted_content].present?
          full_answer += "\n\n📄 **Attachment Content:**\n#{attachment_info[:extracted_content]}"
          Rails.logger.info "📎 Including extracted content (#{attachment_info[:filename]}) in answer to agent"
        end
      end

      @question.answer!(full_answer, attachment: attachment_info)
      
      Rails.logger.info "✅ User #{current_user.id} answered question #{@question.id}"
      
      render json: {
        success: true,
        message: "Answer submitted",
        question_id: @question.id,
        has_attachment: attachment_info.present?
      }
    rescue => e
      Rails.logger.error "Failed to answer question #{@question.id}: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /scout/questions/:id/skip
    def skip
      reason = params[:reason]
      
      @question.skip!(reason: reason)
      
      Rails.logger.info "⏭️ User #{current_user.id} skipped question #{@question.id}"
      
      render json: {
        success: true,
        message: "Question skipped",
        question_id: @question.id
      }
    rescue => e
      Rails.logger.error "Failed to skip question #{@question.id}: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /scout/broadcast_question
    # Internal endpoint for workers to trigger ActionCable broadcasts
    # This bypasses the cross-process ActionCable/Redis issue
    def broadcast_question
      session_id = params[:session_id]
      question_data = params[:question]
      pending_count = params[:pending_count]
      
      Rails.logger.info "📡 [BroadcastQuestion] Received callback for session #{session_id}"
      Rails.logger.info "📡 [BroadcastQuestion] Question: #{question_data[:id]} from #{question_data[:agent_name]}"
      
      unless session_id.present? && question_data.present?
        render json: { success: false, error: "Missing session_id or question data" }, status: :bad_request
        return
      end
      
      # Convert question_data to a regular hash if it's ActionController::Parameters
      question_hash = case question_data
                      when ActionController::Parameters
                        question_data.permit!.to_h
                      when Hash
                        question_data
                      else
                        question_data.to_h
                      end
      
      # Broadcast via ActionCable from the web process (this works!)
      ScoutChannel.broadcast_to(session_id, {
        type: 'question_queue_update',
        action: 'added',
        question: question_hash,
        pending_count: pending_count || 1
      })
      
      Rails.logger.info "📡 [BroadcastQuestion] ✅ Broadcasted question_queue_update via ActionCable"
      
      render json: { success: true, message: "Broadcast sent" }
    rescue => e
      Rails.logger.error "📡 [BroadcastQuestion] ❌ Failed: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
    
    # POST /scout/broadcast_completion
    # Internal endpoint for workers to trigger completion broadcasts
    def broadcast_completion
      session_id = params[:session_id]
      completion_data = params[:completion]
      
      Rails.logger.info "📡 [BroadcastCompletion] Received callback for session #{session_id}"
      Rails.logger.info "📡 [BroadcastCompletion] Agent: #{completion_data[:agent_name]}"
      
      unless session_id.present? && completion_data.present?
        render json: { success: false, error: "Missing session_id or completion data" }, status: :bad_request
        return
      end
      
      # Convert completion_data to a regular hash if it's ActionController::Parameters
      completion_hash = case completion_data
                        when ActionController::Parameters
                          completion_data.permit!.to_h
                        when Hash
                          completion_data
                        else
                          completion_data.to_h
                        end
      
      # Broadcast completion to question queue overlay
      ScoutChannel.broadcast_to(session_id, {
        type: 'question_queue_update',
        action: 'completed',
        completion: completion_hash
      })
      
      # Broadcast work item notification to trigger inbox refresh
      ScoutChannel.broadcast_to(session_id, {
        type: 'work_item_notification',
        agent_name: completion_hash['agent_name'] || completion_hash[:agent_name],
        status: 'completed',
        summary: completion_hash['message'] || completion_hash[:message],
        execution_id: completion_hash['execution_id'] || completion_hash[:execution_id]
      })
      
      Rails.logger.info "📡 [BroadcastCompletion] ✅ Broadcasted completion via ActionCable"
      
      render json: { success: true, message: "Broadcast sent" }
    rescue => e
      Rails.logger.error "📡 [BroadcastCompletion] ❌ Failed: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end

    private

    def set_question
      @question = AgentInputRequest.find(params[:id])
      
      # Verify ownership
      unless @question.agent_plugin_execution.user_id == current_user.id
        render json: { success: false, error: "Unauthorized" }, status: :forbidden
      end
    end

    def process_answer_attachment(attachment)
      return nil unless attachment.is_a?(ActionDispatch::Http::UploadedFile)

      # Store the attachment using Active Storage
      # Agent communication attachments are ALWAYS transient (short-term)
      # They don't need to be saved to the knowledge base - just for this conversation
      blob = ActiveStorage::Blob.create_and_upload!(
        io: attachment.tempfile,
        filename: attachment.original_filename,
        content_type: attachment.content_type,
        metadata: {
          transient: true,
          storage_type: 'short-term',
          expires_at: 24.hours.from_now.iso8601,
          source: 'agent_communication'
        }
      )

      Rails.logger.info "📎 Agent communication attachment stored as transient (24hr expiry)"

      result = {
        filename: attachment.original_filename,
        content_type: attachment.content_type,
        size: attachment.size,
        blob_id: blob.id,
        url: Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true),
        transient: true
      }

      # Extract content based on file type so the agent can understand it
      attachment.tempfile.rewind
      extracted_content = extract_attachment_content(attachment)
      
      if extracted_content.present?
        result[:extracted_content] = extracted_content
        result[:content_description] = extracted_content
        Rails.logger.info "✅ Content extraction complete for #{attachment.original_filename}"
      end

      result
    rescue => e
      Rails.logger.error "Failed to process attachment: #{e.message}"
      nil
    end

    # Extract content from any file type for agent understanding
    def extract_attachment_content(attachment)
      filename = attachment.original_filename
      extension = File.extname(filename).downcase
      content_type = attachment.content_type
      
      Rails.logger.info "📄 Extracting content from #{filename} (#{content_type})"
      
      begin
        case extension
        when '.jpg', '.jpeg', '.png', '.gif', '.webp'
          # Images - use vision analysis
          extract_image_content(attachment)
          
        when '.pdf'
          # PDFs - try text extraction, fall back to vision for scanned docs
          extract_pdf_content(attachment)
          
        when '.csv'
          # CSV - parse and summarize
          extract_csv_content(attachment)
          
        when '.xlsx', '.xls'
          # Excel - parse and summarize
          extract_excel_content(attachment)
          
        when '.docx', '.doc'
          # Word documents
          extract_docx_content(attachment)
          
        when '.txt', '.md', '.markdown', '.json', '.xml', '.html'
          # Text files - read directly
          attachment.tempfile.rewind
          content = attachment.tempfile.read.force_encoding('UTF-8')
          content.length > 50000 ? content[0...50000] + "\n\n[Content truncated...]" : content
          
        else
          # Unknown file type - try to read as text
          attachment.tempfile.rewind
          begin
            content = attachment.tempfile.read.force_encoding('UTF-8')
            if content.valid_encoding? && content.length < 100000
              content.length > 50000 ? content[0...50000] + "\n\n[Content truncated...]" : content
            else
              "File uploaded: #{filename} (#{content_type}). Binary or unsupported format."
            end
          rescue
            "File uploaded: #{filename} (#{content_type}). Unable to extract text content."
          end
        end
      rescue => e
        Rails.logger.error "Content extraction failed for #{filename}: #{e.message}"
        "File uploaded: #{filename}. Content extraction failed: #{e.message}"
      end
    end

    def extract_image_content(attachment)
      Rails.logger.info "👁️ Running vision analysis on image"
      attachment.tempfile.rewind
      image_data = Base64.strict_encode64(attachment.tempfile.read)
      
      bedrock = BedrockService.new
      bedrock.send_message_with_image(
        "Analyze this image and describe what you see in detail. This is being provided as context for an AI agent to help complete a task. Include: visual elements, text content (if any), layout, colors, style, and any other relevant details.",
        image_data,
        attachment.content_type
      )
    end

    def extract_pdf_content(attachment)
      Rails.logger.info "📄 Extracting PDF content"
      require 'pdf-reader'
      
      attachment.tempfile.rewind
      reader = PDF::Reader.new(attachment.tempfile)
      text_parts = []
      
      reader.pages.each_with_index do |page, index|
        page_text = page.text.strip
        next if page_text.empty?
        text_parts << "=== Page #{index + 1} ===\n#{page_text}\n"
      end
      
      extracted = text_parts.join("\n")
      
      # If minimal text, it might be scanned - try vision
      if extracted.strip.length < 50
        Rails.logger.info "📸 PDF appears scanned, using vision"
        return extract_image_content(attachment) # Treat as image
      end
      
      extracted.length > 50000 ? extracted[0...50000] + "\n\n[Content truncated...]" : extracted
    rescue => e
      Rails.logger.error "PDF extraction failed: #{e.message}"
      "PDF uploaded but text extraction failed: #{e.message}"
    end

    def extract_csv_content(attachment)
      Rails.logger.info "📊 Parsing CSV content"
      require 'csv'
      
      attachment.tempfile.rewind
      content = attachment.tempfile.read.force_encoding('UTF-8')
      
      csv = CSV.parse(content, headers: true)
      
      summary = "📊 **CSV Data Summary**\n"
      summary += "- Rows: #{csv.length}\n"
      summary += "- Columns: #{csv.headers.join(', ')}\n\n"
      
      # Show first 20 rows as sample
      summary += "**Sample Data (first 20 rows):**\n```\n"
      summary += csv.headers.join(" | ") + "\n"
      summary += "-" * 50 + "\n"
      
      csv.first(20).each do |row|
        summary += row.values_at(*csv.headers).map(&:to_s).join(" | ") + "\n"
      end
      summary += "```\n"
      
      if csv.length > 20
        summary += "\n*...and #{csv.length - 20} more rows*"
      end
      
      summary
    rescue => e
      Rails.logger.error "CSV parsing failed: #{e.message}"
      "CSV uploaded but parsing failed: #{e.message}"
    end

    def extract_excel_content(attachment)
      Rails.logger.info "📊 Parsing Excel content"
      
      # Check if roo gem is available
      begin
        require 'roo'
      rescue LoadError
        return "Excel file uploaded: #{attachment.original_filename}. Excel parsing requires the 'roo' gem."
      end
      
      attachment.tempfile.rewind
      
      # Determine file type
      xlsx = if attachment.original_filename.end_with?('.xlsx')
               Roo::Excelx.new(attachment.tempfile.path)
             else
               Roo::Excel.new(attachment.tempfile.path)
             end
      
      summary = "📊 **Excel Data Summary**\n"
      summary += "- Sheets: #{xlsx.sheets.join(', ')}\n\n"
      
      xlsx.sheets.first(3).each do |sheet_name|
        xlsx.default_sheet = sheet_name
        summary += "**Sheet: #{sheet_name}**\n"
        summary += "- Rows: #{xlsx.last_row || 0}\n"
        summary += "- Columns: #{xlsx.last_column || 0}\n"
        
        # Show first 10 rows
        if xlsx.last_row && xlsx.last_row > 0
          summary += "```\n"
          (1..[10, xlsx.last_row].min).each do |row|
            row_data = (1..(xlsx.last_column || 1)).map { |col| xlsx.cell(row, col).to_s }.join(" | ")
            summary += row_data + "\n"
          end
          summary += "```\n"
        end
        summary += "\n"
      end
      
      summary
    rescue => e
      Rails.logger.error "Excel parsing failed: #{e.message}"
      "Excel uploaded but parsing failed: #{e.message}"
    end

    def extract_docx_content(attachment)
      Rails.logger.info "📝 Extracting Word document content"
      
      # Check if docx gem is available
      begin
        require 'docx'
      rescue LoadError
        # Fallback: try to read as zip and extract text
        return extract_docx_fallback(attachment)
      end
      
      attachment.tempfile.rewind
      doc = Docx::Document.open(attachment.tempfile.path)
      
      text = doc.paragraphs.map(&:text).join("\n\n")
      text.length > 50000 ? text[0...50000] + "\n\n[Content truncated...]" : text
    rescue => e
      Rails.logger.error "DOCX extraction failed: #{e.message}"
      extract_docx_fallback(attachment)
    end

    def extract_docx_fallback(attachment)
      # Try to extract text from DOCX using basic zip/xml parsing
      require 'zip'
      
      attachment.tempfile.rewind
      text_content = []
      
      Zip::File.open(attachment.tempfile.path) do |zip|
        doc_xml = zip.find_entry('word/document.xml')
        if doc_xml
          content = doc_xml.get_input_stream.read
          # Extract text between <w:t> tags
          text_content = content.scan(/<w:t[^>]*>([^<]*)<\/w:t>/).flatten
        end
      end
      
      extracted = text_content.join(' ')
      extracted.length > 50000 ? extracted[0...50000] + "\n\n[Content truncated...]" : extracted
    rescue => e
      "Word document uploaded: #{attachment.original_filename}. Text extraction failed: #{e.message}"
    end

    def image_file?(file)
      %w[image/jpeg image/jpg image/png image/gif image/webp].include?(file.content_type)
    end
  end
end

