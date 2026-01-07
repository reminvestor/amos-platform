# frozen_string_literal: true

module Tools
  class SaveImageToDocumentsTool < BaseTool
    def self.metadata
      {
        name: "save_image_to_documents",
        description: "Save an image from the image library to the entity's document store (RAG) so it can be retrieved and referenced in future conversations. Use this when the user asks to save an image to their documents or knowledge base.",
        category: "documents",
        input_schema: {
          type: "object",
          properties: {
            image_id: {
              type: "integer",
              description: "The ID of the image asset to save to documents"
            },
            title: {
              type: "string",
              description: "Optional custom title for the document. If not provided, uses the image title."
            },
            tags: {
              type: "array",
              items: { type: "string" },
              description: "Optional tags to help categorize the document"
            }
          },
          required: ["image_id"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      image_id = get_arg(args, :image_id)
      custom_title = get_arg(args, :title)
      tags = get_arg(args, :tags, [])

      return error_response("Image ID is required") if image_id.blank?

      # Find the image asset
      image_asset = ImageAsset.by_entity(entity.id).find_by(id: image_id)
      return error_response("Image not found") unless image_asset
      return error_response("Image has no attached file") unless image_asset.file.attached?

      begin
        # Find or create the entity's RAG store
        rag_store = RagStore.find_or_create_by!(
          entity: entity,
          store_type: "entity",
          app_name: "amos"
        ) do |store|
          store.name = "#{entity.name} Documents"
          store.user = user
          store.status = "active"
        end

        # Check if this image is already saved to RAG
        existing_doc = rag_store.rag_documents.find_by(
          "docling_metadata->>'image_asset_id' = ?", image_asset.id.to_s
        )

        if existing_doc
          return success_response(
            message: "This image is already saved to your documents",
            already_saved: true,
            rag_document_id: existing_doc.id,
            title: existing_doc.title
          )
        end

        # Calculate file hash
        file_hash = Digest::SHA256.hexdigest(image_asset.file.download)

        # Determine title
        doc_title = custom_title.presence || image_asset.title.presence || "AI-generated image"

        # Create RAG document from the image
        rag_document = rag_store.rag_documents.create!(
          original_filename: image_asset.file.filename.to_s,
          content_type: image_asset.file.content_type,
          file_size_bytes: image_asset.file.byte_size,
          file_hash: file_hash,
          title: doc_title,
          processing_status: "completed",
          docling_metadata: {
            source: "image_asset",
            image_asset_id: image_asset.id,
            provider: image_asset.source,
            description: image_asset.description,
            tags: tags
          }
        )

        # Attach the same file to the RAG document
        rag_document.file.attach(image_asset.file.blob)

        # Add tags if provided
        if tags.any?
          rag_document.add_tags(tags, "user")
        end

        # Create a chunk with the image description for semantic search
        searchable_content = [
          "Image: #{doc_title}",
          image_asset.description.presence,
          "Tags: #{tags.join(', ')}".presence
        ].compact.join(". ")

        rag_document.rag_chunks.create!(
          content: searchable_content,
          chunk_index: 0,
          chunk_type: "image_description",
          metadata: {
            image_asset_id: image_asset.id,
            provider: image_asset.source
          }
        )

        Rails.logger.info "[SaveImageToDocumentsTool] Saved image #{image_asset.id} to RAG document #{rag_document.id}"

        # Update canvas to show saved status
        @context[:canvas_suggestion] = "image_viewer"
        @context[:canvas_data] = {
          image_id: image_asset.id,
          saved_to_rag: true,
          rag_document_id: rag_document.id
        }

        success_response(
          message: "Image saved to your documents successfully",
          rag_document_id: rag_document.id,
          title: doc_title,
          image_id: image_asset.id
        )
      rescue => e
        Rails.logger.error "[SaveImageToDocumentsTool] Failed to save image: #{e.message}"
        error_response("Failed to save image: #{e.message}")
      end
    end
  end
end
