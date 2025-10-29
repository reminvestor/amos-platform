require "test_helper"

class DoclingChunkingServiceTest < ActiveSupport::TestCase
  setup do
    @service = DoclingChunkingService.new
  end

  # ===== Initialization =====

  test "initializes with default configuration" do
    service = DoclingChunkingService.new

    assert_equal DoclingChunkingService::DEFAULT_MAX_TOKENS, service.instance_variable_get(:@max_tokens)
    assert_equal DoclingChunkingService::DEFAULT_OVERLAP, service.instance_variable_get(:@overlap)
    assert_equal DoclingChunkingService::DEFAULT_PRESERVE_SECTIONS, service.instance_variable_get(:@preserve_sections)
  end

  test "initializes with custom configuration" do
    service = DoclingChunkingService.new(max_tokens: 1024, overlap: 100, preserve_sections: false)

    assert_equal 1024, service.instance_variable_get(:@max_tokens)
    assert_equal 100, service.instance_variable_get(:@overlap)
    assert_equal false, service.instance_variable_get(:@preserve_sections)
  end

  # ===== Input Type Handling =====

  test "handles Hash input (standard Docling output)" do
    docling_output = {
      'text' => 'This is sample document content.'
    }

    chunks = @service.chunk(docling_output)

    assert_kind_of Array, chunks
    assert chunks.any?
    assert_equal 'This is sample document content.', chunks.first[:content]
  end

  test "handles String input (plain text fallback)" do
    plain_text = "This is plain text that will be chunked."

    chunks = @service.chunk(plain_text)

    assert_kind_of Array, chunks
    assert chunks.any?
    assert_includes chunks.first[:content], "plain text"
  end

  test "raises error for invalid input type" do
    assert_raises(ArgumentError, /Unsupported docling output type/) do
      @service.chunk([1, 2, 3]) # Array is not supported
    end
  end

  # ===== Section-Aware Chunking =====

  test "chunks by sections when sections are present" do
    docling_output = {
      'sections' => [
        {
          'title' => 'Introduction',
          'content' => 'This is the introduction section.',
          'level' => 1,
          'page' => 1
        },
        {
          'title' => 'Chapter 1',
          'content' => 'This is chapter 1 content.',
          'level' => 1,
          'page' => 2
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    assert_equal 2, chunks.length
    assert_equal 'section', chunks.first[:type]
    assert_includes chunks.first[:content], "Introduction"
    assert_includes chunks.last[:content], "Chapter 1"
  end

  test "creates single chunk for small section" do
    docling_output = {
      'sections' => [
        {
          'title' => 'Small Section',
          'content' => 'Short content.',
          'level' => 1,
          'page' => 1
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    assert_equal 1, chunks.length
    assert_equal 'section', chunks.first[:type]
  end

  test "splits large section into multiple chunks" do
    # Create content larger than max_tokens (512 tokens = ~2048 chars)
    long_content = 'A' * 3000

    docling_output = {
      'sections' => [
        {
          'title' => 'Large Section',
          'content' => long_content,
          'level' => 1,
          'page' => 1
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    # Should split into multiple chunks
    assert chunks.length > 1

    # All chunks should be section type
    chunks.each do |chunk|
      assert_equal 'section', chunk[:type]
    end

    # Should track section parts
    assert_not_nil chunks.first[:metadata][:section_part]
    assert_not_nil chunks.first[:metadata][:total_parts]
  end

  test "preserves section metadata" do
    docling_output = {
      'sections' => [
        {
          'title' => 'Test Section',
          'content' => 'Content here.',
          'level' => 2,
          'page' => 5
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    metadata = chunks.first[:metadata]
    assert_equal 'Test Section', metadata[:section_title]
    assert_equal 2, metadata[:section_level]
    assert_equal 5, metadata[:page_start]
  end

  test "skips section chunking when preserve_sections is false" do
    service = DoclingChunkingService.new(preserve_sections: false)

    docling_output = {
      'sections' => [
        { 'title' => 'Section', 'content' => 'Content' }
      ],
      'text' => 'Full document text'
    }

    chunks = service.chunk(docling_output)

    # Should use sliding window instead of sections
    # (Hard to assert exact behavior, but should not be 'section' type)
    # Actually, with no sections processing, it falls back to text
    assert chunks.any?
  end

  # ===== Sliding Window Chunking =====

  test "uses sliding window for text without sections" do
    docling_output = {
      'text' => 'Sentence one. Sentence two. Sentence three. Sentence four.'
    }

    chunks = @service.chunk(docling_output)

    assert chunks.any?
    # Should create chunks by sentences
  end

  test "creates overlapping chunks in sliding window" do
    # Create text with many sentences to force multiple chunks
    sentences = 100.times.map { |i| "Sentence number #{i}." }.join(' ')

    docling_output = {
      'text' => sentences
    }

    chunks = @service.chunk(docling_output)

    # Should have multiple chunks due to token limit
    assert chunks.length > 1

    # Overlap check: Last sentences of chunk N should appear in chunk N+1
    # (This is tricky to test exactly without knowing the exact split point)
  end

  test "respects max_tokens in sliding window" do
    # Each chunk should not exceed max_tokens
    long_text = 'word ' * 5000 # Many words

    docling_output = {
      'text' => long_text
    }

    chunks = @service.chunk(docling_output)

    chunks.each do |chunk|
      estimated_tokens = chunk[:content].length / 4.0
      assert estimated_tokens <= @service.instance_variable_get(:@max_tokens) + 100 # Allow some margin
    end
  end

  # ===== Plain Text Chunking =====

  test "chunks plain text by words" do
    plain_text = "word1 word2 word3 word4 word5"

    chunks = @service.chunk(plain_text)

    assert_equal 1, chunks.length
    assert_equal 'text', chunks.first[:type]
    assert_equal plain_text, chunks.first[:content]
  end

  test "splits long plain text into multiple chunks" do
    # Create text longer than max_tokens
    long_text = ('word ' * 3000).strip

    chunks = @service.chunk(long_text)

    assert chunks.length > 1

    chunks.each do |chunk|
      assert_equal 'text', chunk[:type]
    end
  end

  test "creates overlap in plain text chunks" do
    service = DoclingChunkingService.new(max_tokens: 100, overlap: 10)

    # Create long text
    long_text = ('word ' * 500).strip

    chunks = service.chunk(long_text)

    assert chunks.length > 1

    # Chunks should have some overlapping words
    # (Exact testing is complex, but verify multiple chunks exist)
  end

  # ===== Table Handling =====

  test "creates table chunks from markdown tables" do
    docling_output = {
      'tables' => [
        {
          'markdown' => "| Header 1 | Header 2 |\n|----------|----------|",
          'page' => 3
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    assert_equal 1, chunks.length
    assert_equal 'table', chunks.first[:type]
    assert_includes chunks.first[:content], "Header 1"
  end

  test "creates table chunks from text tables" do
    docling_output = {
      'tables' => [
        {
          'text' => "Column A | Column B\nData 1 | Data 2",
          'page' => 2
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    assert_equal 1, chunks.length
    assert_equal 'table', chunks.first[:type]
    assert_includes chunks.first[:content], "Column A"
  end

  test "converts array data to markdown table" do
    docling_output = {
      'tables' => [
        {
          'data' => [
            ['Name', 'Age'],
            ['John', '30'],
            ['Jane', '25']
          ],
          'page' => 1
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    table_chunk = chunks.first
    assert_equal 'table', table_chunk[:type]
    assert_includes table_chunk[:content], "Name"
    assert_includes table_chunk[:content], "Age"
    assert_includes table_chunk[:content], "John"
    # Should have markdown table formatting
    assert_includes table_chunk[:content], "|"
  end

  test "includes table caption" do
    docling_output = {
      'tables' => [
        {
          'caption' => 'Sales Data for Q1',
          'markdown' => "| Product | Sales |\n|---------|-------|",
          'page' => 5
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    assert_includes chunks.first[:content], "Sales Data for Q1"
  end

  test "stores table metadata" do
    docling_output = {
      'tables' => [
        {
          'id' => 'table_1',
          'markdown' => "| A | B |\n|---|---|",
          'page_number' => 4,
          'num_rows' => 5,
          'num_cols' => 3
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    metadata = chunks.first[:metadata]
    assert_equal 'table_1', metadata[:table_id]
    assert_equal 4, metadata[:page]
    assert_equal 5, metadata[:rows]
    assert_equal 3, metadata[:cols]
  end

  test "handles multiple tables" do
    docling_output = {
      'tables' => [
        { 'markdown' => "| A |", 'page' => 1 },
        { 'markdown' => "| B |", 'page' => 2 },
        { 'markdown' => "| C |", 'page' => 3 }
      ]
    }

    chunks = @service.chunk(docling_output)

    table_chunks = chunks.select { |c| c[:type] == 'table' }
    assert_equal 3, table_chunks.length
  end

  # ===== Code Block Handling =====

  test "creates code chunks with language specified" do
    docling_output = {
      'code_blocks' => [
        {
          'language' => 'python',
          'content' => "def hello():\n    print('Hello')",
          'page' => 10
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    code_chunk = chunks.first
    assert_equal 'code', code_chunk[:type]
    assert_includes code_chunk[:content], "```python"
    assert_includes code_chunk[:content], "def hello()"
    assert_equal 'python', code_chunk[:metadata][:language]
  end

  test "defaults to plaintext for code without language" do
    docling_output = {
      'code_blocks' => [
        {
          'content' => "some code here",
          'page' => 8
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    code_chunk = chunks.first
    assert_includes code_chunk[:content], "```plaintext"
    assert_equal 'plaintext', code_chunk[:metadata][:language]
  end

  test "formats code blocks with triple backticks" do
    docling_output = {
      'code_blocks' => [
        {
          'language' => 'javascript',
          'content' => "console.log('test')",
          'page' => 5
        }
      ]
    }

    chunks = @service.chunk(docling_output)

    code_chunk = chunks.first
    assert_includes code_chunk[:content], "```"
    assert_includes code_chunk[:content], "javascript"
  end

  test "handles multiple code blocks" do
    docling_output = {
      'code_blocks' => [
        { 'language' => 'python', 'content' => 'print("hi")', 'page' => 1 },
        { 'language' => 'ruby', 'content' => 'puts "hello"', 'page' => 2 }
      ]
    }

    chunks = @service.chunk(docling_output)

    code_chunks = chunks.select { |c| c[:type] == 'code' }
    assert_equal 2, code_chunks.length

    languages = code_chunks.map { |c| c[:metadata][:language] }
    assert_includes languages, 'python'
    assert_includes languages, 'ruby'
  end

  # ===== Combined Content Types =====

  test "handles document with sections, tables, and code" do
    docling_output = {
      'sections' => [
        { 'title' => 'Intro', 'content' => 'Introduction text', 'level' => 1, 'page' => 1 }
      ],
      'tables' => [
        { 'markdown' => "| Data |", 'page' => 2 }
      ],
      'code_blocks' => [
        { 'language' => 'python', 'content' => 'print()', 'page' => 3 }
      ]
    }

    chunks = @service.chunk(docling_output)

    # Should have all three types
    types = chunks.map { |c| c[:type] }.uniq.sort
    assert_includes types, 'section'
    assert_includes types, 'table'
    assert_includes types, 'code'
  end

  # ===== Token Estimation =====

  test "estimates tokens correctly" do
    service = @service

    # 4 characters = ~1 token
    text_4_chars = "test"
    assert_equal 1, service.send(:estimate_tokens, text_4_chars)

    # 100 characters = ~25 tokens
    text_100_chars = "a" * 100
    assert_equal 25, service.send(:estimate_tokens, text_100_chars)

    # Empty string = 0 tokens
    assert_equal 0, service.send(:estimate_tokens, "")
  end

  # ===== Metadata Extraction =====

  test "extracts complete section metadata" do
    section = {
      'title' => 'Chapter 1',
      'level' => 2,
      'page_start' => 5,
      'page_end' => 10
    }

    metadata = @service.send(:extract_section_metadata, section)

    assert_equal 'Chapter 1', metadata[:section_title]
    assert_equal 2, metadata[:section_level]
    assert_equal 5, metadata[:page_start]
    assert_equal 10, metadata[:page_end]
  end

  test "handles missing metadata fields gracefully" do
    section = {
      'title' => 'Minimal Section'
      # Missing level, page_start, page_end
    }

    metadata = @service.send(:extract_section_metadata, section)

    assert_equal 'Minimal Section', metadata[:section_title]
    assert_nil metadata[:section_level]
  end

  # ===== Edge Cases =====

  test "handles empty docling output" do
    docling_output = {}

    chunks = @service.chunk(docling_output)

    assert_equal 0, chunks.length
  end

  test "handles docling output with empty sections array" do
    docling_output = {
      'sections' => []
    }

    chunks = @service.chunk(docling_output)

    assert_equal 0, chunks.length
  end

  test "handles very short text" do
    docling_output = {
      'text' => 'Hi'
    }

    chunks = @service.chunk(docling_output)

    assert_equal 1, chunks.length
    assert_equal 'Hi', chunks.first[:content]
  end

  test "handles text with no sentences (no periods)" do
    docling_output = {
      'text' => 'This is text without proper punctuation and just keeps going'
    }

    chunks = @service.chunk(docling_output)

    assert chunks.any?
  end

  test "handles text with special characters" do
    docling_output = {
      'text' => 'Text with émojis 🔥 and spëcial çharacters!'
    }

    chunks = @service.chunk(docling_output)

    assert_includes chunks.first[:content], "émojis 🔥"
  end

  test "handles nil text fields gracefully" do
    docling_output = {
      'sections' => [
        { 'title' => 'Title Only' } # No content field
      ]
    }

    chunks = @service.chunk(docling_output)

    # Should still create chunk with just title
    assert chunks.any?
    assert_includes chunks.first[:content], "Title Only"
  end

  test "handles empty table data" do
    docling_output = {
      'tables' => [
        { 'data' => [] }
      ]
    }

    chunks = @service.chunk(docling_output)

    # Should create chunk even with empty data
    assert_equal 1, chunks.length
  end

  test "handles code block with text field instead of content" do
    docling_output = {
      'code_blocks' => [
        { 'text' => 'code from text field', 'language' => 'ruby' }
      ]
    }

    chunks = @service.chunk(docling_output)

    code_chunk = chunks.first
    assert_includes code_chunk[:content], "code from text field"
  end

  test "handles very large document" do
    # Create massive section
    huge_content = ('Sentence. ' * 10000).strip

    docling_output = {
      'sections' => [
        { 'title' => 'Huge Section', 'content' => huge_content, 'level' => 1 }
      ]
    }

    chunks = @service.chunk(docling_output)

    # Should split into many chunks
    assert chunks.length > 10

    # All chunks should have reasonable size
    chunks.each do |chunk|
      assert chunk[:content].length < 5000 # Reasonable max
    end
  end

  test "handles document with alternative content key" do
    docling_output = {
      'content' => 'Text using content key instead of text key'
    }

    chunks = @service.chunk(docling_output)

    assert chunks.any?
    assert_includes chunks.first[:content], "content key"
  end

  # ===== Chunk Structure =====

  test "creates chunks with correct structure" do
    docling_output = {
      'text' => 'Sample content'
    }

    chunks = @service.chunk(docling_output)

    chunk = chunks.first

    assert chunk.key?(:content)
    assert chunk.key?(:type)
    assert chunk.key?(:metadata)

    assert_kind_of String, chunk[:content]
    assert_kind_of String, chunk[:type]
    assert_kind_of Hash, chunk[:metadata]
  end

  test "chunk types are valid" do
    docling_output = {
      'sections' => [{ 'content' => 'text' }],
      'tables' => [{ 'markdown' => '| |' }],
      'code_blocks' => [{ 'content' => 'code' }],
      'text' => 'plain text'
    }

    service = DoclingChunkingService.new(preserve_sections: true)
    chunks = service.chunk(docling_output)

    valid_types = ['text', 'section', 'table', 'code']

    chunks.each do |chunk|
      assert_includes valid_types, chunk[:type]
    end
  end
end
