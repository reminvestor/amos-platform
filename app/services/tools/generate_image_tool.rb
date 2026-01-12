# frozen_string_literal: true

module Tools
  class GenerateImageTool < BaseTool
    def self.metadata
      {
        name: "generate_image",
        description: "Generate an AI image from a text description. USE THIS TOOL IMMEDIATELY when user asks to create/generate/make an image. Supports quality levels: 'standard' (fast, default) or 'pro'/'high quality' (better text rendering, higher fidelity). User can say 'use pro', 'high quality', or 'hd' to get the pro model.",
        category: "creative",
        input_schema: {
          type: "object",
          properties: {
            prompt: {
              type: "string",
              description: "Detailed description of the image to generate. Be specific about style, colors, composition, and subject matter."
            },
            quality: {
              type: "string",
              enum: ["standard", "pro", "hd", "high"],
              description: "Quality level: 'standard' (fast, default) or 'pro'/'hd'/'high' (high-fidelity, better text). Use pro when user asks for 'high quality', 'pro', 'hd', or 'better quality'."
            },
            aspect_ratio: {
              type: "string",
              enum: ["square", "landscape", "portrait", "wide", "tall"],
              description: "Image aspect ratio. 'square' (1:1), 'landscape' (16:9), 'portrait' (9:16), 'wide' (4:3), 'tall' (3:4). Defaults to square."
            },
            title: {
              type: "string",
              description: "Optional title for the image asset"
            },
            save_to_documents: {
              type: "boolean",
              description: "Whether to also save the image to the entity's document store (RAG) for AI retrieval. Defaults to false."
            }
          },
          required: ["prompt"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      prompt = get_arg(args, :prompt)
      quality = get_arg(args, :quality, "standard")&.downcase
      aspect_ratio = get_arg(args, :aspect_ratio, "square")
      title = get_arg(args, :title, prompt.truncate(50))
      save_to_documents = get_arg(args, :save_to_documents, false)

      return error_response("Prompt is required") if prompt.blank?

      begin
        # Determine provider based on quality setting
        provider = quality_to_provider(quality)
        provider_name = provider == :gemini_pro ? "Gemini Nano Banana Pro" : "Gemini Nano Banana"

        # Map aspect ratio to size
        size = aspect_ratio_to_size(aspect_ratio)

        Rails.logger.info "[GenerateImageTool] Using #{provider_name} for quality=#{quality}"

        # Initialize service with provider
        service = ImageGenerationService.new(provider: provider)

        # Generate and store the image
        image_asset = service.generate_and_store!(
          user: user,
          entity: entity,
          title: title,
          description: prompt,
          size: size,
          tags: ["ai-generated", provider.to_s, "quality-#{quality}"]
        )

        # Get the URL for display and download
        host = ENV.fetch("APP_HOST", "localhost:3000")
        image_url = nil
        download_url = nil

        if image_asset.file.attached?
          image_url = Rails.application.routes.url_helpers.rails_blob_url(
            image_asset.file,
            host: host
          )
          download_url = Rails.application.routes.url_helpers.rails_blob_url(
            image_asset.file,
            host: host,
            disposition: "attachment"
          )
        end

        # Optionally save to RAG store
        rag_document = nil
        if save_to_documents
          rag_document = save_image_to_rag(image_asset)
        end

        # Set canvas suggestion for image viewer
        @context[:canvas_suggestion] = "image_viewer"
        @context[:canvas_data] = {
          image_id: image_asset.id,
          image_url: image_url,
          download_url: download_url,
          title: image_asset.title,
          description: prompt,
          provider: provider.to_s,
          provider_name: provider_name,
          aspect_ratio: aspect_ratio,
          quality: quality,
          created_at: image_asset.created_at.iso8601,
          saved_to_rag: rag_document.present?,
          rag_document_id: rag_document&.id
        }

        # Response data without image URLs - image shows only in canvas
        response_data = {
          message: "Image generated successfully using #{provider_name}",
          image_id: image_asset.id,
          title: image_asset.title,
          provider: provider.to_s,
          quality: quality,
          prompt: prompt
        }

        if rag_document
          response_data[:saved_to_rag] = true
          response_data[:rag_document_id] = rag_document.id
          response_data[:message] += " and saved to your documents"
        end

        success_response(**response_data)
      rescue ArgumentError => e
        error_response("Configuration error: #{e.message}")
      rescue GeminiImageService::RateLimitError => e
        error_response("Rate limit exceeded. Please try again in a few seconds.")
      rescue GeminiImageService::SafetyFilterError => e
        error_response("Image generation blocked by safety filters. Please modify your prompt.")
      rescue => e
        Rails.logger.error "Image generation failed: #{e.class} - #{e.message}"
        error_response("Image generation failed: #{e.message}")
      end
    end

    private

    def quality_to_provider(quality)
      case quality.to_s.downcase
      when "pro", "hd", "high", "high_quality", "premium"
        :gemini_pro
      else
        :gemini
      end
    end

    def aspect_ratio_to_size(aspect_ratio)
      case aspect_ratio.to_s.downcase
      when "landscape" then "1920x1080"
      when "portrait" then "1080x1920"
      when "wide" then "1200x900"
      when "tall" then "900x1200"
      else "1024x1024"
      end
    end

    # Save the image to the entity's RAG store for AI retrieval
    def save_image_to_rag(image_asset)
      return nil unless entity && image_asset.file.attached?

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

      # Calculate file hash
      file_hash = Digest::SHA256.hexdigest(image_asset.file.download)

      # Create RAG document from the image
      rag_document = rag_store.rag_documents.create!(
        original_filename: image_asset.file.filename.to_s,
        content_type: image_asset.file.content_type,
        file_size_bytes: image_asset.file.byte_size,
        file_hash: file_hash,
        title: image_asset.title,
        processing_status: "completed",
        docling_metadata: {
          source: "ai_generated_image",
          provider: image_asset.source,
          description: image_asset.description,
          image_asset_id: image_asset.id
        }
      )

      # Attach the same file to the RAG document
      rag_document.file.attach(image_asset.file.blob)

      # Create a single chunk with the image description for semantic search
      rag_document.rag_chunks.create!(
        content: "AI-generated image: #{image_asset.title}. #{image_asset.description}",
        chunk_index: 0,
        chunk_type: "image_description",
        metadata: {
          image_asset_id: image_asset.id,
          provider: image_asset.source
        }
      )

      Rails.logger.info "[GenerateImageTool] Saved image #{image_asset.id} to RAG document #{rag_document.id}"
      rag_document
    rescue => e
      Rails.logger.error "[GenerateImageTool] Failed to save image to RAG: #{e.message}"
      nil
    end
  end
end
