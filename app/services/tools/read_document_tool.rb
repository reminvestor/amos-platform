require 'tempfile'
require 'open3'

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
              description: 'ImageAsset or RagDocument ID of the uploaded file'
            },
            asset_type: {
              type: 'string',
              description: 'Type of asset: "document" for RagDocument (PDFs, docs), "image" for ImageAsset (images). Required to look in the correct table.',
              enum: ['document', 'image']
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
      asset_type = get_arg(args, :asset_type) # 'document' or 'image'
      max_length = get_arg(args, :max_length, 50000)
      
      # Need either file_url or asset_id
      if !file_url && !asset_id
        return error_response("Either file_url or asset_id is required")
      end
      
      tempfile = nil
      begin
        # Find the file
        if asset_id
          Rails.logger.info "🔍 ReadDocumentTool: Looking for asset_id: #{asset_id}, asset_type: #{asset_type}"
          
          asset = nil
          
          # Use asset_type to look in the correct table first
          if asset_type == 'document'
            # Look for RagDocument first (PDFs, docs, etc.)
            Rails.logger.info "🔍 Looking for RagDocument first (asset_type: document)..."
            rag_document = RagDocument.joins(:rag_store).find_by(
              id: asset_id, 
              rag_stores: { entity_id: @entity.id }
            )
            
            if rag_document && rag_document.file.attached?
              asset = rag_document
              Rails.logger.info "✅ Found as RagDocument: #{rag_document.id}"
            else
              # Fallback to ImageAsset if not found as RagDocument
              Rails.logger.info "🔍 Not found as RagDocument, trying ImageAsset..."
              asset = ImageAsset.find_by(id: asset_id, entity: @entity)
              Rails.logger.info "✅ Found as ImageAsset: #{asset.id}" if asset
            end
          else
            # Look for ImageAsset first (images, or when asset_type not specified)
            Rails.logger.info "🔍 Looking for ImageAsset first..."
            asset = ImageAsset.find_by(id: asset_id, entity: @entity)
            
            if asset
              Rails.logger.info "✅ Found as ImageAsset: #{asset.id}"
            else
              # Fallback to RagDocument if not found as ImageAsset
              Rails.logger.info "🔍 Not found as ImageAsset, trying RagDocument..."
              rag_document = RagDocument.joins(:rag_store).find_by(
                id: asset_id, 
                rag_stores: { entity_id: @entity.id }
              )
              
              if rag_document && rag_document.file.attached?
                asset = rag_document
                Rails.logger.info "✅ Found as RagDocument: #{rag_document.id}"
              end
            end
          end
          
          unless asset
            Rails.logger.error "❌ Asset not found as ImageAsset or RagDocument"
            return error_response("File not found or access denied")
          end
          
          # Download the file to a temporary location for processing
          # This ensures compatibility with tools like ImageMagick
          begin
            tempfile = asset.file.blob.open do |file|
              # Create a temp file with the same extension
              ext = File.extname(asset.file.filename.to_s)
              temp = Tempfile.new(['document', ext])
              temp.binmode
              temp.write(file.read)
              temp.rewind
              temp
            end
            
            file_path = tempfile.path
            filename = asset.file.filename.to_s
            content_type = asset.file.content_type
          rescue => e
            Rails.logger.error "Failed to create temp file: #{e.message}"
            return error_response("Failed to access file: #{e.message}")
          end
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
        when '.xlsx', '.xls'
          extract_excel_text(file_path)
        when '.csv'
          extract_csv_text(file_path)
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

        # Trigger RAG indexing for this document if not already indexed (only for ImageAssets)
        # RagDocuments are already in the RAG system
        if asset_id && asset.is_a?(ImageAsset)
          enqueue_rag_indexing(asset, filename)
        end

        # Suggest loading document viewer canvas
        @context[:canvas_suggestion] = 'document_viewer'
        @context[:canvas_data] = {
          filename: filename,
          content_type: content_type,
          asset_id: asset_id,  # Canvas can build URL from this
          asset_type: asset_type || (asset.is_a?(RagDocument) ? 'document' : 'image'),  # Pass asset_type so canvas knows which table to query
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
          source: 'uploaded',  # Document from uploaded files
          message: "Successfully extracted #{text_content.length} characters from #{filename}"
        )
        
      rescue => e
        Rails.logger.error "Document reading failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Failed to read document: #{e.message}")
      ensure
        # Clean up tempfile if we created one
        tempfile&.close! if defined?(tempfile) && tempfile
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
    
    def extract_excel_text(file_path)
      require 'roo'
      
      spreadsheet = Roo::Spreadsheet.open(file_path)
      text_parts = []
      
      spreadsheet.sheets.each do |sheet_name|
        sheet = spreadsheet.sheet(sheet_name)
        text_parts << "=== Sheet: #{sheet_name} ==="
        
        # Get headers from first row
        headers = sheet.row(1).map(&:to_s)
        text_parts << headers.join("\t")
        text_parts << "-" * 40
        
        # Get data rows (limit to first 500 for sanity)
        (2..[sheet.last_row, 502].min).each do |row_num|
          row = sheet.row(row_num).map(&:to_s)
          text_parts << row.join("\t")
        end
        
        if sheet.last_row > 502
          text_parts << "[... #{sheet.last_row - 502} more rows truncated ...]"
        end
        
        text_parts << ""
      end
      
      text_parts.join("\n")
    rescue LoadError
      Rails.logger.warn "roo gem not available for Excel parsing"
      "Excel parsing requires the 'roo' gem. Please install it or convert to CSV."
    rescue => e
      "Error reading Excel file: #{e.message}"
    end

    def extract_csv_text(file_path)
      require 'csv'
      
      rows = CSV.read(file_path, headers: false)
      return "CSV file is empty" if rows.empty?
      
      text_parts = []
      headers = rows.first
      text_parts << headers.join("\t")
      text_parts << "-" * 40
      
      rows[1..500].each do |row|
        text_parts << row.map(&:to_s).join("\t")
      end
      
      if rows.length > 501
        text_parts << "[... #{rows.length - 501} more rows truncated ...]"
      end
      
      text_parts.join("\n")
    rescue => e
      "Error reading CSV file: #{e.message}"
    end

    def extract_docx_text(file_path)
      require 'docx'
      
      doc = Docx::Document.open(file_path)
      
      # Extract text from all paragraphs
      text_parts = []
      
      doc.paragraphs.each do |paragraph|
        text = paragraph.text.strip
        text_parts << text unless text.empty?
      end
      
      # Also extract from tables
      doc.tables.each do |table|
        table.rows.each do |row|
          row_text = row.cells.map { |cell| cell.text.strip }.reject(&:empty?).join("\t")
          text_parts << row_text unless row_text.empty?
        end
      end
      
      extracted = text_parts.join("\n\n")
      
      if extracted.strip.empty?
        "Word document appears to be empty or contains only images/objects that cannot be extracted as text."
      else
        extracted
      end
    rescue LoadError
      Rails.logger.warn "docx gem not available - falling back to basic extraction"
      "DOCX extraction requires the 'docx' gem. Please install it or upload as PDF."
    rescue => e
      Rails.logger.error "DOCX extraction failed: #{e.message}"
      "Error extracting Word document: #{e.message}"
    end
    
    def extract_with_vision(file_path, content_type)
      # Use Claude vision API to read scanned PDFs or images
      Rails.logger.info "👁️ Using Claude vision to read document"
      
      begin
        # For PDFs, convert first page to image
        if content_type == 'application/pdf'
          begin
            image_data = convert_pdf_to_image(file_path)
            media_type = 'image/png'
          rescue => conv_error
            Rails.logger.error "PDF conversion failed: #{conv_error.message}"
            # Return a helpful message instead of crashing
            return <<~MSG
              📋 Document Information:
              - File: #{File.basename(file_path)}
              - Type: PDF Document
              
              ⚠️ Unable to extract text from this PDF using OCR.
              
              This appears to be a scanned PDF that requires special tools to read.
              To enable PDF OCR, please ensure the following are installed on your system:
              - ImageMagick: brew install imagemagick
              - Ghostscript: brew install ghostscript
              
              Alternatively, you can:
              1. Convert the PDF to text using an online tool
              2. Upload a text-based PDF instead of a scanned image
              3. Take a screenshot of the PDF and upload it as an image
            MSG
          end
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
      
      # Ensure the file exists
      unless File.exist?(pdf_path)
        raise "PDF file not found at path: #{pdf_path}"
      end
      
      # Create a new tempfile for the output PNG
      output_file = Tempfile.new(['pdf_page', '.png'])
      output_path = output_file.path
      
      begin
        # Check if we can use system commands
        Rails.logger.info "🔍 Checking for PDF conversion tools..."
        
        # Try using Ghostscript directly first
        gs_version, status = Open3.capture2e('gs', '--version')
        gs_version = gs_version.strip
        if status.success? && gs_version.match?(/\d+\.\d+/)
          Rails.logger.info "✅ Using Ghostscript #{gs_version} for PDF conversion"
          
          # Convert PDF to PNG using Ghostscript directly
          gs_cmd = [
            "gs",
            "-dNOPAUSE",
            "-dBATCH",
            "-sDEVICE=png16m",
            "-r150",
            "-dFirstPage=1",
            "-dLastPage=1",
            "-sOutputFile=#{output_path}",
            pdf_path
          ]
          
          # Execute the command and capture output
          output, status = Open3.capture2e(*gs_cmd)
          unless status.success?
            Rails.logger.error "Ghostscript conversion failed: #{output}"
            raise "Ghostscript conversion failed: #{output}"
          end
        else
          # Fall back to ImageMagick
          Rails.logger.info "⚠️ Ghostscript not found, trying ImageMagick..."
          
          # Use ImageMagick command directly to avoid MiniMagick issues
          convert_cmd = [
            "convert",
            "-density", "150",
            "-quality", "85",
            "-resize", "1600x1600>",
            "-background", "white",
            "-alpha", "remove",
            "#{pdf_path}[0]",
            output_path
          ]
          
          # Execute the command and capture output
          output, status = Open3.capture2e(*convert_cmd)
          unless status.success?
            Rails.logger.error "ImageMagick conversion failed: #{output}"
            raise "ImageMagick conversion failed: #{output}. Please ensure ImageMagick and Ghostscript are installed:\nbrew install imagemagick ghostscript"
          end
        end
        
        # Read the converted image
        image_data = File.read(output_path)
        
        # If still > 5MB, reduce quality
        if image_data.bytesize > 5_000_000
          Rails.logger.info "📦 Image too large (#{image_data.bytesize} bytes), reducing quality..."
          MiniMagick::Tool::Convert.new do |convert|
            convert << "#{pdf_path}[0]"
            convert.merge! ["-density", "100"] 
            convert.merge! ["-quality", "75"]
            convert.merge! ["-resize", "1200x1200>"]
            convert.merge! ["-background", "white"]
            convert.merge! ["-alpha", "remove"]
            convert << output_path
          end
          image_data = File.read(output_path)
        end
        
        Rails.logger.info "✅ Converted PDF to image: #{image_data.bytesize} bytes"
        return image_data
      ensure
        output_file.close! if output_file
      end
    rescue LoadError
      # If MiniMagick not available, return error
      raise "MiniMagick gem required for scanned PDF processing. Install with: gem install mini_magick"
    rescue => e
      Rails.logger.error "PDF conversion error: #{e.message}"
      Rails.logger.error "Please install required tools with: brew install imagemagick ghostscript"
      raise "PDF to image conversion failed: #{e.message}. Please ensure ImageMagick and Ghostscript are installed."
    end

    def enqueue_rag_indexing(asset, filename)
      # Check if this asset has already been indexed
      existing_rag_docs = RagDocument.joins(:rag_store)
        .where(rag_stores: { entity_id: @entity.id })
        .where("rag_documents.original_filename = ?", filename)
        .count

      if existing_rag_docs > 0
        Rails.logger.info "📚 Document #{filename} already indexed in RAG, skipping"
        return
      end

      # Create a persistent temp file from ActiveStorage
      ext = File.extname(filename)
      persistent_temp = Tempfile.new(['rag_document', ext])
      persistent_temp.binmode

      # Copy file from ActiveStorage to temp location
      asset.file.blob.open do |blob_file|
        persistent_temp.write(blob_file.read)
      end

      persistent_temp.rewind
      persistent_temp_path = persistent_temp.path
      persistent_temp.close  # Close but keep the file (don't unlink)

      # Create a RagStore for this document if not exists
      rag_store = @entity.rag_stores.find_or_create_by(
        name: "Chat Documents",
        app_name: "scout",
        store_type: "general"
      ) do |store|
        store.status = 'active'
      end

      Rails.logger.info "📤 Enqueuing RAG indexing for #{filename}"

      # Enqueue the document pipeline job to process the file
      Rag::DocumentPipelineJob.perform_later(
        rag_store.id,
        persistent_temp_path,
        {
          source: "upload",
          asset_id: asset.id,
          content_type: asset.file.content_type
        }
      )
    rescue => e
      Rails.logger.warn "⚠️ Failed to enqueue RAG indexing: #{e.message}"
      # Don't raise - this shouldn't block document reading
    end
  end
end

