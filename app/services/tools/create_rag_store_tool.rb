module Tools
  class CreateRagStoreTool < BaseTool
    def self.metadata
      {
        name: 'create_rag_store',
        description: 'Create a RAG (Retrieval Augmented Generation) knowledge base from API documentation',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            app_name: {
              type: 'string',
              description: 'Name of the application/API'
            },
            documentation: {
              type: 'array',
              description: 'Array of documentation URLs or text content'
            },
            search_results: {
              type: 'array',
              description: 'Array of search results to process'
            },
            user_uploads: {
              type: 'array',
              description: 'Array of uploaded file references'
            }
          },
          required: ['app_name']
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
      if error = validate_required_args(args, [:app_name])
        return error
      end
      
      begin
        # Process all documentation sources
        documents_to_process = []
        
        # Add search results as URLs
        search_results.each do |result|
          documents_to_process << {
            type: 'url',
            content: result[:url] || result['url'],
            metadata: { title: result[:title] || result['title'] }
          }
        end
        
        # Add user-provided documentation
        documentation.each do |doc|
          if doc.start_with?('http')
            documents_to_process << { type: 'url', content: doc }
          else
            documents_to_process << { type: 'text', content: doc }
          end
        end
        
        # Add uploaded files
        user_uploads.each do |upload|
          documents_to_process << {
            type: 'file',
            content: upload[:path] || upload['path'],
            filename: upload[:filename] || upload['filename']
          }
        end
        
        # Process documents to extract chunks
        processor = DocumentProcessorService.new
        processing_result = processor.process_documents(documents_to_process)
        
        if !processing_result[:success]
          return error_response("Document processing failed: #{processing_result[:error]}")
        end
        
        # Create RAG store with Pinecone
        rag_service = RagStoreService.new
        rag_result = rag_service.create_rag_store(
          app_name,
          processing_result[:chunks],
          {
            user: user,
            entity: entity,
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
            status: 'ready',
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
