class RagStoreService
  require "pinecone"
  require "digest"

  EMBEDDING_DIMENSION = 1536 # OpenAI embedding dimension

  # Multi-tenant index strategy
  SYSTEM_INDEX = "amos-system-knowledge"  # Shared AMOS knowledge
  ENTITY_INDEX = "amos-entity-knowledge"  # Customer-specific data

  def initialize
    @pinecone = Pinecone::Client.new
    @openai_client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end

  def create_rag_store(app_name, chunks, metadata = {})
    Rails.logger.info "🗄️ Creating RAG store for #{app_name} with #{chunks.length} chunks"

    # Determine store type (default: entity)
    store_type = metadata[:store_type] || 'entity'
    entity = metadata[:entity]

    # SECURITY: Entity stores require entity context
    if store_type == 'entity' && entity.nil?
      raise SecurityError, "Cannot create entity RAG store without entity context"
    end

    # Select index based on store type
    index_name = store_type == 'system' ? SYSTEM_INDEX : ENTITY_INDEX

    # Generate namespace with entity isolation
    namespace = generate_namespace(app_name, store_type, entity)

    Rails.logger.info "📍 Store type: #{store_type}, Index: #{index_name}, Namespace: #{namespace}"

    # Ensure index exists
    ensure_index_exists(index_name)

    # Generate embeddings for all chunks
    embedded_chunks = generate_embeddings(chunks)

    # Store in Pinecone
    store_vectors(index_name, namespace, embedded_chunks)

    # Create RAG store record
    rag_store = RagStore.create!(
      name: metadata[:name] || "#{app_name} Documentation",
      app_name: app_name,
      store_type: store_type,
      entity: (store_type == 'entity' ? entity : nil),
      user: metadata[:user],
      pinecone_index: index_name,
      pinecone_namespace: namespace,
      chunk_count: chunks.length,
      metadata: metadata.except(:store_type, :entity, :user).merge(
        created_at: Time.current,
        sources: extract_sources(chunks)
      ),
      status: "active"
    )

    {
      success: true,
      rag_store_id: rag_store.id,
      index_name: index_name,
      namespace: namespace,
      chunks_stored: chunks.length,
      message: "Successfully created RAG store for #{app_name}"
    }
  rescue => e
    Rails.logger.error "RAG store creation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: e.message }
  end

  def query_rag_store(rag_store_id, query, current_entity: nil, top_k: 5)
    rag_store = RagStore.find(rag_store_id)

    # SECURITY CHECK: Verify access
    unless can_access_rag_store?(rag_store, current_entity)
      log_access_denied(rag_store, current_entity, query)
      raise SecurityError, "Access denied to RAG store #{rag_store_id}"
    end

    # Log access
    log_rag_access(rag_store, current_entity, query)

    # Generate embedding for query
    query_embedding = generate_embedding(query)

    # Query Pinecone
    index = @pinecone.index(rag_store.pinecone_index)
    results = index.query(
      vector: query_embedding,
      namespace: rag_store.pinecone_namespace,
      top_k: top_k,
      include_metadata: true
    )

    # Format results
    formatted_results = results["matches"].map do |match|
      {
        content: match["metadata"]["content"],
        score: match["score"],
        source: match["metadata"]["source"],
        type: match["metadata"]["type"]
      }
    end

    {
      success: true,
      results: formatted_results,
      query: query,
      rag_store_id: rag_store_id
    }
  rescue => e
    Rails.logger.error "RAG query failed: #{e.message}"
    { success: false, error: e.message, results: [] }
  end

  def add_to_rag_store(rag_store_id, new_chunks)
    rag_store = RagStore.find(rag_store_id)

    # Generate embeddings for new chunks
    embedded_chunks = generate_embeddings(new_chunks)

    # Store in existing namespace
    store_vectors(rag_store.pinecone_index, rag_store.pinecone_namespace, embedded_chunks)

    # Update chunk count
    rag_store.update!(
      chunk_count: rag_store.chunk_count + new_chunks.length,
      updated_at: Time.current
    )

    {
      success: true,
      chunks_added: new_chunks.length,
      total_chunks: rag_store.chunk_count
    }
  rescue => e
    Rails.logger.error "Failed to add to RAG store: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # Generate namespace with entity isolation
  def generate_namespace(app_name, store_type, entity)
    base_name = app_name.downcase.gsub(/\s+/, '_')
    timestamp = Time.current.to_i

    if store_type == 'system'
      # System RAG: no entity prefix
      "system_#{base_name}_#{timestamp}"
    else
      # Entity RAG: prefix with entity_id for isolation
      "entity_#{entity.id}_#{base_name}_#{timestamp}"
    end
  end

  # Security check: Can current entity access this RAG store?
  def can_access_rag_store?(rag_store, current_entity)
    case rag_store.store_type
    when 'system'
      true  # Everyone can access system knowledge
    when 'entity'
      rag_store.entity_id == current_entity&.id  # Must match entity
    else
      false
    end
  end

  # Log RAG access for security auditing
  def log_rag_access(rag_store, current_entity, query)
    Rails.logger.info({
      event: 'rag_access',
      rag_store_id: rag_store.id,
      store_type: rag_store.store_type,
      store_entity_id: rag_store.entity_id,
      current_entity_id: current_entity&.id,
      query: query.slice(0, 100),  # Log first 100 chars of query
      timestamp: Time.current
    }.to_json)
  end

  # Log denied access attempts
  def log_access_denied(rag_store, current_entity, query)
    Rails.logger.warn({
      event: 'rag_access_denied',
      rag_store_id: rag_store.id,
      store_type: rag_store.store_type,
      store_entity_id: rag_store.entity_id,
      current_entity_id: current_entity&.id,
      query: query.slice(0, 100),
      timestamp: Time.current
    }.to_json)
  end

  def ensure_index_exists(index_name)
    indexes = @pinecone.list_indexes

    unless indexes.include?(index_name)
      Rails.logger.info "Creating new Pinecone index: #{index_name}"

      @pinecone.create_index(
        name: index_name,
        dimension: EMBEDDING_DIMENSION,
        metric: "cosine",
        spec: {
          serverless: {
            cloud: "aws",
            region: ENV["PINECONE_REGION"] || "us-east-1"
          }
        }
      )

      # Wait for index to be ready
      wait_for_index_ready(index_name)
    end
  end

  def wait_for_index_ready(index_name, max_attempts: 60)
    attempts = 0

    loop do
      index_info = @pinecone.describe_index(index_name)

      if index_info["status"]["ready"]
        Rails.logger.info "✅ Index #{index_name} is ready"
        break
      end

      attempts += 1
      if attempts >= max_attempts
        raise "Index #{index_name} failed to become ready after #{max_attempts} attempts"
      end

      Rails.logger.info "⏳ Waiting for index #{index_name} to be ready (attempt #{attempts}/#{max_attempts})"
      sleep(2)
    end
  end

  def generate_embeddings(chunks)
    Rails.logger.info "🧮 Generating embeddings for #{chunks.length} chunks"

    chunks.map.with_index do |chunk, index|
      embedding = generate_embedding(chunk[:content])

      {
        id: generate_vector_id(chunk),
        values: embedding,
        metadata: {
          content: chunk[:content],
          source: chunk[:metadata][:source],
          type: chunk[:metadata][:type] || "unknown",
          chunk_index: index,
          **chunk[:metadata].except(:content) # Include other metadata
        }
      }
    end
  end

  def generate_embedding(text)
    response = @openai_client.embeddings(
      parameters: {
        model: "text-embedding-ada-002",
        input: text.slice(0, 8000) # Limit text length
      }
    )

    response.dig("data", 0, "embedding")
  rescue => e
    Rails.logger.error "Embedding generation failed: #{e.message}"
    raise
  end

  def generate_vector_id(chunk)
    # Generate deterministic ID based on content
    content_hash = Digest::SHA256.hexdigest(chunk[:content])
    source_hash = Digest::SHA256.hexdigest(chunk[:metadata][:source].to_s)

    "#{content_hash[0..7]}-#{source_hash[0..7]}"
  end

  def store_vectors(index_name, namespace, vectors)
    Rails.logger.info "📤 Storing #{vectors.length} vectors in Pinecone"

    index = @pinecone.index(index_name)

    # Upsert in batches of 100
    vectors.each_slice(100) do |batch|
      index.upsert(
        vectors: batch,
        namespace: namespace
      )
    end

    Rails.logger.info "✅ Successfully stored all vectors"
  end

  def extract_sources(chunks)
    chunks.map { |c| c[:metadata][:source] }.uniq
  end
end

# Create the RagStore model if it doesn't exist
unless defined?(RagStore)
  class RagStore < ApplicationRecord
    validates :name, presence: true
    validates :app_name, presence: true
    validates :pinecone_index, presence: true
    validates :pinecone_namespace, presence: true

    enum :status, { active: "active", archived: "archived" }
  end
end
