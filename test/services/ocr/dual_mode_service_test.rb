# test/services/ocr/dual_mode_service_test.rb
require "test_helper"

module Ocr
  class DualModeServiceTest < ActiveSupport::TestCase
    setup do
      @entity = entities(:one)
      @service = DualModeService.instance

      # Create test file
      @test_file = Rails.root.join('tmp', 'test_ocr_document.txt')
      FileUtils.mkdir_p(File.dirname(@test_file))
      File.write(@test_file, "Sample OCR test document content\nWith multiple lines\nAnd some data")
    end

    teardown do
      FileUtils.rm_f(@test_file) if @test_file && File.exist?(@test_file)
    end

    test "determines provider from options" do
      provider = @service.send(:determine_provider, @test_file, { provider: 'textract' })
      assert_equal :textract, provider
    end

    test "determines provider from environment variable" do
      ENV.stub :fetch, 'docling' do
        provider = @service.send(:determine_provider, @test_file, {})
        assert_equal :docling, provider
      end
    end

    test "defaults to auto provider selection" do
      ENV.stub :fetch, 'auto' do
        provider = @service.send(:determine_provider, @test_file, {})
        assert_equal :auto, provider
      end
    end

    test "detects document type from filename" do
      assert_equal 'invoice', @service.send(:detect_document_type, 'invoice_2024.pdf', {})
      assert_equal 'receipt', @service.send(:detect_document_type, 'receipt_store.jpg', {})
      assert_equal 'form', @service.send(:detect_document_type, 'application_form.pdf', {})
      assert_equal 'id', @service.send(:detect_document_type, 'drivers_license.jpg', {})
      assert_equal 'bank_statement', @service.send(:detect_document_type, 'statement_jan.pdf', {})
      assert_equal 'general', @service.send(:detect_document_type, 'random_document.pdf', {})
    end

    test "uses provided document type from options" do
      doc_type = @service.send(:detect_document_type, 'file.pdf', { document_type: 'contract' })
      assert_equal 'contract', doc_type
    end

    test "prefers Textract for invoice documents" do
      should_use = @service.send(:should_use_textract?, 'invoice', 10.0, {})
      assert should_use, "Should use Textract for invoices"
    end

    test "prefers Textract for receipt documents" do
      should_use = @service.send(:should_use_textract?, 'receipt', 2.0, {})
      assert should_use, "Should use Textract for receipts"
    end

    test "prefers Docling for small general documents" do
      should_use = @service.send(:should_use_textract?, 'general', 3.0, {})
      assert_not should_use, "Should use Docling for small documents"
    end

    test "prefers Textract for large documents" do
      should_use = @service.send(:should_use_textract?, 'general', 15.0, {})
      assert should_use, "Should use Textract for large documents"
    end

    test "uses Textract when high accuracy requested" do
      should_use = @service.send(:should_use_textract?, 'general', 2.0, { high_accuracy: true })
      assert should_use, "Should use Textract for high accuracy"
    end

    test "uses Textract when form extraction requested" do
      should_use = @service.send(:should_use_textract?, 'general', 2.0, { extract_forms: true })
      assert should_use, "Should use Textract for form extraction"
    end

    test "checks Textract availability with environment variables" do
      ENV.stub :[], ->(key) { key == 'TEXTRACT_ENABLED' ? 'true' : 'test_key' } do
        Aws.stub_const(:TextractService, Class.new) do
          assert @service.send(:textract_available?)
        end
      end
    end

    test "Textract unavailable without env vars" do
      ENV.stub :[], nil do
        assert_not @service.send(:textract_available?)
      end
    end

    test "checks Docling availability" do
      # Mock DoclingBridgeService
      mock_service = Minitest::Mock.new
      mock_service.expect :available?, true

      Object.stub_const(:DoclingBridgeService, Class.new) do
        DoclingBridgeService.stub :new, mock_service do
          assert @service.send(:docling_available?)
        end
      end

      mock_service.verify
    end

    test "fallback enabled by default" do
      ENV.stub :fetch, 'true' do
        assert @service.send(:fallback_enabled?)
      end
    end

    test "shadow mode disabled by default" do
      ENV.stub :[], nil do
        assert_not @service.send(:shadow_mode_enabled?)
      end
    end

    test "formats Textract results correctly" do
      raw_result = {
        pages: [{ page_number: 1, text: 'Page 1 content' }],
        raw_text: 'Full document text',
        tables: [{ rows: [] }],
        forms: [{ key: 'value' }],
        metadata: { confidence: 0.95 }
      }

      formatted = @service.send(:format_result, raw_result, :textract)

      assert_equal :textract, formatted[:provider]
      assert_equal 1, formatted[:pages].count
      assert_equal 'Full document text', formatted[:raw_text]
      assert_equal 1, formatted[:tables].count
      assert_equal 1, formatted[:forms].count
      assert formatted[:metadata][:processed_at].present?
    end

    test "formats Docling results correctly" do
      raw_result = {
        chunks: [
          { content: 'Chunk 1 text', metadata: { page: 1, type: 'text' } },
          { content: 'Chunk 2 text', metadata: { page: 1, type: 'text' } },
          { content: '| Header |\n| Data |', metadata: { page: 2, type: 'table' } }
        ],
        metadata: { total_chunks: 3 }
      }

      formatted = @service.send(:format_result, raw_result, :docling)

      assert_equal :docling, formatted[:provider]
      assert_equal 2, formatted[:pages].count  # 2 pages
      assert formatted[:raw_text].present?
      assert formatted[:pages].first[:tables].present?
    end

    test "parses markdown tables from content" do
      table_content = <<~TABLE
        | Name | Age | City |
        |------|-----|------|
        | John | 30  | NYC  |
        | Jane | 25  | LA   |
      TABLE

      parsed = @service.send(:parse_table_from_content, table_content)

      assert_equal 3, parsed.count  # Header + 2 data rows
      assert_equal ['Name', 'Age', 'City'], parsed.first
      assert_equal ['John', '30', 'NYC'], parsed[1]
    end

    test "calculates similarity between identical texts" do
      results = {
        textract: { raw_text: 'Same text content' },
        docling: { raw_text: 'Same text content' }
      }

      similarity = @service.send(:calculate_similarity, results)
      assert_equal 1.0, similarity
    end

    test "calculates similarity between different texts" do
      results = {
        textract: { raw_text: 'Document A content' },
        docling: { raw_text: 'Document B content' }
      }

      similarity = @service.send(:calculate_similarity, results)
      assert similarity < 1.0
      assert similarity > 0.0
    end

    test "returns nil similarity when texts missing" do
      results = {
        textract: { raw_text: nil },
        docling: { raw_text: 'Some text' }
      }

      similarity = @service.send(:calculate_similarity, results)
      assert_nil similarity
    end

    test "recommends provider based on success" do
      results = {
        textract: { raw_text: 'Text', tables: [{ data: [] }] },
        docling: { error: 'Failed' }
      }
      timings = { textract: 2.0, docling: 1.0 }

      recommendation = @service.send(:recommend_provider, results, timings, @test_file)

      assert_includes recommendation, "Only Textract succeeded"
    end

    test "recommends Docling for cost savings on small files" do
      small_file = Rails.root.join('tmp', 'small_test.txt')
      File.write(small_file, 'A' * 1000)  # 1KB file

      results = {
        textract: { raw_text: 'Text' },
        docling: { raw_text: 'Text' }
      }
      timings = { textract: 2.0, docling: 1.5 }

      recommendation = @service.send(:recommend_provider, results, timings, small_file)

      assert_includes recommendation, "cost savings on small documents"

      FileUtils.rm_f(small_file)
    end

    test "recommends Textract when it detects tables" do
      results = {
        textract: { raw_text: 'Text', tables: [{ data: [['A', 'B']] }] },
        docling: { raw_text: 'Text', tables: [] }
      }
      timings = { textract: 2.0, docling: 1.0 }

      recommendation = @service.send(:recommend_provider, results, timings, @test_file)

      assert_includes recommendation, "Textract detected tables"
    end

    test "process document tracks metrics" do
      mock_docling_service = Minitest::Mock.new
      mock_docling_service.expect :process_document, {
        chunks: [{ content: 'Test', metadata: { page: 1 } }],
        metadata: {}
      }, [String, Hash]

      mock_docling_service.expect :available?, true

      Object.stub_const(:DoclingBridgeService, Class.new) do
        DoclingBridgeService.stub :new, mock_docling_service do
          result = @service.process_document(@entity, @test_file, provider: 'docling')

          assert_equal :docling, @service.metrics[:provider]
          assert @service.metrics[:processing_time] > 0
        end
      end

      mock_docling_service.verify
    end

    test "process document with Textract fallback to Docling" do
      # Mock Textract as unavailable
      @service.stub :textract_available?, false do
        # Mock Docling as available
        mock_docling_service = Minitest::Mock.new
        mock_docling_service.expect :process_document, {
          chunks: [{ content: 'Fallback text', metadata: { page: 1 } }],
          metadata: {}
        }, [String, Hash]
        mock_docling_service.expect :available?, true

        Object.stub_const(:DoclingBridgeService, Class.new) do
          DoclingBridgeService.stub :new, mock_docling_service do
            result = @service.send(:process_with_textract, @entity, @test_file, {})

            assert_equal :docling, result[:provider]
            assert @service.metrics[:fallback_used]
          end
        end

        mock_docling_service.verify
      end
    end

    test "raises error when neither provider available" do
      @service.stub :textract_available?, false do
        @service.stub :docling_available?, false do
          assert_raises RuntimeError do
            @service.send(:process_with_docling, @entity, @test_file, {})
          end
        end
      end
    end

    test "enhances result with Comprehend when enabled" do
      result = {
        raw_text: 'Test document about Amazon in Seattle',
        pages: [],
        tables: [],
        forms: []
      }

      mock_comprehend = Minitest::Mock.new
      mock_comprehend.expect :analyze_document, {
        entities: [{ text: 'Amazon', type: 'ORGANIZATION' }],
        key_phrases: [{ text: 'Test document', score: 0.9 }],
        sentiment: { sentiment: :neutral },
        language: { language_code: 'en' }
      }, [String]

      Aws::ComprehendService.stub :new, mock_comprehend do
        @service.stub :comprehend_enabled?, true do
          enhanced = @service.send(:enhance_with_comprehend, @entity, result)

          assert enhanced[:nlp_analysis].present?
          assert enhanced[:nlp_analysis][:entities].present?
          assert enhanced[:nlp_analysis][:sentiment].present?
        end
      end

      mock_comprehend.verify
    end

    test "handles Comprehend enhancement errors gracefully" do
      result = { raw_text: 'Test', pages: [] }

      Aws::ComprehendService.stub :new, ->{ raise StandardError.new("API Error") } do
        @service.stub :comprehend_enabled?, true do
          enhanced = @service.send(:enhance_with_comprehend, @entity, result)

          # Should return original result without enhancement
          assert_nil enhanced[:nlp_analysis]
        end
      end
    end

    test "compare providers runs both and returns comparison" do
      # Mock both services
      mock_textract = Minitest::Mock.new
      mock_textract.expect :process_document, {
        raw_text: 'Textract result',
        pages: [],
        tables: [],
        forms: [],
        metadata: {}
      }, [String, Hash]

      mock_docling = Minitest::Mock.new
      mock_docling.expect :process_document, {
        chunks: [{ content: 'Docling result', metadata: { page: 1 } }],
        metadata: {}
      }, [String, Hash]
      mock_docling.expect :available?, true

      @service.stub :textract_available?, true do
        @service.stub :docling_available?, true do
          Aws::TextractService.stub :new, mock_textract do
            Object.stub_const(:DoclingBridgeService, Class.new) do
              DoclingBridgeService.stub :new, mock_docling do
                comparison = @service.compare_providers(@entity, @test_file)

                assert comparison[:results][:textract].present?
                assert comparison[:results][:docling].present?
                assert comparison[:timings][:textract].present?
                assert comparison[:timings][:docling].present?
                assert comparison[:recommendation].present?
              end
            end
          end
        end
      end

      mock_textract.verify
      mock_docling.verify
    end

    test "compare providers handles failures gracefully" do
      @service.stub :textract_available?, true do
        @service.stub :docling_available?, false do
          Aws::TextractService.stub :new, ->(_) { raise StandardError.new("Textract Error") } do
            comparison = @service.compare_providers(@entity, @test_file)

            assert comparison[:results][:textract][:error].present?
            assert_includes comparison[:recommendation], "Both providers failed"
          end
        end
      end
    end

    test "logs metrics for entity with tracking enabled" do
      @entity.stub :track_ocr_metrics?, true do
        @service.instance_variable_set(:@metrics, {
          provider: :textract,
          fallback_used: false,
          processing_time: 1.5
        })

        assert_difference 'OcrMetric.count', 1 do
          @service.send(:log_metrics, @entity, @test_file)
        end

        metric = OcrMetric.last
        assert_equal @entity, metric.entity
        assert_equal 'textract', metric.provider
        assert_equal false, metric.fallback_used
        assert metric.processing_time_ms > 0
      end
    end

    test "handles metric logging errors gracefully" do
      @entity.stub :track_ocr_metrics?, true do
        OcrMetric.stub :create!, ->(*) { raise StandardError.new("DB Error") } do
          # Should not raise error
          assert_nothing_raised do
            @service.send(:log_metrics, @entity, @test_file)
          end
        end
      end
    end
  end
end
