# Smart chunking service for docling-processed documents
#
# Features:
# - Section-aware chunking (preserves document structure)
# - Table extraction and formatting
# - Code block handling
# - Overlapping chunks for context
# - Token-aware splitting
#
# Usage:
#   service = DoclingChunkingService.new(max_tokens: 512, overlap: 50)
#   chunks = service.chunk(docling_output)

class DoclingChunkingService
  # Default configuration
  DEFAULT_MAX_TOKENS = 512
  DEFAULT_OVERLAP = 50
  DEFAULT_PRESERVE_SECTIONS = true

  def initialize(max_tokens: DEFAULT_MAX_TOKENS, overlap: DEFAULT_OVERLAP, preserve_sections: DEFAULT_PRESERVE_SECTIONS)
    @max_tokens = max_tokens
    @overlap = overlap
    @preserve_sections = preserve_sections
  end

  def chunk(docling_output)
    chunks = []

    Rails.logger.info "📄 DoclingChunkingService: Chunking document"
    Rails.logger.debug "  Config: max_tokens=#{@max_tokens}, overlap=#{@overlap}, preserve_sections=#{@preserve_sections}"

    # Handle different docling output formats
    if docling_output.is_a?(Hash)
      # Standard docling output
      chunks.concat(process_docling_hash(docling_output))
    elsif docling_output.is_a?(String)
      # Plain text fallback
      chunks.concat(chunk_plain_text(docling_output))
    else
      raise ArgumentError, "Unsupported docling output type: #{docling_output.class}"
    end

    Rails.logger.info "  Created #{chunks.length} chunks"
    chunks
  end

  private

  def process_docling_hash(docling_output)
    chunks = []

    # Handle sections if present and section preservation is enabled
    if @preserve_sections && docling_output['sections'].present?
      Rails.logger.debug "  Processing #{docling_output['sections'].length} sections"
      chunks.concat(chunk_by_sections(docling_output['sections']))
    elsif docling_output['text'].present?
      # Fall back to sliding window chunking
      Rails.logger.debug "  Using sliding window chunking"
      chunks.concat(chunk_by_sliding_window(docling_output['text']))
    elsif docling_output['content'].present?
      # Alternative key for text content
      chunks.concat(chunk_by_sliding_window(docling_output['content']))
    end

    # Handle tables separately (they need special formatting)
    if docling_output['tables'].present?
      Rails.logger.debug "  Processing #{docling_output['tables'].length} tables"
      chunks.concat(create_table_chunks(docling_output['tables']))
    end

    # Handle code blocks if present
    if docling_output['code_blocks'].present?
      Rails.logger.debug "  Processing #{docling_output['code_blocks'].length} code blocks"
      chunks.concat(create_code_chunks(docling_output['code_blocks']))
    end

    chunks
  end

  def chunk_by_sections(sections)
    chunks = []

    sections.each do |section|
      section_text = build_section_text(section)
      token_count = estimate_tokens(section_text)

      if token_count <= @max_tokens
        # Section fits in one chunk
        chunks << create_chunk(
          content: section_text,
          type: 'section',
          metadata: extract_section_metadata(section)
        )
      else
        # Split large section into multiple chunks
        sub_chunks = split_text_intelligently(section_text)

        sub_chunks.each_with_index do |chunk_text, i|
          chunks << create_chunk(
            content: chunk_text,
            type: 'section',
            metadata: extract_section_metadata(section).merge(
              section_part: i + 1,
              total_parts: sub_chunks.length
            )
          )
        end
      end
    end

    chunks
  end

  def chunk_by_sliding_window(text)
    chunks = []

    # Split into sentences
    sentences = text.split(/(?<=[.!?])\s+/)

    current_chunk = []
    current_tokens = 0

    sentences.each do |sentence|
      sentence_tokens = estimate_tokens(sentence)

      # Check if adding this sentence exceeds limit
      if current_tokens + sentence_tokens > @max_tokens && current_chunk.any?
        # Save current chunk
        chunks << create_chunk(
          content: current_chunk.join(' '),
          type: 'text',
          metadata: {}
        )

        # Start new chunk with overlap (keep last few sentences)
        overlap_sentences = current_chunk.last([2, current_chunk.length].min)
        current_chunk = overlap_sentences
        current_tokens = overlap_sentences.sum { |s| estimate_tokens(s) }
      end

      current_chunk << sentence
      current_tokens += sentence_tokens
    end

    # Add final chunk if any content remains
    if current_chunk.any?
      chunks << create_chunk(
        content: current_chunk.join(' '),
        type: 'text',
        metadata: {}
      )
    end

    chunks
  end

  def chunk_plain_text(text)
    # Simple word-based chunking for plain text
    chunks = []
    words = text.split(/\s+/)

    current_chunk = []
    current_tokens = 0

    words.each do |word|
      word_tokens = estimate_tokens(word)

      if current_tokens + word_tokens > @max_tokens && current_chunk.any?
        chunks << create_chunk(
          content: current_chunk.join(' '),
          type: 'text',
          metadata: {}
        )

        # Overlap: keep last N words
        overlap_words = current_chunk.last([@overlap, current_chunk.length].min)
        current_chunk = overlap_words
        current_tokens = overlap_words.sum { |w| estimate_tokens(w) }
      end

      current_chunk << word
      current_tokens += word_tokens
    end

    if current_chunk.any?
      chunks << create_chunk(
        content: current_chunk.join(' '),
        type: 'text',
        metadata: {}
      )
    end

    chunks
  end

  def create_table_chunks(tables)
    tables.map do |table|
      content_parts = []

      # Add table caption if available
      content_parts << "Table: #{table['caption']}" if table['caption'].present?

      # Add table content (prefer markdown, fall back to text)
      if table['markdown'].present?
        content_parts << table['markdown']
      elsif table['text'].present?
        content_parts << table['text']
      elsif table['data'].present?
        # Convert array data to markdown table
        content_parts << array_to_markdown_table(table['data'])
      end

      create_chunk(
        content: content_parts.join("\n\n"),
        type: 'table',
        metadata: {
          table_id: table['id'],
          page: table['page_number'] || table['page'],
          rows: table['num_rows'] || table['rows'],
          cols: table['num_cols'] || table['columns']
        }
      )
    end
  end

  def create_code_chunks(code_blocks)
    code_blocks.map do |code|
      language = code['language'] || 'plaintext'

      content = if code['content'].present?
                  "```#{language}\n#{code['content']}\n```"
                else
                  code['text'] || ''
                end

      create_chunk(
        content: content,
        type: 'code',
        metadata: {
          language: language,
          page: code['page_number'] || code['page']
        }
      )
    end
  end

  # Helper methods

  def build_section_text(section)
    parts = []
    parts << section['title'] if section['title'].present?
    parts << section['text'] if section['text'].present?
    parts << section['content'] if section['content'].present?
    parts.join("\n\n")
  end

  def extract_section_metadata(section)
    {
      section_title: section['title'],
      section_level: section['level'],
      page_start: section['page_start'] || section['page'],
      page_end: section['page_end']
    }.compact
  end

  def split_text_intelligently(text)
    chunks = []
    words = text.split(/\s+/)

    current_chunk = []
    current_tokens = 0

    words.each do |word|
      word_tokens = estimate_tokens(word)

      if current_tokens + word_tokens > @max_tokens && current_chunk.any?
        chunks << current_chunk.join(' ')

        # Overlap
        overlap_words = current_chunk.last(@overlap)
        current_chunk = overlap_words
        current_tokens = overlap_words.sum { |w| estimate_tokens(w) }
      end

      current_chunk << word
      current_tokens += word_tokens
    end

    chunks << current_chunk.join(' ') if current_chunk.any?
    chunks
  end

  def create_chunk(content:, type:, metadata:)
    {
      content: content,
      type: type,
      metadata: metadata
    }
  end

  def estimate_tokens(text)
    # Heuristic: 1 token ≈ 4 characters for English
    # This is approximate; actual tokenization depends on the model
    (text.to_s.length / 4.0).ceil
  end

  def array_to_markdown_table(data)
    return '' if data.nil? || data.empty?

    # Assume first row is headers
    headers = data.first
    rows = data[1..]

    # Build markdown table
    lines = []
    lines << "| #{headers.join(' | ')} |"
    lines << "| #{headers.map { '---' }.join(' | ')} |"

    rows.each do |row|
      lines << "| #{row.join(' | ')} |"
    end

    lines.join("\n")
  end
end
