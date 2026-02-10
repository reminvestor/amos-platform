module Tools
  class QueryDocumentContentTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: 'query_document_content',
        description: 'REQUIRED when user asks about uploaded documents. Trigger phrases: "tell me about X", "what\'s in my X", "find X", "search my documents". Searches ALL documents (recent uploads + permanent storage) automatically. Use this instead of answering from memory when user asks about document content.',
        category: 'document',
        input_schema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'What to search for in the documents (e.g., "tires", "service ticket", "server error")'
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
        # Filter out low-relevance results — similarity < 0.35 means the content is likely unrelated
        min_relevance = 0.35
        relevant_chunks = rag_results[:chunks].select do |chunk|
          score = chunk[:similarity_score] || chunk[:combined_score] || 0
          score >= min_relevance
        end

        if relevant_chunks.any?
          Rails.logger.info "✅ Found #{relevant_chunks.length} relevant results in RAG database (filtered from #{rag_results[:chunks].length})"

          # Group by document and extract unique documents with their IDs
          documents_found = relevant_chunks.map do |chunk|
            {
              document_id: chunk[:rag_document_id],
              title: chunk[:document_title],
              filename: chunk.dig(:metadata, :filename)
            }
          end.uniq { |d| d[:document_id] }

          return success_response(
            query: query,
            source: 'rag',
            results: relevant_chunks,
            count: relevant_chunks.length,
            documents: documents_found,
            response_time_ms: rag_results[:response_time_ms],
            message: "Found #{relevant_chunks.length} results from #{documents_found.length} document(s).",
            cost: 0.0001,  # AWS Bedrock embedding cost
            # Canvas routing - opens document store with search pre-filled
            canvas_type: 'document_store',
            canvas_data: { search: query }
          )
        else
          Rails.logger.info "⚠️ RAG returned #{rag_results[:chunks].length} results but all below relevance threshold (#{min_relevance})"
          # Fall through to uploaded documents search, then "no results"
        end
      end

      # STEP 3: Fall back to searching uploaded documents directly
      # (Finds recently uploaded files that haven't been indexed to RAG yet)
      Rails.logger.info "🔄 No RAG results, searching uploaded documents"
      uploaded_docs = search_uploaded_documents(query, top_k)

      if uploaded_docs[:documents].any?
        Rails.logger.info "✅ Found #{uploaded_docs[:documents].length} uploaded document(s) matching query"
        return success_response(
          query: query,
          source: 'uploaded',
          results: uploaded_docs[:documents],
          count: uploaded_docs[:documents].length,
          message: "Found #{uploaded_docs[:documents].length} uploaded document(s). Use read_document tool with asset_id to read content.",
          cost: 0.0  # Free - searching local database
        )
      end

      # No results found anywhere
      Rails.logger.info "⚠️ No results found in session, RAG storage, or uploaded documents"
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

    # Search uploaded documents directly (fallback for recently uploaded files)
    def search_uploaded_documents(query, top_k)
      query_lower = query.downcase

      # Search documents by title matching
      documents = @entity.image_assets
        .where("LOWER(title) LIKE ?", "%#{query_lower}%")
        .order(created_at: :desc)
        .limit(top_k)

      matching_docs = documents.map do |doc|
        {
          title: doc.title,
          asset_id: doc.id,
          content_type: doc.file.content_type,
          size: doc.file.blob.byte_size,
          uploaded_at: doc.created_at,
          storage_type: 'uploaded',
          relevance: calculate_relevance(doc.title, query)
        }
      end

      # Sort by relevance score
      matching_docs.sort_by! { |d| -d[:relevance] }

      {
        documents: matching_docs
      }
    rescue => e
      Rails.logger.error "Uploaded documents search error: #{e.message}"
      { documents: [] }
    end

    # Calculate relevance score for document title matching
    def calculate_relevance(title, query)
      query_words = query.downcase.split
      title_lower = title.downcase

      # Exact match gets highest score
      return 100 if title_lower == query.downcase

      # Matches are scored by number of query words found
      score = query_words.count { |word| title_lower.include?(word) }
      score * 10
    end
  end
end
