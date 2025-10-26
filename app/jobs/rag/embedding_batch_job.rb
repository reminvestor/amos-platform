# Generates embeddings for chunks and stores in both Pinecone and PostgreSQL (pgvector)
#
# This job implements the dual-write strategy:
# 1. Generate embeddings via AWS Bedrock (Titan Embed)
# 2. Store embeddings in PostgreSQL (pgvector) for local search
# 3. Store embeddings in Pinecone for production-scale vector search
#
# Queue: embeddings (rate-limited for API calls)
# Retry: 5 attempts with exponential backoff

module Rag
  class EmbeddingBatchJob < ApplicationJob
    queue_as :embeddings

    # Retry on transient errors
    retry_on StandardError, wait: :exponentially_longer, attempts: 5
    retry_on Aws::BedrockRuntime::Errors::ThrottlingException, wait: 30.seconds, attempts: 10

    # Discard on permanent errors
    discard_on ActiveRecord::RecordNotFound
    discard_on ArgumentError

    # Process chunks in batches to avoid overwhelming APIs
    BATCH_SIZE = 10
    MAX_RETRIES = 5

    def perform(chunk_ids)
      Rails.logger.info "🔢 EmbeddingBatchJob: Processing #{chunk_ids.length} chunks"

      chunks = RagChunk.includes(rag_document: :rag_store).find(chunk_ids)

      return if chunks.empty?

      rag_store = chunks.first.rag_store

      # Track processing job
      processing_job = create_processing_job(rag_store, chunk_ids)

      begin
        # Generate embeddings via Bedrock
        embeddings = generate_embeddings(chunks)

        # Update chunks with embeddings (pgvector)
        update_chunks_with_embeddings(chunks, embeddings)

        # Store in Pinecone (if configured)
        store_in_pinecone(chunks, rag_store) if pinecone_configured?

        # Mark processing job as completed
        processing_job.update!(
          status: :completed,
          completed_at: Time.current
        )

        # Check if all chunks for this RAG store are now embedded
        check_rag_store_completion(rag_store)

        Rails.logger.info "✅ EmbeddingBatchJob: Successfully processed #{chunks.length} chunks"

      rescue => e
        Rails.logger.error "❌ EmbeddingBatchJob failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        processing_job.update!(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )

        raise # Re-raise to trigger retry logic
      end
    end

    private

    def create_processing_job(rag_store, chunk_ids)
      rag_store.rag_processing_jobs.create!(
        job_id: job_id,
        job_type: 'embedding_batch',
        status: :processing,
        started_at: Time.current,
        metadata: {
          chunk_ids: chunk_ids,
          chunk_count: chunk_ids.length
        }
      )
    end

    def generate_embeddings(chunks)
      bedrock = bedrock_client

      Rails.logger.info "🧠 Generating embeddings for #{chunks.length} chunks via Bedrock"

      chunks.map.with_index do |chunk, index|
        Rails.logger.debug "  Processing chunk #{index + 1}/#{chunks.length}"

        response = bedrock.invoke_model(
          model_id: embedding_model,
          content_type: 'application/json',
          body: {
            inputText: truncate_text_for_embedding(chunk.content)
          }.to_json
        )

        parsed = JSON.parse(response.body.read)
        embedding_vector = parsed['embedding']

        unless embedding_vector.is_a?(Array) && embedding_vector.length == 1536
          raise "Invalid embedding response: expected 1536-dimension array, got #{embedding_vector.class}"
        end

        embedding_vector
      end
    end

    def update_chunks_with_embeddings(chunks, embeddings)
      Rails.logger.info "💾 Storing #{chunks.length} embeddings in PostgreSQL (pgvector)"

      chunks.zip(embeddings).each do |chunk, embedding|
        chunk.update!(embedding: embedding)
      end
    end

    def store_in_pinecone(chunks, rag_store)
      return unless rag_store.pinecone_index.present? && rag_store.pinecone_namespace.present?

      Rails.logger.info "☁️ Storing #{chunks.length} vectors in Pinecone"

      index = pinecone_index(rag_store.pinecone_index)

      vectors = chunks.map do |chunk|
        {
          id: "chunk_#{chunk.id}",
          values: chunk.embedding,
          metadata: {
            rag_store_id: chunk.rag_store.id.to_s,
            rag_document_id: chunk.rag_document.id.to_s,
            entity_id: chunk.rag_store.entity_id&.to_s,
            chunk_type: chunk.chunk_type,
            chunk_index: chunk.chunk_index,
            # Truncate content for metadata storage (Pinecone limit: 40KB per vector)
            content_preview: chunk.content[0..1000],
            page: chunk.metadata&.dig('page'),
            section_title: chunk.metadata&.dig('section_title')
          }
        }
      end

      # Upsert vectors to Pinecone
      index.upsert(
        vectors: vectors,
        namespace: rag_store.pinecone_namespace
      )

      # Update chunks with Pinecone vector IDs
      chunks.each_with_index do |chunk, i|
        chunk.update_column(:pinecone_vector_id, vectors[i][:id])
      end

      Rails.logger.info "✅ Stored #{vectors.length} vectors in Pinecone"
    end

    def check_rag_store_completion(rag_store)
      return unless rag_store.all_chunks_embedded?

      Rails.logger.info "🎉 All chunks embedded for RagStore ##{rag_store.id}"

      # Update RAG store status to ready
      if rag_store.respond_to?(:complete_processing!)
        rag_store.complete_processing!
      else
        rag_store.update!(status: :ready)
      end

      # TODO: Notify user via broadcast/email
      # NotifyUserJob.perform_later(rag_store.id, 'ready')
    end

    # Helper methods

    def bedrock_client
      @bedrock_client ||= Aws::BedrockRuntime::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
    end

    def embedding_model
      # Using Amazon Titan Embed Text v1 (1536 dimensions)
      'amazon.titan-embed-text-v1'
    end

    def truncate_text_for_embedding(text)
      # Titan Embed supports up to 8K tokens (~32K characters)
      # Truncate to be safe
      text[0..25_000]
    end

    def pinecone_configured?
      ENV['PINECONE_API_KEY'].present? && ENV['PINECONE_ENVIRONMENT'].present?
    end

    def pinecone_index(index_name)
      require 'pinecone'

      Pinecone::Index.new(index_name)
    end
  end
end
