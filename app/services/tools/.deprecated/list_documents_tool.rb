module Tools
  class ListDocumentsTool < BaseTool
    def self.metadata
      {
        name: 'list_documents',
        description: 'List all uploaded documents for the current user/entity. Returns document information including titles, asset IDs, sizes, and upload dates. Use this to find a specific document before reading its content.',
        category: 'document',
        input_schema: {
          type: 'object',
          properties: {
            search_query: {
              type: 'string',
              description: 'Optional: Search for documents by name (e.g., "dodge ram", "wheel catalog")'
            }
          }
        }
      }
    end

    def execute(args)
      log_execution(args)

      search_query = get_arg(args, :search_query, '').downcase

      # Get all documents for the entity
      documents = @entity.image_assets.order(created_at: :desc)

      # Filter by search query if provided
      if search_query.present?
        documents = documents.select { |doc| doc.title.downcase.include?(search_query) }
      end

      if documents.empty?
        return error_response("No documents found#{search_query.present? ? " matching '#{search_query}'" : ''}")
      end

      # Format document list
      doc_list = documents.map do |doc|
        {
          asset_id: doc.id,
          title: doc.title,
          size: number_to_human_size(doc.file.blob.byte_size),
          content_type: doc.file.content_type,
          uploaded_at: doc.created_at.strftime('%B %d, %Y at %l:%M %p')
        }
      end

      success_response(
        documents: doc_list,
        total_count: doc_list.length,
        message: "Found #{doc_list.length} document(s)",
        # Canvas routing - opens document store with search pre-filled
        canvas_type: 'document_store',
        canvas_data: search_query.present? ? { search: search_query } : {}
      )
    end

    private

    def number_to_human_size(bytes)
      units = ['B', 'KB', 'MB', 'GB']
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end
  end
end
