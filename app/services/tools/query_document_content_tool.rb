module Tools
  class QueryDocumentContentTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'query_document_content',
        description: 'Search for information across all your documents (session and permanent storage). Automatically checks recent uploads first (fast), then searches permanent knowledge base (comprehensive).',
        category: 'document',
        input_schema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'What to search for in the documents (e.g., "tires", "service ticket", "pricing")'
            },
            top_k: {
              type: 'integer',
              description: 'Maximum number of results to return (default: 5)',
              default: 5
            }
          },
          required: ['query']
        }
      }
    end

    def execute(args)
      log_execution(args)

      query = get_arg(args, :query)
      top_k = get_arg(args, :top_k, 5)

      return error_response("Query is required") if query.blank?

      Rails.logger.info "🔍 Unified document query: '#{query}' (top_k: #{top_k})"

      # STEP 1: Check Redis session storage FIRST (fast, free)
      session_results = search_session_documents(query, top_k)

      if session_results[:found]
        Rails.logger.info "✅ Found results in session storage (#{session_results[:chunks].length} chunks)"
        return success_response(
          query: query,
          source: 'session',
          results: session_results[:chunks],
          count: session_results[:chunks].length,
          message: "Found #{session_results[:chunks].length} results in recent uploads",
          cost: 0.0  # Free!
        )
      end

      # STEP 2: Fall back to RAG database (slower, costs embeddings)
      Rails.logger.info "🔄 No session results, falling back to RAG database"
      rag_results = search_rag_database(query, top_k)

      if rag_results[:chunks].any?
        Rails.logger.info "✅ Found results in RAG database (#{rag_results[:chunks].length} chunks)"
        return success_response(
          query: query,
          source: 'rag',
          results: rag_results[:chunks],
          count: rag_results[:chunks].length,
          response_time_ms: rag_results[:response_time_ms],
          message: "Found #{rag_results[:chunks].length} results in permanent knowledge base",
          cost: 0.0001  # AWS Bedrock embedding cost
        )
      end

      # No results found anywhere
      Rails.logger.info "⚠️ No results found in session or RAG storage"
      success_response(
        query: query,
        source: 'none',
        results: [],
        count: 0,
        message: "No documents contain information about '#{query}'"
      )
    rescue => e
      Rails.logger.error "Query document content error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      error_response("Search failed: #{e.message}")
    end

    private

    # Search Redis session storage
    def search_session_documents(query, top_k)
      session_id = @context[:session_id]
      return { found: false, chunks: [] } unless session_id

      session_key = "rag:session:#{session_id}:documents"
      redis_docs = $redis.hgetall(session_key)

      return { found: false, chunks: [] } if redis_docs.empty?

      Rails.logger.info "📦 Searching #{redis_docs.keys.length} session document(s)"

      # Simple keyword search through session document chunks
      matching_chunks = []
      query_words = query.downcase.split

      redis_docs.each do |filename, doc_json|
        doc_data = JSON.parse(doc_json)
        chunks = doc_data['chunks'] || []

        chunks.each_with_index do |chunk, index|
          content = chunk['content'].to_s.downcase

          # Score based on keyword matches
          score = query_words.count { |word| content.include?(word) }

          if score > 0
            matching_chunks << {
              content: chunk['content'],
              score: score,
              filename: doc_data['filename'],
              chunk_index: index,
              storage_type: 'session',
              metadata: {
                filename: doc_data['filename'],
                asset_id: doc_data['asset_id']
              }
            }
          end
        end
      end

      # Sort by score and limit
      matching_chunks.sort_by! { |c| -c[:score] }
      matching_chunks = matching_chunks.first(top_k)

      {
        found: matching_chunks.any?,
        chunks: matching_chunks
      }
    end

    # Search RAG database with vector similarity
    def search_rag_database(query, top_k)
      service = HybridRagQueryService.new(@entity)
      result = service.query(query, top_k: top_k)

      {
        chunks: result[:chunks] || [],
        response_time_ms: result[:response_time_ms]
      }
    rescue => e
      Rails.logger.error "RAG query error: #{e.message}"
      { chunks: [], response_time_ms: 0 }
    end
  end
end
