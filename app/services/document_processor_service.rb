class DocumentProcessorService
  require "open-uri"
  require "pdf-reader"
  require "kramdown"
  require "yaml"
  require "json"

  def initialize(use_docling: true)
    @chunks = []
    @metadata = {}
    @use_docling = use_docling && DoclingBridgeService.available?

    if @use_docling
      Rails.logger.info "✨ Docling enabled for enhanced document processing"
      @docling_bridge = DoclingBridgeService.new
    else
      Rails.logger.info "📄 Using standard document processing (Docling not available)"
    end
  rescue => e
    Rails.logger.warn "⚠️ Docling initialization failed, falling back to standard processing: #{e.message}"
    @use_docling = false
  end

  def process_documents(documents)
    Rails.logger.info "📄 Processing #{documents.length} documents"

    documents.each do |doc|
      case doc[:type]
      when "url"
        process_url(doc[:content])
      when "file"
        process_file(doc[:content], doc[:filename])
      when "text"
        process_text(doc[:content], doc[:metadata] || {})
      end
    end

    {
      success: true,
      chunks: @chunks,
      total_chunks: @chunks.length,
      metadata: aggregate_metadata
    }
  rescue => e
    Rails.logger.error "Document processing failed: #{e.message}"
    { success: false, error: e.message, chunks: @chunks }
  end

  # Process file with Docling (enhanced parsing)
  def process_with_docling(file_path, filename)
    Rails.logger.info "✨ Processing with Docling: #{filename}"

    result = @docling_bridge.process_file(file_path, {
      chunk_size: 2000,
      preserve_tables: true,
      extract_images: false
    })

    if result[:success]
      Rails.logger.info "✅ Docling extracted #{result[:chunks].length} chunks"

      # Add chunks from Docling
      result[:chunks].each do |chunk|
        @chunks << {
          content: chunk[:content],
          metadata: chunk[:metadata].merge(
            processor: "docling",
            enhanced: true
          )
        }
      end

      # Store Docling metadata
      @metadata[filename] = result[:metadata].merge(
        processor: "docling"
      )

      true # Success
    else
      Rails.logger.warn "Docling processing failed: #{result[:error]}"
      false # Fall back to standard processing
    end
  rescue => e
    Rails.logger.error "Docling bridge error: #{e.message}"
    false # Fall back to standard processing
  end

  # Check if file type is supported by Docling
  def docling_supported?(extension)
    DoclingBridgeService::SUPPORTED_EXTENSIONS.include?(extension)
  end

  private

  def process_url(url)
    Rails.logger.info "🌐 Fetching URL: #{url}"

    begin
      response = URI.open(url,
        "User-Agent" => "AMOS Labs Integration Builder/1.0",
        read_timeout: 30,
        open_timeout: 10
      )

      content_type = response.content_type
      content = response.read

      case content_type
      when /json/i
        process_json_content(content, { source: url })
      when /yaml|yml/i
        process_yaml_content(content, { source: url })
      when /markdown|md/i
        process_markdown_content(content, { source: url })
      when /html/i
        process_html_content(content, { source: url })
      when /pdf/i
        process_pdf_content(content, { source: url })
      else
        process_text(content, { source: url })
      end
    rescue => e
      Rails.logger.error "Failed to fetch URL #{url}: #{e.message}"
      @chunks << {
        content: "Error fetching #{url}: #{e.message}",
        metadata: { source: url, error: true }
      }
    end
  end

  def process_file(file_path, filename)
    Rails.logger.info "📁 Processing file: #{filename}"

    extension = File.extname(filename).downcase

    # Try Docling first for supported file types
    if @use_docling && docling_supported?(extension)
      result = process_with_docling(file_path, filename)
      return if result # Successfully processed with Docling

      Rails.logger.info "⚠️ Docling processing failed, falling back to standard processing"
    end

    # Standard processing (fallback or non-Docling files)
    content = File.read(file_path)

    case extension
    when ".json"
      process_json_content(content, { source: filename })
    when ".yaml", ".yml"
      process_yaml_content(content, { source: filename })
    when ".md", ".markdown"
      process_markdown_content(content, { source: filename })
    when ".pdf"
      process_pdf_file(file_path, { source: filename })
    when ".html", ".htm"
      process_html_content(content, { source: filename })
    when ".xlsx", ".xls", ".ods"
      process_spreadsheet_file(file_path, { source: filename })
    when ".csv"
      process_csv_file(file_path, { source: filename })
    when ".docx"
      process_docx_file(file_path, { source: filename })
    else
      process_text(content, { source: filename })
    end
  end

  def process_json_content(content, metadata)
    data = JSON.parse(content)

    # Handle OpenAPI/Swagger specifications
    if data["openapi"] || data["swagger"]
      process_openapi_spec(data, metadata)
    else
      # Generic JSON processing
      extract_chunks_from_hash(data, metadata, "")
    end
  rescue JSON::ParserError => e
    Rails.logger.error "JSON parse error: #{e.message}"
    process_text(content, metadata.merge(parse_error: true))
  end

  def process_yaml_content(content, metadata)
    data = YAML.safe_load(content)

    # Handle OpenAPI/Swagger specifications
    if data["openapi"] || data["swagger"]
      process_openapi_spec(data, metadata)
    else
      # Generic YAML processing
      extract_chunks_from_hash(data, metadata, "")
    end
  rescue => e
    Rails.logger.error "YAML parse error: #{e.message}"
    process_text(content, metadata.merge(parse_error: true))
  end

  def process_spreadsheet_file(file_path, metadata)
    require 'roo'
    
    Rails.logger.info "📊 Processing spreadsheet: #{metadata[:source]}"
    
    spreadsheet = Roo::Spreadsheet.open(file_path)
    all_content = []
    
    spreadsheet.sheets.each do |sheet_name|
      spreadsheet.default_sheet = sheet_name
      sheet_content = ["## Sheet: #{sheet_name}", ""]
      
      # Get headers from first row
      first_row = spreadsheet.first_row
      last_row = spreadsheet.last_row
      first_col = spreadsheet.first_column
      last_col = spreadsheet.last_column
      
      next unless last_row && last_col
      
      headers = (first_col..last_col).map { |col| spreadsheet.cell(first_row, col)&.to_s || "Column #{col}" }
      sheet_content << "Columns: #{headers.join(', ')}"
      sheet_content << ""
      
      # Extract data rows (limit to prevent huge chunks)
      row_limit = [last_row, first_row + 100].min
      (first_row..row_limit).each do |row_num|
        row_values = (first_col..last_col).map do |col|
          cell = spreadsheet.cell(row_num, col)
          cell.is_a?(Float) && cell == cell.to_i ? cell.to_i.to_s : cell&.to_s
        end
        sheet_content << row_values.join(" | ")
      end
      
      if last_row > row_limit
        sheet_content << "[... #{last_row - row_limit} more rows ...]"
      end
      
      all_content << sheet_content.join("\n")
    end
    
    combined_content = all_content.join("\n\n")
    
    # Create chunks from spreadsheet content
    process_text(combined_content, metadata.merge(type: "spreadsheet"))
  rescue LoadError
    Rails.logger.warn "roo gem not available for spreadsheet processing"
    process_text("Spreadsheet content could not be extracted (missing roo gem)", metadata)
  rescue => e
    Rails.logger.error "Spreadsheet processing error: #{e.message}"
    process_text("Spreadsheet: #{metadata[:source]} (extraction failed: #{e.message})", metadata)
  end

  def process_csv_file(file_path, metadata)
    require 'csv'
    
    Rails.logger.info "📋 Processing CSV: #{metadata[:source]}"
    
    content_lines = []
    CSV.foreach(file_path, headers: true) do |row|
      content_lines << row.to_h.map { |k, v| "#{k}: #{v}" }.join(" | ")
    end
    
    combined_content = content_lines.join("\n")
    process_text(combined_content, metadata.merge(type: "csv"))
  rescue => e
    Rails.logger.error "CSV processing error: #{e.message}"
    content = File.read(file_path) rescue ""
    process_text(content, metadata.merge(type: "csv", parse_error: true))
  end

  def process_docx_file(file_path, metadata)
    require 'docx'
    
    Rails.logger.info "📝 Processing Word document: #{metadata[:source]}"
    
    doc = Docx::Document.open(file_path)
    text_parts = []
    
    doc.paragraphs.each do |paragraph|
      text = paragraph.text.strip
      text_parts << text unless text.empty?
    end
    
    # Also extract from tables
    doc.tables.each do |table|
      table.rows.each do |row|
        row_text = row.cells.map { |cell| cell.text.strip }.reject(&:empty?).join(" | ")
        text_parts << row_text unless row_text.empty?
      end
    end
    
    combined_content = text_parts.join("\n\n")
    
    if combined_content.strip.empty?
      combined_content = "Word document appears to be empty or contains only images/objects."
    end
    
    process_text(combined_content, metadata.merge(type: "docx"))
  rescue LoadError
    Rails.logger.warn "docx gem not available for Word processing"
    process_text("Word document content could not be extracted (missing docx gem)", metadata)
  rescue => e
    Rails.logger.error "Word document processing error: #{e.message}"
    process_text("Word document: #{metadata[:source]} (extraction failed: #{e.message})", metadata)
  end

  def process_openapi_spec(spec, metadata)
    # Extract authentication information
    if spec["components"] && spec["components"]["securitySchemes"]
      auth_chunk = {
        content: "Authentication Methods:\n#{format_security_schemes(spec['components']['securitySchemes'])}",
        metadata: metadata.merge(type: "authentication", api_version: spec["info"]["version"])
      }
      @chunks << auth_chunk
    end

    # Extract endpoint information
    if spec["paths"]
      spec["paths"].each do |path, methods|
        methods.each do |method, details|
          next if method == "parameters"

          endpoint_chunk = {
            content: format_endpoint(path, method, details),
            metadata: metadata.merge(
              type: "endpoint",
              path: path,
              method: method.upcase,
              operation_id: details["operationId"]
            )
          }
          @chunks << endpoint_chunk
        end
      end
    end

    # Extract server/base URL information
    if spec["servers"]
      server_chunk = {
        content: "API Servers:\n#{spec['servers'].map { |s| "#{s['url']} - #{s['description']}" }.join("\n")}",
        metadata: metadata.merge(type: "servers")
      }
      @chunks << server_chunk
    end

    # Store overall API metadata
    @metadata[metadata[:source]] = {
      api_name: spec.dig("info", "title"),
      api_version: spec.dig("info", "version"),
      base_url: spec.dig("servers", 0, "url"),
      total_endpoints: spec["paths"]&.values&.map(&:keys)&.flatten&.count || 0
    }
  end

  def format_security_schemes(schemes)
    schemes.map do |name, config|
      case config["type"]
      when "apiKey"
        "#{name}: API Key (#{config['in']}: #{config['name']})"
      when "http"
        "#{name}: HTTP #{config['scheme']} authentication"
      when "oauth2"
        "#{name}: OAuth 2.0 - #{config['flows'].keys.join(', ')}"
      else
        "#{name}: #{config['type']}"
      end
    end.join("\n")
  end

  def format_endpoint(path, method, details)
    content = []
    content << "#{method.upcase} #{path}"
    content << "Summary: #{details['summary']}" if details["summary"]
    content << "Description: #{details['description']}" if details["description"]

    if details["parameters"]
      content << "\nParameters:"
      details["parameters"].each do |param|
        content << "  - #{param['name']} (#{param['in']}): #{param['description']} #{param['required'] ? '[Required]' : '[Optional]'}"
      end
    end

    if details["requestBody"]
      content << "\nRequest Body:"
      if details["requestBody"]["content"]
        details["requestBody"]["content"].each do |content_type, schema|
          content << "  Content-Type: #{content_type}"
          if schema["schema"] && schema["schema"]["properties"]
            content << "  Properties: #{schema['schema']['properties'].keys.join(', ')}"
          end
        end
      end
    end

    if details["responses"]
      content << "\nResponses:"
      details["responses"].each do |code, response|
        content << "  #{code}: #{response['description']}"
      end
    end

    content.join("\n")
  end

  def process_markdown_content(content, metadata)
    # Parse markdown to extract structure
    doc = Kramdown::Document.new(content)

    # Extract sections
    current_section = []
    current_heading = nil

    doc.root.children.each do |element|
      case element.type
      when :header
        # Save previous section if exists
        if current_section.any?
          @chunks << {
            content: current_section.join("\n"),
            metadata: metadata.merge(
              type: "documentation",
              section: current_heading
            )
          }
        end

        current_heading = element.options[:raw_text]
        current_section = [ current_heading ]
      else
        current_section << element_to_text(element)
      end
    end

    # Save last section
    if current_section.any?
      @chunks << {
        content: current_section.join("\n"),
        metadata: metadata.merge(
          type: "documentation",
          section: current_heading
        )
      }
    end
  end

  def process_html_content(content, metadata)
    # Simple HTML text extraction
    text = content.gsub(/<script.*?<\/script>/m, "") # Remove scripts
                 .gsub(/<style.*?<\/style>/m, "")   # Remove styles
                 .gsub(/<[^>]+>/, " ")              # Remove tags
                 .gsub(/\s+/, " ")                  # Normalize whitespace
                 .strip

    process_text(text, metadata.merge(type: "html"))
  end

  def process_pdf_file(file_path, metadata)
    reader = PDF::Reader.new(file_path)

    reader.pages.each_with_index do |page, index|
      text = page.text
      next if text.strip.empty?

      @chunks << {
        content: text,
        metadata: metadata.merge(
          type: "pdf",
          page: index + 1,
          total_pages: reader.page_count
        )
      }
    end
  rescue => e
    Rails.logger.error "PDF processing error: #{e.message}"
    @chunks << {
      content: "Error processing PDF: #{e.message}",
      metadata: metadata.merge(error: true)
    }
  end

  def process_text(content, metadata)
    # Split long text into chunks
    max_chunk_size = 2000

    if content.length <= max_chunk_size
      @chunks << {
        content: content,
        metadata: metadata.merge(type: "text")
      }
    else
      # Split by paragraphs or sentences
      paragraphs = content.split(/\n\n+/)

      current_chunk = []
      current_size = 0

      paragraphs.each do |paragraph|
        if current_size + paragraph.length > max_chunk_size && current_chunk.any?
          @chunks << {
            content: current_chunk.join("\n\n"),
            metadata: metadata.merge(type: "text", chunked: true)
          }
          current_chunk = [ paragraph ]
          current_size = paragraph.length
        else
          current_chunk << paragraph
          current_size += paragraph.length
        end
      end

      # Add remaining chunk
      if current_chunk.any?
        @chunks << {
          content: current_chunk.join("\n\n"),
          metadata: metadata.merge(type: "text", chunked: true)
        }
      end
    end
  end

  def extract_chunks_from_hash(data, metadata, prefix)
    case data
    when Hash
      data.each do |key, value|
        new_prefix = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        extract_chunks_from_hash(value, metadata, new_prefix)
      end
    when Array
      if data.all? { |item| item.is_a?(Hash) }
        # Array of objects - process each
        data.each_with_index do |item, index|
          extract_chunks_from_hash(item, metadata, "#{prefix}[#{index}]")
        end
      else
        # Simple array - create chunk
        @chunks << {
          content: "#{prefix}: #{data.join(', ')}",
          metadata: metadata.merge(type: "data", path: prefix)
        }
      end
    else
      # Leaf value - create chunk
      @chunks << {
        content: "#{prefix}: #{data}",
        metadata: metadata.merge(type: "data", path: prefix)
      }
    end
  end

  def element_to_text(element)
    case element.type
    when :text
      element.value
    when :p, :blockquote
      element.children.map { |child| element_to_text(child) }.join
    when :ul, :ol
      element.children.map { |li| "- #{element_to_text(li)}" }.join("\n")
    when :codeblock
      "```#{element.options[:lang]}\n#{element.value}```"
    when :codespan
      "`#{element.value}`"
    else
      element.children.map { |child| element_to_text(child) }.join if element.children
    end
  end

  def aggregate_metadata
    {
      total_sources: @metadata.keys.count,
      api_specs_found: @metadata.values.count { |m| m[:api_name].present? },
      total_endpoints: @metadata.values.sum { |m| m[:total_endpoints] || 0 },
      sources: @metadata
    }
  end
end
