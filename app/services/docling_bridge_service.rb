class DoclingBridgeService
  require "open3"
  require "json"

  PYTHON_SCRIPT = Rails.root.join("lib", "docling_processor.py")
  CHUNK_SIZE = 2000

  # Check if Docling is available
  def self.available?
    @available ||= begin
      result = system("python3 -c 'import docling' 2>/dev/null")
      Rails.logger.info "Docling availability: #{result ? '✅ Available' : '❌ Not available'}"
      result
    end
  end

  def initialize
    unless self.class.available?
      raise "Docling is not available. Install with: pip3 install -r requirements.txt"
    end
  end

  # Process a document file using Docling
  #
  # @param file_path [String] Path to document file
  # @param options [Hash] Processing options
  # @option options [Integer] :chunk_size Maximum chunk size (default: 2000)
  # @option options [Boolean] :preserve_tables Keep table structure (default: true)
  # @option options [Boolean] :extract_images Extract image metadata (default: false)
  # @option options [String] :chunking_strategy 'simple' or 'semantic' (default: from RagConfig)
  # @option options [Integer] :chunk_overlap Overlap in characters for semantic chunking (default: from RagConfig)
  # @return [Hash] Result with success status, chunks, and metadata
  def process_file(file_path, options = {})
    unless File.exist?(file_path)
      return error_result("File not found: #{file_path}")
    end

    chunk_size = options.fetch(:chunk_size, RagConfig.chunk_size)
    preserve_tables = options.fetch(:preserve_tables, true)
    extract_images = options.fetch(:extract_images, false)
    chunking_strategy = options.fetch(:chunking_strategy, RagConfig.chunking_strategy)
    chunk_overlap = options.fetch(:chunk_overlap, RagConfig.chunk_overlap)

    Rails.logger.info "📄 Processing document with Docling: #{File.basename(file_path)} (#{chunking_strategy} chunking)"

    begin
      stdout, stderr, status = Open3.capture3(
        "python3",
        PYTHON_SCRIPT.to_s,
        file_path,
        chunk_size.to_s,
        preserve_tables.to_s,
        extract_images.to_s,
        chunking_strategy,
        chunk_overlap.to_s,
        timeout: 300 # 5 minute timeout
      )

      unless status.success?
        Rails.logger.error "Docling processing failed: #{stderr}"
        return error_result("Docling processing failed: #{stderr}")
      end

      result = JSON.parse(stdout, symbolize_names: true)

      if result[:success]
        Rails.logger.info "✅ Docling extracted #{result[:chunks].length} chunks"
        result
      else
        Rails.logger.error "Docling error: #{result[:error]}"
        error_result(result[:error])
      end

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Docling output: #{e.message}"
      Rails.logger.error "Output: #{stdout}"
      error_result("Failed to parse Docling output: #{e.message}")

    rescue Timeout::Error
      Rails.logger.error "Docling processing timed out for #{file_path}"
      error_result("Processing timed out after 5 minutes")

    rescue => e
      Rails.logger.error "Docling bridge error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      error_result("Docling bridge error: #{e.message}")
    end
  end

  # Check if a file type is supported by Docling
  def self.supported_file?(filename)
    extension = File.extname(filename).downcase
    SUPPORTED_EXTENSIONS.include?(extension)
  end

  # Get supported file extensions
  SUPPORTED_EXTENSIONS = %w[
    .pdf
    .docx
    .pptx
    .xlsx
    .html
    .md
    .asciidoc
    .xml
  ].freeze

  # Check Docling installation and version
  def self.check_installation
    return { installed: false, error: "Python3 not found" } unless system("which python3 > /dev/null 2>&1")

    stdout, stderr, status = Open3.capture3("python3 -c 'import docling; print(docling.__version__)'")

    if status.success?
      {
        installed: true,
        version: stdout.strip,
        python_path: `which python3`.strip
      }
    else
      {
        installed: false,
        error: stderr.strip,
        hint: "Install with: pip3 install -r requirements.txt"
      }
    end
  rescue => e
    {
      installed: false,
      error: e.message
    }
  end

  private

  def error_result(message)
    {
      success: false,
      error: message,
      chunks: []
    }
  end
end
