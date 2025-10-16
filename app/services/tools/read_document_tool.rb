module Tools
  class ReadDocumentTool < BaseTool
    def self.read_only?
      true
    end
    
    def self.metadata
      {
        name: 'read_document',
        description: 'Read and extract text content from uploaded documents (PDF, DOCX, TXT, etc.) so you can analyze, translate, or summarize them',
        category: 'document',
        input_schema: {
          type: 'object',
          properties: {
            file_url: {
              type: 'string',
              description: 'URL of the uploaded file to read'
            },
            asset_id: {
              type: 'integer',
              description: 'ImageAsset ID of the uploaded file'
            },
            max_length: {
              type: 'integer',
              description: 'Maximum characters to return (default: 50000)',
              default: 50000
            }
          }
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      file_url = get_arg(args, :file_url)
      asset_id = get_arg(args, :asset_id)
      max_length = get_arg(args, :max_length, 50000)
      
      # Need either file_url or asset_id
      if !file_url && !asset_id
        return error_response("Either file_url or asset_id is required")
      end
      
      begin
        # Find the file
        if asset_id
          asset = ImageAsset.find_by(id: asset_id, entity: @entity)
          return error_response("File not found or access denied") unless asset
          
          file_path = ActiveStorage::Blob.service.path_for(asset.file.blob.key)
          filename = asset.file.filename.to_s
          content_type = asset.file.content_type
        elsif file_url
          # Download from URL (if it's an ActiveStorage URL)
          return error_response("Direct URL reading not yet implemented")
        end
        
        # Extract text based on file type
        extension = File.extname(filename).downcase
        
        text_content = case extension
        when '.pdf'
          # Try text extraction first
          extracted = extract_pdf_text(file_path)
          
          # If no text found (scanned PDF), use Claude vision
          if extracted.strip.length < 50
            Rails.logger.info "📸 PDF has minimal text - using Claude vision for OCR"
            extract_with_vision(file_path, 'application/pdf')
          else
            extracted
          end
        when '.txt'
          File.read(file_path)
        when '.md', '.markdown'
          File.read(file_path)
        when '.docx'
          extract_docx_text(file_path)
        when '.jpg', '.jpeg', '.png', '.gif', '.webp'
          # Images - use Claude vision
          extract_with_vision(file_path, content_type)
        else
          File.read(file_path) rescue "Unable to read file type: #{extension}"
        end
        
        # Truncate if too long
        if text_content.length > max_length
          text_content = text_content[0...max_length] + "\n\n[Content truncated - full document has #{text_content.length} characters]"
        end

        # Suggest loading document viewer canvas
        @context[:canvas_suggestion] = 'document_viewer'
        @context[:canvas_data] = {
          filename: filename,
          content_type: content_type,
          asset_id: asset_id,  # Canvas can build URL from this
          size: asset&.file&.blob&.byte_size,
          extracted_text_preview: text_content.first(500)
        }

        success_response(
          content: text_content,
          filename: filename,
          file_type: extension,
          content_type: content_type,
          character_count: text_content.length,
          truncated: text_content.length >= max_length,
          message: "Successfully extracted #{text_content.length} characters from #{filename}"
        )
        
      rescue => e
        Rails.logger.error "Document reading failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Failed to read document: #{e.message}")
      end
    end
    
    private
    
    def extract_pdf_text(file_path)
      require 'pdf-reader'
      
      reader = PDF::Reader.new(file_path)
      text_parts = []
      
      reader.pages.each_with_index do |page, index|
        page_text = page.text.strip
        next if page_text.empty?
        
        text_parts << "=== Page #{index + 1} ===\n#{page_text}\n"
      end
      
      text_parts.join("\n")
    rescue => e
      Rails.logger.error "PDF extraction failed: #{e.message}"
      "Error extracting PDF: #{e.message}"
    end
    
    def extract_docx_text(file_path)
      # Would need docx gem for this
      # For now, return message
      "DOCX extraction not yet implemented. Please upload as PDF or TXT."
    end
    
    def extract_with_vision(file_path, content_type)
      # Use Claude vision API to read scanned PDFs or images
      Rails.logger.info "👁️ Using Claude vision to read document"
      
      begin
        # For PDFs, convert first page to image
        if content_type == 'application/pdf'
          image_data = convert_pdf_to_image(file_path)
          media_type = 'image/png'
        else
          # Read image file directly
          image_data = File.read(file_path)
          media_type = content_type
        end
        
        # Encode to base64
        base64_image = Base64.strict_encode64(image_data)
        
        # Call Claude vision API
        ai_service = BedrockService.new(user: @user, entity: @entity)
        
        response = ai_service.send_message_with_image(
          "Extract all text from this document/image. Preserve formatting, layout, and structure as much as possible. If the document is in another language, extract it in the original language.",
          base64_image,
          media_type
        )
        
        "=== Text extracted via Claude Vision (OCR) ===\n\n#{response}"
        
      rescue => e
        Rails.logger.error "Vision extraction failed: #{e.message}"
        "Error using vision extraction: #{e.message}"
      end
    end
    
    def convert_pdf_to_image(pdf_path)
      # Convert first page of PDF to PNG for vision processing
      # Keep under Claude's 5MB limit
      require 'mini_magick'
      
      image = MiniMagick::Image.open("#{pdf_path}[0]")  # First page only
      image.format 'png'
      
      # Start with good quality
      image.resize '1600x1600>'  # Reasonable size for OCR
      image.quality 85
      
      # Get blob
      blob = image.to_blob
      
      # If still > 5MB, reduce further
      if blob.bytesize > 5_000_000
        Rails.logger.info "📦 Image too large (#{blob.bytesize} bytes), compressing..."
        image.resize '1200x1200>'
        image.quality 75
        blob = image.to_blob
      end
      
      # If STILL > 5MB, aggressive compression
      if blob.bytesize > 5_000_000
        Rails.logger.info "📦 Still too large, aggressive compression..."
        image.resize '800x800>'
        image.quality 60
        blob = image.to_blob
      end
      
      Rails.logger.info "✅ Final image size: #{blob.bytesize} bytes (#{(blob.bytesize / 1024.0 / 1024.0).round(2)} MB)"
      
      blob
    rescue LoadError
      # If MiniMagick not available, return error
      raise "MiniMagick gem required for scanned PDF processing. Install with: gem install mini_magick"
    rescue => e
      raise "PDF to image conversion failed: #{e.message}"
    end
  end
end

