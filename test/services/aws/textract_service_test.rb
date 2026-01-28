# test/services/aws/textract_service_test.rb
require "test_helper"

module Aws
  class TextractServiceTest < ActiveSupport::TestCase
    setup do
      @entity = entities(:one)

      # Set up environment variables
      ENV['AWS_REGION'] = 'us-east-1'
      ENV['AWS_ACCESS_KEY_ID'] = 'test_key'
      ENV['AWS_SECRET_ACCESS_KEY'] = 'test_secret'
      ENV['RAG_BUCKET'] = 'test-bucket'

      # Create unique test file per test instance (for parallel test safety)
      @test_file = ::Rails.root.join('tmp', "test_textract_#{Process.pid}_#{Random.rand(10000)}.pdf")
      FileUtils.mkdir_p(File.dirname(@test_file))
      File.write(@test_file, "PDF content placeholder")

      # Create mock clients
      @mock_textract_client = Minitest::Mock.new
      @mock_s3_client = Minitest::Mock.new

      # Initialize service with mocked clients
      @service = TextractService.instance
      @service.instance_variable_set(:@client, @mock_textract_client)
      @service.instance_variable_set(:@s3_client, @mock_s3_client)
    end

    teardown do
      FileUtils.rm_f(@test_file) if @test_file && File.exist?(@test_file)
      ENV.delete('TEXTRACT_SNS_TOPIC_ARN')
      ENV.delete('TEXTRACT_ROLE_ARN')
    end

    test "validates supported file formats" do
      valid_file = ::Rails.root.join('tmp', 'test.pdf')
      File.write(valid_file, 'content')

      assert_nothing_raised do
        @service.send(:validate_file!, valid_file)
      end

      FileUtils.rm_f(valid_file)
    end

    test "rejects unsupported file formats" do
      invalid_file = ::Rails.root.join('tmp', 'test.doc')
      File.write(invalid_file, 'content')

      error = assert_raises ArgumentError do
        @service.send(:validate_file!, invalid_file)
      end

      assert_includes error.message, "Unsupported file format"
      FileUtils.rm_f(invalid_file)
    end

    test "rejects missing files" do
      error = assert_raises ArgumentError do
        @service.send(:validate_file!, '/tmp/nonexistent.pdf')
      end

      assert_includes error.message, "File not found"
    end

    test "rejects files that are too large" do
      # Create a mock file that appears large
      large_file = ::Rails.root.join('tmp', 'large.pdf')
      File.write(large_file, 'content')

      File.stub :size, 600.megabytes do
        error = assert_raises ArgumentError do
          @service.send(:validate_file!, large_file)
        end

        assert_includes error.message, "File too large"
      end

      FileUtils.rm_f(large_file)
    end

    test "uploads file to S3 with metadata" do
      def @mock_s3_client.put_object(params)
        OpenStruct.new(etag: 'test-etag')
      end

      s3_key = @service.send(:upload_to_s3, @entity, @test_file)

      assert s3_key.present?
      assert s3_key.starts_with?("textract/#{@entity.id}/")
      assert s3_key.ends_with?(File.basename(@test_file))
    end

    test "cleans up S3 file after processing" do
      s3_key = "textract/#{@entity.id}/test.pdf"

      # Stub the S3 client's delete_object method
      def @mock_s3_client.delete_object(params)
        nil
      end

      @service.send(:cleanup_s3_file, s3_key)
      # Verify cleanup was called (success if no exception)
      assert true
    end

    test "determines features from options" do
      # Default features
      features = @service.send(:determine_features, {})
      assert_equal ['TABLES', 'LAYOUT'], features

      # With forms
      features = @service.send(:determine_features, { extract_forms: true })
      assert_includes features, 'FORMS'

      # With signatures
      features = @service.send(:determine_features, { detect_signatures: true })
      assert_includes features, 'SIGNATURES'

      # Without tables
      features = @service.send(:determine_features, { extract_tables: false })
      assert_not_includes features, 'TABLES'
    end

    test "identifies single page documents" do
      # Images are single page
      assert @service.send(:single_page_document?, 'test.png')
      assert @service.send(:single_page_document?, 'test.jpg')
      assert @service.send(:single_page_document?, 'test.jpeg')

      # PDFs assumed multi-page
      assert_not @service.send(:single_page_document?, 'test.pdf')
    end

    test "estimates processing time based on file size" do
      head_response = OpenStruct.new(content_length: 5.megabytes)

      # Define method on mock
      def @mock_s3_client.head_object(params)
        OpenStruct.new(content_length: 5.megabytes)
      end

      time = @service.send(:estimate_processing_time, 'test-key')

      assert time > 0
      assert time <= 60
    end

    test "processes single page document synchronously" do
      mock_response = OpenStruct.new(
        blocks: [
          OpenStruct.new(
            block_type: 'PAGE',
            id: 'page-1',
            page: 1,
            confidence: 0.99,
            geometry: nil
          ),
          OpenStruct.new(
            block_type: 'LINE',
            id: 'line-1',
            text: 'Test document text',
            page: 1,
            confidence: 0.98,
            geometry: nil,
            relationships: nil
          )
        ],
        document_metadata: OpenStruct.new(pages: 1),
        job_status: nil,
        job_id: nil,
        analyze_document_model_version: 'v1.0',
        warnings: []
      )

      # Define methods on mocks
      def @mock_s3_client.put_object(params)
        OpenStruct.new(etag: 'test')
      end

      def @mock_textract_client.analyze_document(params)
        OpenStruct.new(
          blocks: [
            OpenStruct.new(
              block_type: 'PAGE',
              id: 'page-1',
              page: 1,
              confidence: 0.99,
              geometry: nil
            ),
            OpenStruct.new(
              block_type: 'LINE',
              id: 'line-1',
              text: 'Test document text',
              page: 1,
              confidence: 0.98,
              geometry: nil,
              relationships: nil
            )
          ],
          document_metadata: OpenStruct.new(pages: 1),
          job_status: nil,
          job_id: nil,
          analyze_document_model_version: 'v1.0',
          warnings: []
        )
      end

      def @mock_s3_client.delete_object(params)
        nil
      end

      # Stub single_page_document? to return true
      @service.stub :single_page_document?, true do
        result = @service.process_document(@entity, @test_file)

        assert result[:pages].present?
        assert result[:raw_text].present?
        assert_includes result[:raw_text], 'Test document text'
      end
    end

    test "processes multi-page document asynchronously" do
      # Define methods on mocks
      def @mock_s3_client.put_object(params)
        OpenStruct.new(etag: 'test')
      end

      def @mock_textract_client.start_document_analysis(params)
        OpenStruct.new(job_id: 'job-123')
      end

      # Stub single_page_document? to return false
      @service.stub :single_page_document?, false do
        # Stub TextractResultJob
        TextractResultJob.stub :perform_later, true do
          result = @service.process_document(@entity, @test_file, cleanup: false)

          assert_equal 'processing', result[:status]
          assert_equal 'job-123', result[:job_id]
          assert result[:estimated_time_seconds].present?
        end
      end
    end

    test "gets job results for succeeded job" do
      mock_response = OpenStruct.new(
        job_id: 'job-123',
        job_status: 'SUCCEEDED',
        next_token: nil,
        blocks: [
          OpenStruct.new(
            block_type: 'LINE',
            id: 'line-1',
            text: 'Completed document text',
            page: 1,
            confidence: 0.95,
            geometry: nil,
            relationships: nil
          )
        ],
        document_metadata: OpenStruct.new(pages: 1),
        analyze_document_model_version: 'v1.0',
        warnings: []
      )

      # Define method on mock
      def @mock_textract_client.get_document_analysis(params)
        OpenStruct.new(
          job_id: 'job-123',
          job_status: 'SUCCEEDED',
          next_token: nil,
          blocks: [
            OpenStruct.new(
              block_type: 'LINE',
              id: 'line-1',
              text: 'Completed document text',
              page: 1,
              confidence: 0.95,
              geometry: nil,
              relationships: nil
            )
          ],
          document_metadata: OpenStruct.new(pages: 1),
          analyze_document_model_version: 'v1.0',
          warnings: []
        )
      end

      result = @service.get_job_results('job-123')

      assert_equal 'completed', result[:status]
      assert result[:pages].present?
      assert result[:raw_text].present?
    end

    test "gets job results for in progress job" do
      # Define method on mock
      def @mock_textract_client.get_document_analysis(params)
        OpenStruct.new(
          job_id: 'job-123',
          job_status: 'IN_PROGRESS',
          progress_percentage: 45
        )
      end

      result = @service.get_job_results('job-123')

      assert_equal 'processing', result[:status]
      assert_equal 45, result[:progress]
    end

    test "gets job results for failed job" do
      # Define method on mock
      def @mock_textract_client.get_document_analysis(params)
        OpenStruct.new(
          job_id: 'job-123',
          job_status: 'FAILED',
          status_message: 'Processing failed due to invalid format'
        )
      end

      result = @service.get_job_results('job-123')

      assert_equal 'failed', result[:status]
      assert result[:error].present?
    end

    test "extracts tables from document" do
      mock_response = OpenStruct.new(
        blocks: [
          OpenStruct.new(
            block_type: 'TABLE',
            id: 'table-1',
            confidence: 0.95,
            geometry: nil,
            relationships: [
              OpenStruct.new(
                type: 'CHILD',
                ids: ['cell-1', 'cell-2']
              )
            ]
          ),
          OpenStruct.new(
            block_type: 'CELL',
            id: 'cell-1',
            row_index: 1,
            column_index: 1,
            confidence: 0.98,
            relationships: [
              OpenStruct.new(type: 'CHILD', ids: ['word-1'])
            ]
          ),
          OpenStruct.new(
            block_type: 'WORD',
            id: 'word-1',
            text: 'Header'
          ),
          OpenStruct.new(
            block_type: 'CELL',
            id: 'cell-2',
            row_index: 1,
            column_index: 2,
            confidence: 0.97,
            relationships: [
              OpenStruct.new(type: 'CHILD', ids: ['word-2'])
            ]
          ),
          OpenStruct.new(
            block_type: 'WORD',
            id: 'word-2',
            text: 'Value'
          )
        ]
      )

      # Define method on mock
      def @mock_textract_client.analyze_document(params)
        OpenStruct.new(
          blocks: [
            OpenStruct.new(
              block_type: 'TABLE',
              id: 'table-1',
              confidence: 0.95,
              geometry: nil,
              relationships: [
                OpenStruct.new(
                  type: 'CHILD',
                  ids: ['cell-1', 'cell-2']
                )
              ]
            ),
            OpenStruct.new(
              block_type: 'CELL',
              id: 'cell-1',
              row_index: 1,
              column_index: 1,
              confidence: 0.98,
              relationships: [
                OpenStruct.new(type: 'CHILD', ids: ['word-1'])
              ]
            ),
            OpenStruct.new(
              block_type: 'WORD',
              id: 'word-1',
              text: 'Header'
            ),
            OpenStruct.new(
              block_type: 'CELL',
              id: 'cell-2',
              row_index: 1,
              column_index: 2,
              confidence: 0.97,
              relationships: [
                OpenStruct.new(type: 'CHILD', ids: ['word-2'])
              ]
            ),
            OpenStruct.new(
              block_type: 'WORD',
              id: 'word-2',
              text: 'Value'
            )
          ]
        )
      end

      tables = @service.extract_tables('test-key')

      assert tables.is_a?(Array)
    end

    test "analyzes expense documents" do
      mock_response = OpenStruct.new(
        expense_documents: [
          OpenStruct.new(
            summary_fields: [
              OpenStruct.new(
                type: OpenStruct.new(text: 'VENDOR_NAME'),
                value_detection: OpenStruct.new(text: 'Acme Corp', confidence: 0.99)
              ),
              OpenStruct.new(
                type: OpenStruct.new(text: 'TOTAL'),
                value_detection: OpenStruct.new(text: '$99.99', confidence: 0.98)
              )
            ],
            line_item_groups: [
              OpenStruct.new(
                line_items: [
                  OpenStruct.new(
                    line_item_expense_fields: [
                      OpenStruct.new(
                        type: OpenStruct.new(text: 'ITEM'),
                        value_detection: OpenStruct.new(text: 'Widget', confidence: 0.97)
                      ),
                      OpenStruct.new(
                        type: OpenStruct.new(text: 'PRICE'),
                        value_detection: OpenStruct.new(text: '$49.99', confidence: 0.96)
                      )
                    ]
                  )
                ]
              )
            ]
          )
        ]
      )

      # Define methods on mocks
      def @mock_s3_client.put_object(params)
        OpenStruct.new(etag: 'test')
      end

      def @mock_textract_client.analyze_expense(params)
        OpenStruct.new(
          expense_documents: [
            OpenStruct.new(
              summary_fields: [
                OpenStruct.new(
                  type: OpenStruct.new(text: 'VENDOR_NAME'),
                  value_detection: OpenStruct.new(text: 'Acme Corp', confidence: 0.99)
                ),
                OpenStruct.new(
                  type: OpenStruct.new(text: 'TOTAL'),
                  value_detection: OpenStruct.new(text: '$99.99', confidence: 0.98)
                )
              ],
              line_item_groups: [
                OpenStruct.new(
                  line_items: [
                    OpenStruct.new(
                      line_item_expense_fields: [
                        OpenStruct.new(
                          type: OpenStruct.new(text: 'ITEM'),
                          value_detection: OpenStruct.new(text: 'Widget', confidence: 0.97)
                        ),
                        OpenStruct.new(
                          type: OpenStruct.new(text: 'PRICE'),
                          value_detection: OpenStruct.new(text: '$49.99', confidence: 0.96)
                        )
                      ]
                    )
                  ]
                )
              ]
            )
          ]
        )
      end

      def @mock_s3_client.delete_object(params)
        nil
      end

      result = @service.analyze_expense(@entity, @test_file)

      assert result[:expenses].present?
      assert_equal 1, result[:expenses].count
      assert result[:expenses].first[:summary_fields]['VENDOR_NAME'].present?
      assert result[:expenses].first[:line_items].present?
    end

    test "analyzes identity documents" do
      mock_response = OpenStruct.new(
        identity_documents: [
          OpenStruct.new(
            identity_document_fields: [
              OpenStruct.new(
                type: OpenStruct.new(text: 'FIRST_NAME'),
                value_detection: OpenStruct.new(text: 'John', confidence: 0.99)
              ),
              OpenStruct.new(
                type: OpenStruct.new(text: 'LAST_NAME'),
                value_detection: OpenStruct.new(text: 'Doe', confidence: 0.98)
              ),
              OpenStruct.new(
                type: OpenStruct.new(text: 'DOCUMENT_TYPE'),
                value_detection: OpenStruct.new(text: 'DRIVERS_LICENSE', confidence: 0.97)
              )
            ]
          )
        ]
      )

      # Define methods on mocks
      def @mock_s3_client.put_object(params)
        OpenStruct.new(etag: 'test')
      end

      def @mock_textract_client.analyze_id(params)
        OpenStruct.new(
          identity_documents: [
            OpenStruct.new(
              identity_document_fields: [
                OpenStruct.new(
                  type: OpenStruct.new(text: 'FIRST_NAME'),
                  value_detection: OpenStruct.new(text: 'John', confidence: 0.99)
                ),
                OpenStruct.new(
                  type: OpenStruct.new(text: 'LAST_NAME'),
                  value_detection: OpenStruct.new(text: 'Doe', confidence: 0.98)
                ),
                OpenStruct.new(
                  type: OpenStruct.new(text: 'DOCUMENT_TYPE'),
                  value_detection: OpenStruct.new(text: 'DRIVERS_LICENSE', confidence: 0.97)
                )
              ]
            )
          ]
        )
      end

      def @mock_s3_client.delete_object(params)
        nil
      end

      result = @service.analyze_identity(@entity, @test_file)

      assert result[:identity_documents].present?
      assert_equal 1, result[:identity_documents].count
      assert_equal 'DRIVERS_LICENSE', result[:identity_documents].first[:document_type]
      assert result[:identity_documents].first[:fields]['FIRST_NAME'].present?
    end

    test "parses geometry correctly" do
      geometry = OpenStruct.new(
        bounding_box: OpenStruct.new(
          width: 0.5,
          height: 0.1,
          left: 0.1,
          top: 0.2
        ),
        polygon: [
          OpenStruct.new(x: 0.1, y: 0.2),
          OpenStruct.new(x: 0.6, y: 0.2),
          OpenStruct.new(x: 0.6, y: 0.3),
          OpenStruct.new(x: 0.1, y: 0.3)
        ]
      )

      parsed = @service.send(:parse_geometry, geometry)

      assert_equal 0.5, parsed[:bounding_box][:width]
      assert_equal 4, parsed[:polygon].count
    end

    test "handles throttling errors as retryable" do
      error = ::Aws::Textract::Errors::ThrottlingException.new(nil, 'Rate limit exceeded')

      assert_raises TextractService::RetryableError do
        @service.send(:handle_textract_error, error)
      end
    end

    test "handles throughput exceeded errors as retryable" do
      error = ::Aws::Textract::Errors::ProvisionedThroughputExceededException.new(nil, 'Throughput exceeded')

      assert_raises TextractService::RetryableError do
        @service.send(:handle_textract_error, error)
      end
    end

    test "handles invalid S3 object errors" do
      error = ::Aws::Textract::Errors::InvalidS3ObjectException.new(nil, 'Invalid S3 object')

      assert_raises ArgumentError do
        @service.send(:handle_textract_error, error)
      end
    end

    test "handles document too large errors" do
      error = ::Aws::Textract::Errors::DocumentTooLargeException.new(nil, 'Document too large')

      assert_raises ArgumentError do
        @service.send(:handle_textract_error, error)
      end
    end

    test "handles bad document errors" do
      error = ::Aws::Textract::Errors::BadDocumentException.new(nil, 'Bad document')

      assert_raises ArgumentError do
        @service.send(:handle_textract_error, error)
      end
    end

    test "notification disabled without SNS topic" do
      assert_not @service.send(:notification_enabled?)
    end

    test "notification enabled with SNS topic" do
      ENV['TEXTRACT_SNS_TOPIC_ARN'] = 'arn:aws:sns:us-east-1:123:topic'

      assert @service.send(:notification_enabled?)
    end

    test "builds notification config when enabled" do
      ENV['TEXTRACT_SNS_TOPIC_ARN'] = 'arn:aws:sns:us-east-1:123:topic'
      ENV['TEXTRACT_ROLE_ARN'] = 'arn:aws:iam::123:role/TextractRole'

      config = @service.send(:notification_config)

      assert config.present?
      assert_equal 'arn:aws:sns:us-east-1:123:topic', config[:sns_topic_arn]
      assert_equal 'arn:aws:iam::123:role/TextractRole', config[:role_arn]
    end
  end
end
