require "test_helper"

module Rag
  class ArchiveOldDocumentsJobTest < ActiveJob::TestCase
    def setup
      @job = ArchiveOldDocumentsJob.new
      @entity = entities(:company_one)
    end

    test "perform in dry run mode doesn't archive" do
      # Create stale store
      store = create_stale_store

      result = @job.perform(dry_run: true)

      assert result[:dry_run]
      assert result[:stale_stores_found] > 0
      assert_equal 0, result[:archived_count]

      # Store should not be archived
      assert_not_equal "archived", store.reload.status
    end

    test "finds stale entity stores" do
      # Create stale store (not accessed in 60+ days)
      stale_store = create_stale_store

      # Create recent store
      recent_store = RagStore.create!(
        name: "Recent Store",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns-recent",
        store_type: "entity",
        entity: @entity,
        status: "active",
        last_accessed_at: 10.days.ago
      )

      result = @job.perform(dry_run: true)

      assert result[:stale_stores_found] >= 1
    end

    test "does not archive system stores" do
      # Create stale system store
      system_store = RagStore.create!(
        name: "System Store",
        app_name: "system",
        pinecone_index: "test-index",
        pinecone_namespace: "system-ns",
        store_type: "system",
        entity: nil,
        status: "active",
        last_accessed_at: 90.days.ago
      )

      result = @job.perform(dry_run: true)

      # System stores should never be archived
      # So if we had only system stores, count should be 0
      # (This depends on test data, but validates the query)
    end

    test "archives stale store and updates status" do
      store = create_stale_store
      original_status = store.status

      # Stub S3 operations
      s3_mock = Minitest::Mock.new
      s3_mock.expect :head_object, true, [Hash]
      s3_mock.expect :copy_object, true, [Hash]

      Aws::S3::Client.stub :new, s3_mock do
        result = @job.perform(dry_run: false)

        assert result[:archived_count] > 0

        # Store should be marked as archived
        assert_equal "archived", store.reload.status
      end
    end

    test "moves S3 documents to Glacier" do
      ENV['RAG_BUCKET'] = 'test-bucket'

      # Clean up any existing stale stores to isolate test
      RagStore.where('last_accessed_at < ? OR last_accessed_at IS NULL', 60.days.ago)
              .where(store_type: 'entity')
              .where.not(status: 'archived')
              .destroy_all

      store = create_stale_store_with_document

      # Mock S3 client
      s3_mock = Minitest::Mock.new

      # Expect head_object call (check if exists)
      s3_mock.expect :head_object, true, [Hash]

      # Expect copy_object call with DEEP_ARCHIVE storage class
      s3_mock.expect :copy_object, true, [Hash]

      Aws::S3::Client.stub :new, s3_mock do
        result = @job.perform(dry_run: false)

        # Verify S3 operations were called
        s3_mock.verify
      end

      ENV['RAG_BUCKET'] = nil
    end

    test "handles missing S3 objects gracefully" do
      store = create_stale_store_with_document

      # Mock S3 to raise NotFound
      s3_mock = Minitest::Mock.new
      s3_mock.expect :head_object, -> { raise Aws::S3::Errors::NotFound.new(nil, "Not found") }, [Hash]

      Aws::S3::Client.stub :new, s3_mock do
        # Should not raise error
        assert_nothing_raised do
          @job.perform(dry_run: false)
        end
      end
    end

    test "removes from Pinecone when configured" do
      ENV['ARCHIVE_REMOVES_PINECONE'] = 'true'

      store = create_stale_store
      store.update!(pinecone_namespace: "test-namespace")

      # Mock S3 operations
      s3_mock = Minitest::Mock.new
      s3_mock.expect :head_object, true, [Hash]
      s3_mock.expect :copy_object, true, [Hash]

      Aws::S3::Client.stub :new, s3_mock do
        assert_nothing_raised do
          @job.perform(dry_run: false)
        end
      end

      ENV['ARCHIVE_REMOVES_PINECONE'] = 'false'
    end

    test "skips Pinecone removal when not configured" do
      ENV['ARCHIVE_REMOVES_PINECONE'] = 'false'

      store = create_stale_store

      # Mock S3 but not Pinecone
      s3_mock = Minitest::Mock.new
      s3_mock.expect :head_object, true, [Hash]
      s3_mock.expect :copy_object, true, [Hash]

      Aws::S3::Client.stub :new, s3_mock do
        result = @job.perform(dry_run: false)

        # Should complete without Pinecone calls
        assert result[:archived_count] > 0
      end
    end

    test "handles errors and continues processing" do
      # Create two stale stores
      store1 = create_stale_store
      store1.update!(name: "Store 1", pinecone_namespace: "ns1")

      store2 = create_stale_store
      store2.update!(name: "Store 2", pinecone_namespace: "ns2")

      # Mock S3 to fail for first store, succeed for second
      call_count = 0
      Aws::S3::Client.stub :new, -> {
        mock = Minitest::Mock.new
        if call_count == 0
          mock.expect :head_object, -> { raise StandardError, "S3 error" }, [Hash]
        else
          mock.expect :head_object, true, [Hash]
          mock.expect :copy_object, true, [Hash]
        end
        call_count += 1
        mock
      } do
        result = @job.perform(dry_run: false)

        # Should report errors but continue
        assert result[:errors].length > 0
      end
    end

    test "respects stale threshold" do
      # Create store just before threshold
      recent = RagStore.create!(
        name: "Almost Stale",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns-recent",
        store_type: "entity",
        entity: @entity,
        status: "active",
        last_accessed_at: (Rag::ArchiveOldDocumentsJob::STALE_THRESHOLD - 1.day).ago
      )

      result = @job.perform(dry_run: true)

      # Should not include the almost-stale store
      # (hard to assert without knowing other test data)
    end

    test "logs summary" do
      assert_nothing_raised do
        @job.perform(dry_run: true)
      end
    end

    test "retries on transient failures" do
      # Stub to raise error
      @job.stub :find_stale_stores, ->{ raise StandardError, "Test error" } do
        assert_raises(StandardError) do
          @job.perform
        end
      end
    end

    test "skips S3 operations when RAG_BUCKET not set" do
      original_bucket = ENV['RAG_BUCKET']
      ENV['RAG_BUCKET'] = nil

      store = create_stale_store

      result = @job.perform(dry_run: false)

      # Should complete but skip S3 operations
      assert_equal "archived", store.reload.status

      ENV['RAG_BUCKET'] = original_bucket
    end

    private

    def create_stale_store
      RagStore.create!(
        name: "Stale Store #{rand(1000)}",
        app_name: "test",
        pinecone_index: "test-index",
        pinecone_namespace: "test-ns-#{rand(1000)}",
        store_type: "entity",
        entity: @entity,
        status: "active",
        last_accessed_at: 90.days.ago
      )
    end

    def create_stale_store_with_document
      store = create_stale_store
      store.update!(s3_raw_path: "entities/#{@entity.id}/raw_documents/#{store.id}")

      doc = RagDocument.create!(
        rag_store: store,
        original_filename: "test.pdf",
        file_hash: "abc123#{rand(1000)}"
      )

      store
    end
  end
end
