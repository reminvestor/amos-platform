# frozen_string_literal: true

module V3
  module Tools
    # ReadFileTool - Read documents, knowledge base, and uploaded files
    #
    # Consolidates: read_document, query_document_content, list_documents
    #
    class ReadFileTool < ::Tools::BaseTool
      def self.read_only?
        true
      end

      def self.metadata
        {
          name: "read_file",
          description: <<~DESC.strip,
            Read uploaded documents and knowledge base content.
            
            Actions:
            - "list": List all documents/files
            - "read": Read a specific document by ID
            - "search": Search document content with a query
            
            Examples:
            - read_file(action: "list")
            - read_file(action: "read", document_id: 42)
            - read_file(action: "search", query: "pricing policy")
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: "What to do: 'list', 'read', or 'search'",
                enum: %w[list read search]
              },
              document_id: {
                type: "integer",
                description: "For action='read': document ID"
              },
              query: {
                type: "string",
                description: "For action='search': search query"
              },
              limit: {
                type: "integer",
                description: "Max results (default: 10)"
              }
            },
            required: ["action"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        action = get_arg(args, :action)

        case action
        when "list"
          list_documents(args)
        when "read"
          read_document(args)
        when "search"
          search_documents(args)
        else
          error_response("Unknown action: #{action}")
        end
      rescue => e
        Rails.logger.error "[V3::ReadFile] Error: #{e.message}"
        error_response("File operation failed: #{e.message}")
      end

      private

      def list_documents(args)
        limit = [get_arg(args, :limit, 20).to_i, 50].min
        
        docs = RagDocument.joins(:rag_store)
                          .where(rag_stores: { entity_id: entity.id })
                          .order(created_at: :desc)
                          .limit(limit)
                          .map do |doc|
          {
            id: doc.id,
            filename: doc.original_filename,
            title: doc.title || doc.original_filename,
            content_type: doc.content_type,
            size: doc.file_size_bytes,
            status: doc.processing_status,
            created_at: doc.created_at
          }
        end

        total = RagDocument.joins(:rag_store).where(rag_stores: { entity_id: entity.id }).count

        success_response(
          documents: docs,
          count: docs.length,
          total: total,
          message: "Use read_file(action: 'read', document_id: ID) to read a document's content."
        )
      end

      def read_document(args)
        doc_id = get_arg(args, :document_id)
        return error_response("Missing: document_id") if doc_id.blank?

        # Delegate to existing ReadDocumentTool with correct params
        tool = ::Tools::ReadDocumentTool.new(user: user, entity: entity, context: context)
        tool.execute({ "asset_id" => doc_id.to_i, "asset_type" => "document" })
      end

      def search_documents(args)
        query = get_arg(args, :query)
        return error_response("Missing: query") if query.blank?

        # Delegate to existing QueryDocumentContentTool
        tool = ::Tools::QueryDocumentContentTool.new(user: user, entity: entity, context: context)
        tool.execute({ "query" => query })
      end
    end
  end
end
