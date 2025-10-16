module Tools
  class QueryRagStoreTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "query_rag_store",
        description: "Query a RAG knowledge base to retrieve relevant documentation and information",
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The question or search query to find relevant documentation"
            },
            app_name: {
              type: "string",
              description: "Name of the application to query documentation for"
            },
            rag_store_id: {
              type: "integer",
              description: "ID of the RAG store (optional if app_name provided)"
            },
            top_k: {
              type: "integer",
              description: "Number of results to return (default: 5)"
            }
          },
          required: [ "query" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      query = get_arg(args, :query)
      app_name = get_arg(args, :app_name)
      rag_store_id = get_arg(args, :rag_store_id)
      top_k = get_arg(args, :top_k, 5)

      # Validate required args
      if error = validate_required_args(args, [ :query ])
        return error
      end

      begin
        # Find RAG store
        rag_store = find_rag_store(rag_store_id, app_name)

        if !rag_store
          return error_response("No RAG store found for app: #{app_name || rag_store_id}")
        end

        # Query the RAG store
        rag_service = RagStoreService.new
        result = rag_service.query_rag_store(rag_store.id, query, top_k: top_k)

        if result[:success]
          success_response(
            query: query,
            results: result[:results],
            count: result[:results].length,
            rag_store_id: rag_store.id,
            app_name: rag_store.app_name
          )
        else
          error_response("Query failed: #{result[:error]}")
        end
      rescue => e
        Rails.logger.error "RAG query failed: #{e.message}"
        error_response("Query failed: #{e.message}")
      end
    end

    private

    def find_rag_store(rag_store_id, app_name)
      if rag_store_id
        RagStore.find_by(id: rag_store_id)
      elsif app_name
        # Find most recent RAG store for this app
        RagStore.where(app_name: app_name)
                .where(status: "active")
                .order(created_at: :desc)
                .first
      else
        nil
      end
    end
  end
end
