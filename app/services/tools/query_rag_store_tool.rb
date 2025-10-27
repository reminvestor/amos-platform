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
        # Find RAG store with security check
        rag_store = if rag_store_id
          # Security check: Verify entity can access this specific store
          begin
            RagStore.find_accessible(rag_store_id, entity)
          rescue ActiveRecord::RecordNotFound
            return error_response("RAG store not found or access denied")
          end
        elsif app_name
          # Find latest accessible store for this app
          find_accessible_rag_store(app_name)
        else
          # If neither provided, query ALL entity RAG stores
          return query_all_entity_stores(query, top_k)
        end

        if !rag_store
          return error_response("No accessible RAG store found for app: #{app_name}")
        end

        # Query the RAG store with entity context
        rag_service = RagStoreService.new
        result = rag_service.query_rag_store(
          rag_store.id,
          query,
          current_entity: entity,
          top_k: top_k
        )

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
      rescue SecurityError => e
        Rails.logger.error "RAG access denied: #{e.message}"
        error_response("Access denied: #{e.message}")
      rescue => e
        Rails.logger.error "RAG query failed: #{e.message}"
        error_response("Query failed: #{e.message}")
      end
    end

    private

    # Find accessible RAG store for app (checks both system and entity stores)
    def find_accessible_rag_store(app_name)
      RagStore.accessible_by(entity)
              .where(app_name: app_name, status: "active")
              .order(created_at: :desc)
              .first
    end

    # Query all entity RAG stores using HybridRagQueryService
    def query_all_entity_stores(query, top_k)
      begin
        service = HybridRagQueryService.new(entity)
        result = service.query(query, top_k: top_k)

        if result[:chunks].any?
          success_response(
            query: query,
            results: result[:chunks],
            count: result[:chunks].length,
            response_time_ms: result[:response_time_ms],
            sources: result[:chunks].map { |c| c[:filename] }.uniq,
            message: "Found #{result[:chunks].length} relevant results across all your documents"
          )
        else
          success_response(
            query: query,
            results: [],
            count: 0,
            message: "No relevant documents found for this query"
          )
        end
      rescue => e
        Rails.logger.error "HybridRagQueryService error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Query failed: #{e.message}")
      end
    end
  end
end
