module Tools
  class CreateRagStoreTool < BaseTool
    def self.metadata
      {
        name: "create_rag_store",
        description: "Create a RAG (Retrieval Augmented Generation) knowledge base from API documentation. Creates entity-scoped knowledge bases by default for customer data isolation.",
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            app_name: {
              type: "string",
              description: "Name of the application/API"
            },
            documentation: {
              type: "array",
              description: "Array of documentation URLs or text content"
            },
            search_results: {
              type: "array",
              description: "Array of search results to process"
            },
            user_uploads: {
              type: "array",
              description: "Array of uploaded file references"
            },
            store_type: {
              type: "string",
              description: "Type of RAG store: 'entity' (default, customer-specific) or 'system' (shared AMOS knowledge)",
              enum: ["entity", "system"]
            },
            name: {
              type: "string",
              description: "Optional custom name for the RAG store"
            }
          },
          required: [ "app_name" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      app_name = get_arg(args, :app_name)
      documentation = get_arg(args, :documentation, [])
      search_results = get_arg(args, :search_results, [])
      user_uploads = get_arg(args, :user_uploads, [])

      # Validate required args
      if error = validate_required_args(args, [ :app_name ])
        return error
      end

      begin
        # Process all documentation sources
        documents_to_process = []

        # Add search results as URLs
        # search_results can be either:
        # 1. Array of web_search tool responses (each with :results array inside)
        # 2. Array of individual result hashes (with :url and :title)
        search_results.each do |result|
          # Skip if result is a string (unresolved template variable)
          next if result.is_a?(String)

          # Check if this is a web_search tool response (has :results key)
          if result.is_a?(Hash) && (result[:results] || result["results"])
            # Extract individual results from web_search response
            results_array = result[:results] || result["results"]
            results_array.each do |search_result|
              url = search_result[:url] || search_result["url"]
              next unless url

              documents_to_process << {
                type: "url",
                content: url,
                metadata: {
                  title: search_result[:title] || search_result["title"],
                  snippet: search_result[:snippet] || search_result["snippet"]
                }
              }
            end
          elsif result.is_a?(Hash) && (result[:url] || result["url"])
            # This is an individual result hash
            documents_to_process << {
              type: "url",
              content: result[:url] || result["url"],
              metadata: { title: result[:title] || result["title"] }
            }
          end
        end

        # Add user-provided documentation
        documentation.each do |doc|
          if doc.start_with?("http")
            documents_to_process << { type: "url", content: doc }
          else
            documents_to_process << { type: "text", content: doc }
          end
        end

        # Add uploaded files
        user_uploads.each do |upload|
          # Skip if upload is a string (unresolved template variable)
          next if upload.is_a?(String)
          next unless upload.is_a?(Hash)

          path = upload[:path] || upload["path"]
          next unless path

          documents_to_process << {
            type: "file",
            content: path,
            filename: upload[:filename] || upload["filename"]
          }
        end

        # Check if we have any documents to process
        if documents_to_process.empty?
          return error_response("No valid documentation sources found. Please provide URLs, search results, or uploaded files.")
        end

        Rails.logger.info "📚 Processing #{documents_to_process.length} documents for RAG store"

        # Process documents to extract chunks
        processor = DocumentProcessorService.new
        processing_result = processor.process_documents(documents_to_process)

        if !processing_result[:success]
          return error_response("Document processing failed: #{processing_result[:error]}")
        end

        # Determine store type (default: entity for customer data)
        store_type = get_arg(args, :store_type, 'entity')

        # SECURITY: Entity stores require entity context
        if store_type == 'entity' && entity.nil?
          return error_response("Cannot create entity RAG store without entity context")
        end

        # Create RAG store with Pinecone
        rag_service = RagStoreService.new
        rag_result = rag_service.create_rag_store(
          app_name,
          processing_result[:chunks],
          {
            store_type: store_type,
            entity: entity,
            user: user,
            name: get_arg(args, :name),  # Optional custom name
            total_sources: documents_to_process.length,
            processing_metadata: processing_result[:metadata]
          }
        )

        if rag_result[:success]
          success_response(
            rag_store_id: rag_result[:rag_store_id],
            app_name: app_name,
            documents_indexed: documents_to_process.length,
            chunks_created: rag_result[:chunks_stored],
            status: "ready",
            message: "Successfully created knowledge base for #{app_name}"
          )
        else
          error_response(rag_result[:error])
        end
      rescue => e
        Rails.logger.error "RAG store creation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("RAG store creation failed: #{e.message}")
      end
    end
  end
end
