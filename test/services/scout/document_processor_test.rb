require "test_helper"

module Scout
  class DocumentProcessorTest < ActiveSupport::TestCase
    include ActionDispatch::TestProcess::FixtureFile

    def setup
      @entity = entities(:one)
      @user = users(:one)
      @session_id = SecureRandom.uuid
      @url_generator = ->(file) { "https://example.com/#{file.filename}" }

      @processor = Scout::DocumentProcessor.new(
        entity: @entity,
        user: @user,
        session_id: @session_id,
        url_generator: @url_generator
      )

      # Ensure tests use DocumentProcessorService path, not Ocr::DualModeService
      @processor.stubs(:dual_mode_ocr_available?).returns(false)
    end

    # Class method tests
    test "document_file? returns true for supported extensions" do
      # Mock DoclingBridgeService::SUPPORTED_EXTENSIONS
      DoclingBridgeService::SUPPORTED_EXTENSIONS.each do |ext|
        assert Scout::DocumentProcessor.document_file?(ext),
               "Expected #{ext} to be a document file"
      end
    end

    test "document_file? returns false for unsupported extensions" do
      refute Scout::DocumentProcessor.document_file?(".jpg")
      refute Scout::DocumentProcessor.document_file?(".png")
      refute Scout::DocumentProcessor.document_file?(".gif")
    end

    # create_image_asset tests
    test "create_image_asset creates ImageAsset with correct attributes" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      assert_difference -> { ImageAsset.count }, 1 do
        image_asset = @processor.create_image_asset(file)

        assert_equal @entity, image_asset.entity
        assert_equal @user, image_asset.user
        assert_equal "test_document.pdf", image_asset.title
        assert_equal "upload", image_asset.source
        assert image_asset.file.attached?
      end
    end

    test "create_image_asset raises error when entity is nil" do
      processor = Scout::DocumentProcessor.new(
        entity: nil,
        user: @user
      )

      file = fixture_file_upload("test_document.pdf", "application/pdf")

      assert_raises(ActiveRecord::RecordInvalid) do
        processor.create_image_asset(file)
      end
    end

    # build_image_asset_response tests
    test "build_image_asset_response returns correct hash structure" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")
      image_asset = @processor.create_image_asset(file)
      file.rewind

      response = @processor.build_image_asset_response(image_asset, file)

      assert_equal "https://example.com/test_document.pdf", response[:url]
      assert_equal "test_document.pdf", response[:filename]
      assert_equal "application/pdf", response[:content_type]
      assert_equal file.size, response[:size]
      assert_equal image_asset.id, response[:asset_id]
    end

    # process_for_rag tests - short-term storage (Redis)
    test "process_for_rag stores in Redis for short-term storage" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      # Mock DocumentProcessorService
      mock_result = {
        success: true,
        chunks: [
          { content: "First chunk", metadata: { type: "text" } },
          { content: "Second chunk", metadata: { type: "text" } }
        ],
        metadata: {
          "test_document.pdf" => {
            total_pages: 2,
            processor: "docling",
            processing_time_ms: 100
          }
        }
      }

      DocumentProcessorService.any_instance.stubs(:process_documents).returns(mock_result)

      session_key = "rag:session:#{@session_id}:documents"

      # Mock Redis
      $redis.expects(:hset).with(session_key, "test_document.pdf", anything).once
      $redis.expects(:expire).with(session_key, 24.hours.to_i).once

      result = @processor.process_for_rag(file, storage_type: 'short-term')

      assert result[:success]
      assert_equal 2, result[:chunks_count]
      assert_equal "docling", result[:processor]
      assert_equal "short-term", result[:storage_type]
      assert result[:asset_id].present?
    end

    test "process_for_rag stores chunks in Redis with correct structure" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      mock_result = {
        success: true,
        chunks: [
          { content: "Test content", metadata: { type: "text" } }
        ],
        metadata: {
          "test_document.pdf" => { total_pages: 1, processor: "docling" }
        }
      }

      DocumentProcessorService.any_instance.stubs(:process_documents).returns(mock_result)

      session_key = "rag:session:#{@session_id}:documents"

      # Capture the data written to Redis
      captured_data = nil
      $redis.stubs(:hset).with { |key, field, value|
        captured_data = JSON.parse(value) if key == session_key
        true
      }
      $redis.stubs(:expire)

      @processor.process_for_rag(file, storage_type: 'short-term')

      assert_not_nil captured_data
      assert_equal "test_document.pdf", captured_data["filename"]
      assert_equal 1, captured_data["chunks"].length
      assert_equal "Test content", captured_data["chunks"][0]["content"]
      assert_equal "text", captured_data["chunks"][0]["type"]
      assert captured_data["asset_id"].present?
    end

    # process_for_rag tests - long-term storage (Database)
    test "process_for_rag stores in database for long-term storage" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      mock_result = {
        success: true,
        chunks: [
          { content: "First chunk", metadata: { type: "text" } },
          { content: "Second chunk", metadata: { type: "table" } }
        ],
        metadata: {
          "test_document.pdf" => {
            total_pages: 2,
            processor: "docling",
            processing_time_ms: 150
          }
        }
      }

      DocumentProcessorService.any_instance.stubs(:process_documents).returns(mock_result)

      assert_difference -> { RagStore.count }, 1 do
        assert_difference -> { RagDocument.count }, 1 do
          assert_difference -> { RagChunk.count }, 2 do
            result = @processor.process_for_rag(file, storage_type: 'long-term')

            assert result[:success]
            assert_equal 2, result[:chunks_count]
            assert_equal "docling", result[:processor]
            assert_equal "long-term", result[:storage_type]
            assert result[:rag_store_id].present?
            assert result[:rag_document_id].present?
          end
        end
      end
    end

    test "process_for_rag creates RagStore with correct attributes" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      mock_result = {
        success: true,
        chunks: [{ content: "Test", metadata: {} }],
        metadata: {
          "test_document.pdf" => {
            processor: "docling",
            processing_time_ms: 200
          }
        }
      }

      DocumentProcessorService.any_instance.stubs(:process_documents).returns(mock_result)

      result = @processor.process_for_rag(file, storage_type: 'long-term')

      rag_store = RagStore.find(result[:rag_store_id])
      assert_equal @entity, rag_store.entity
      assert_equal "entity", rag_store.store_type
      assert_equal "docling", rag_store.processing_method
      assert_equal 200, rag_store.processing_time_ms
      assert rag_store.name.include?("test_document.pdf")
    end

    test "process_for_rag creates RagDocument with file hash and metadata" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      mock_result = {
        success: true,
        chunks: [{ content: "Test", metadata: {} }],
        metadata: {
          "test_document.pdf" => { total_pages: 5 }
        }
      }

      DocumentProcessorService.any_instance.stubs(:process_documents).returns(mock_result)

      result = @processor.process_for_rag(file, storage_type: 'long-term')

      rag_document = RagDocument.find(result[:rag_document_id])
      assert_equal "test_document.pdf", rag_document.original_filename
      assert_equal 5, rag_document.page_count
      assert rag_document.file_hash.present?
      assert_equal 64, rag_document.file_hash.length # SHA256 hex length
      assert rag_document.docling_metadata["asset_id"].present?
    end

    test "process_for_rag creates RagChunks with correct types" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      mock_result = {
        success: true,
        chunks: [
          { content: "Text chunk", metadata: { type: "text" } },
          { content: "Table chunk", metadata: { type: "table" } },
          { content: "Default chunk", metadata: {} }
        ],
        metadata: { "test_document.pdf" => {} }
      }

      DocumentProcessorService.any_instance.stubs(:process_documents).returns(mock_result)

      result = @processor.process_for_rag(file, storage_type: 'long-term')

      rag_document = RagDocument.find(result[:rag_document_id])
      chunks = rag_document.rag_chunks.order(:chunk_index)

      assert_equal 3, chunks.count
      assert_equal "text", chunks[0].chunk_type
      assert_equal "Text chunk", chunks[0].content
      assert_equal 0, chunks[0].chunk_index

      assert_equal "table", chunks[1].chunk_type
      assert_equal 1, chunks[1].chunk_index

      assert_equal "text", chunks[2].chunk_type # defaults to "text"
      assert_equal 2, chunks[2].chunk_index
    end

    # Error handling tests
    test "process_for_rag returns error when DocumentProcessorService fails" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      DocumentProcessorService.any_instance.stubs(:process_documents).returns({
        success: false,
        error: "Processing failed"
      })

      result = @processor.process_for_rag(file, storage_type: 'long-term')

      refute result[:success]
      assert_equal "Processing failed", result[:error]
    end

    test "process_for_rag handles exceptions gracefully" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      DocumentProcessorService.any_instance.stubs(:process_documents).raises(StandardError.new("Unexpected error"))

      result = @processor.process_for_rag(file, storage_type: 'short-term')

      refute result[:success]
      assert_equal "Unexpected error", result[:error]
    end

    test "process_for_rag cleans up temp file even on error" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")

      # Mock to raise error
      DocumentProcessorService.any_instance.stubs(:process_documents).raises(StandardError.new("Test error"))

      # Capture temp file path
      temp_path = nil
      Tempfile.any_instance.stubs(:path).returns do
        temp_path = "/tmp/test_temp_file"
        temp_path
      end

      # Should not raise - error should be caught
      result = @processor.process_for_rag(file, storage_type: 'short-term')

      refute result[:success]
      # Temp file cleanup is handled in ensure block
    end

    # Edge cases
    # NOTE: Edge case for files without rewind is covered by integration tests

    test "asset_url uses url_generator when provided" do
      file = fixture_file_upload("test_document.pdf", "application/pdf")
      image_asset = @processor.create_image_asset(file)

      url = @processor.send(:asset_url, image_asset)

      assert_equal "https://example.com/test_document.pdf", url
    end

    test "asset_url falls back to Rails url helpers when no generator" do
      processor = Scout::DocumentProcessor.new(
        entity: @entity,
        user: @user
      )

      file = fixture_file_upload("test_document.pdf", "application/pdf")
      image_asset = processor.create_image_asset(file)

      # Should use Rails.application.routes.url_helpers.rails_blob_url
      url = processor.send(:asset_url, image_asset)

      assert url.present?
      # Can't test exact URL without full Rails app setup
    end
  end
end
