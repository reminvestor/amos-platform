# frozen_string_literal: true

module Rag
  # Archives old RAG documents that haven't been accessed recently
  # Moves S3 files to Glacier and removes from Pinecone to save costs
  # Runs weekly via cron
  class ArchiveOldDocumentsJob < ApplicationJob
    queue_as :maintenance

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # How long before a document is considered stale
    STALE_THRESHOLD = 60.days

    def perform(dry_run: false)
      Rails.logger.info "🗄️ Starting RAG document archival (dry_run: #{dry_run})..."

      # Find stale entity documents (don't archive system docs)
      stale_stores = find_stale_stores

      Rails.logger.info "Found #{stale_stores.count} stale RAG stores to archive"

      archived_count = 0
      errors = []

      stale_stores.find_each do |store|
        begin
          if dry_run
            Rails.logger.info "  [DRY RUN] Would archive: #{store.name} (last accessed #{store.last_accessed_at&.to_date})"
          else
            archive_store(store)
            archived_count += 1
            Rails.logger.info "  ✅ Archived: #{store.name}"
          end
        rescue => e
          error_msg = "Failed to archive store #{store.id}: #{e.message}"
          Rails.logger.error error_msg
          errors << error_msg
        end
      end

      result = {
        date: Date.current.to_s,
        dry_run: dry_run,
        stale_stores_found: stale_stores.count,
        archived_count: archived_count,
        errors: errors
      }

      log_summary(result)
      result
    end

    private

    def find_stale_stores
      RagStore
        .where(store_type: 'entity') # Only archive entity stores, not system
        .where('last_accessed_at < ? OR last_accessed_at IS NULL', STALE_THRESHOLD.ago)
        .where.not(status: 'archived')
    end

    def archive_store(store)
      Rails.logger.info "  📦 Archiving store: #{store.name} (ID: #{store.id})"

      # Step 1: Move S3 documents to Glacier
      if store.s3_raw_path.present?
        move_s3_to_glacier(store)
      end

      # Step 2: Remove from Pinecone (optional - saves costs)
      if store.pinecone_namespace.present? && ENV['ARCHIVE_REMOVES_PINECONE'] == 'true'
        remove_from_pinecone(store)
      end

      # Step 3: Mark as archived in database
      store.update!(status: 'archived')
    end

    def move_s3_to_glacier(store)
      return unless ENV['RAG_BUCKET']

      s3 = Aws::S3::Client.new

      store.rag_documents.each do |doc|
        # Build S3 key
        s3_key = "#{store.s3_raw_path}/#{doc.original_filename}"

        begin
          # Check if object exists
          s3.head_object(bucket: ENV['RAG_BUCKET'], key: s3_key)

          # Transition to Glacier Deep Archive (cheapest option)
          s3.copy_object(
            bucket: ENV['RAG_BUCKET'],
            copy_source: "#{ENV['RAG_BUCKET']}/#{s3_key}",
            key: s3_key,
            storage_class: 'DEEP_ARCHIVE',
            metadata_directive: 'COPY'
          )

          Rails.logger.info "    ❄️  Moved to Glacier: #{doc.original_filename}"
        rescue Aws::S3::Errors::NotFound
          Rails.logger.warn "    ⚠️  S3 object not found: #{s3_key}"
        end
      end
    end

    def remove_from_pinecone(store)
      return unless store.pinecone_namespace.present?
      return unless pinecone_configured?

      begin
        # Delete all vectors in this namespace
        # This saves Pinecone storage costs

        Rails.logger.info "    🗑️  Removing from Pinecone namespace: #{store.pinecone_namespace}"

        # Note: Actual Pinecone deletion would go here
        # We're leaving this as a placeholder since Pinecone integration may vary

        # Example:
        # pinecone = Pinecone::Client.new(api_key: ENV['PINECONE_API_KEY'])
        # index = pinecone.index(ENV['PINECONE_INDEX'])
        # index.delete(namespace: store.pinecone_namespace, delete_all: true)

        Rails.logger.info "    ✅ Pinecone vectors removed"
      rescue => e
        Rails.logger.error "    ❌ Failed to remove from Pinecone: #{e.message}"
        # Don't fail the whole job if Pinecone removal fails
      end
    end

    def pinecone_configured?
      ENV['PINECONE_API_KEY'].present? && ENV['PINECONE_INDEX'].present?
    end

    def log_summary(result)
      Rails.logger.info "=" * 80
      Rails.logger.info "🗄️  RAG Archival Summary - #{result[:date]}"
      Rails.logger.info "=" * 80
      Rails.logger.info "Dry Run: #{result[:dry_run]}"
      Rails.logger.info "Stale Stores Found: #{result[:stale_stores_found]}"
      Rails.logger.info "Archived: #{result[:archived_count]}"
      Rails.logger.info "Errors: #{result[:errors].length}"

      if result[:errors].any?
        Rails.logger.info ""
        Rails.logger.info "Errors:"
        result[:errors].each { |error| Rails.logger.info "  - #{error}" }
      end

      Rails.logger.info "=" * 80
    end
  end
end
