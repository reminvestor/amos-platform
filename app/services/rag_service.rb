class RagService
  def initialize(entity)
    @entity = entity
    @embedding_service = EmbeddingService.new
  end
  
  # Search across all knowledge sources
  def search(query, options = {})
    limit = options[:limit] || 10
    sources = options[:sources] || [:documents, :conversations, :integrations]
    
    # Generate query embedding
    query_embedding = @embedding_service.generate(query)
    return [] if query_embedding.nil?
    
    results = []
    
    # Search knowledge documents
    if sources.include?(:documents)
      doc_results = search_documents(query_embedding, limit: limit / 2)
      results.concat(doc_results)
    end
    
    # Search conversation history
    if sources.include?(:conversations)
      conv_results = search_conversations(query_embedding, limit: limit / 3)
      results.concat(conv_results)
    end
    
    # Search integration data
    if sources.include?(:integrations)
      int_results = search_integrations(query_embedding, limit: limit / 3)
      results.concat(int_results)
    end
    
    # Sort by relevance and return top results
    results.sort_by { |r| -r[:score] }.first(limit)
  end
  
  # Add document to knowledge base
  def add_document(title:, content:, source_type: 'upload', source_url: nil, metadata: {})
    ActiveRecord::Base.transaction do
      doc = @entity.knowledge_documents.create!(
        title: title,
        content: content,
        source_type: source_type,
        source_url: source_url,
        metadata: metadata
      )
      
      # Generate embedding for the whole document
      doc.embedding = @embedding_service.generate(content)
      doc.save!
      
      # Create chunks for large documents
      if content.length > 1000
        chunks = doc.create_chunks!
        chunks.each do |chunk|
          chunk.embedding = @embedding_service.generate(chunk.content)
          chunk.save!
        end
      end
      
      doc
    end
  end
  
  # Store conversation for future context
  def store_conversation(message)
    return unless message.content.present?
    
    embedding = @embedding_service.generate(message.content)
    return if embedding.nil?
    
    ConversationEmbedding.from_scout_message(message, embedding)
  end
  
  # Build context for LLM from search results
  def build_context(results, max_tokens: 4000)
    context_parts = []
    token_count = 0
    
    results.each do |result|
      # Rough token estimation (1 token ≈ 4 chars)
      estimated_tokens = result[:content].length / 4
      break if token_count + estimated_tokens > max_tokens
      
      context_part = case result[:source]
      when :document
        "From knowledge base (#{result[:metadata][:title]}):\n#{result[:content]}"
      when :conversation
        "From previous conversation:\n#{result[:content]}"
      when :integration
        "From #{result[:metadata][:integration]} (#{result[:metadata][:resource_type]}):\n#{result[:content]}"
      end
      
      context_parts << context_part
      token_count += estimated_tokens
    end
    
    context_parts.join("\n\n---\n\n")
  end
  
  private
  
  def search_documents(query_embedding, limit:)
    # Search in document chunks for better granularity
    chunks = DocumentChunk.semantic_search(
      query_embedding,
      entity_id: @entity.id,
      limit: limit
    )
    
    chunks.map do |chunk|
      {
        source: :document,
        content: chunk.context,
        score: calculate_score(chunk),
        metadata: {
          title: chunk.knowledge_document.title,
          chunk_index: chunk.chunk_index,
          document_id: chunk.knowledge_document_id
        }
      }
    end
  end
  
  def search_conversations(query_embedding, limit:)
    embeddings = ConversationEmbedding.find_relevant_context(
      query_embedding,
      entity_id: @entity.id,
      limit: limit
    )
    
    embeddings.map do |embedding|
      {
        source: :conversation,
        content: embedding.content,
        score: calculate_score(embedding),
        metadata: {
          role: embedding.role,
          created_at: embedding.created_at,
          message_id: embedding.scout_message_id
        }
      }
    end
  end
  
  def search_integrations(query_embedding, limit:)
    results = IntegrationEmbedding.search_integrations(
      query_embedding,
      entity_id: @entity.id,
      limit: limit
    )
    
    results.map do |result|
      {
        source: :integration,
        content: result.content,
        score: calculate_score(result),
        metadata: {
          integration: result.integration.name,
          resource_type: result.resource_type,
          resource_id: result.resource_id
        }
      }
    end
  end
  
  def calculate_score(record)
    # This would be calculated by the vector database
    # For now, return a placeholder
    0.85
  end
end
