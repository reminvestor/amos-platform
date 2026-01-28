# frozen_string_literal: true

module Api
  module V1
    class VisionController < Api::BaseController
      before_action :authenticate_api_user!

      # POST /api/v1/vision/scan_business_card
      # Scans a business card image and extracts contact information
      #
      # Request body (JSON):
      #   { "image": "base64_encoded_image_data", "mime_type": "image/jpeg" }
      #
      # Or multipart form:
      #   image: file upload
      #
      def scan_business_card
        image_data, mime_type = extract_image_from_request

        unless image_data.present?
          return render json: {
            success: false,
            error: "No image provided. Send base64 'image' field or upload a file."
          }, status: :bad_request
        end

        begin
          service = GeminiVisionService.new
          contact_data = service.extract_business_card(image_data, mime_type: mime_type)

          if contact_data[:error].present?
            render json: {
              success: false,
              error: contact_data[:error],
              raw_text: contact_data[:raw_text]
            }, status: :unprocessable_entity
          else
            render json: {
              success: true,
              contact: contact_data
            }
          end
        rescue GeminiVisionService::RateLimitError => e
          render json: {
            success: false,
            error: "Rate limit exceeded. Please try again later."
          }, status: :too_many_requests
        rescue GeminiVisionService::VisionError => e
          Rails.logger.error("Vision API error: #{e.message}")
          render json: {
            success: false,
            error: e.message
          }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("Unexpected error in scan_business_card: #{e.class.name}: #{e.message}")
          Rails.logger.error(e.backtrace.first(10).join("\n"))
          render json: {
            success: false,
            error: "An unexpected error occurred"
          }, status: :internal_server_error
        end
      end

      # POST /api/v1/vision/scan
      # Unified scan endpoint - extracts data based on mode
      #
      # Modes: business_card, receipt, document, whiteboard
      #
      def scan
        image_data, mime_type = extract_image_from_request
        mode = params[:mode]&.to_sym || :business_card

        unless image_data.present?
          return render json: { success: false, error: "No image provided" }, status: :bad_request
        end

        unless %i[business_card receipt document whiteboard].include?(mode)
          return render json: { success: false, error: "Invalid mode" }, status: :bad_request
        end

        begin
          service = GeminiVisionService.new
          data = case mode
                 when :business_card
                   service.extract_business_card(image_data, mime_type: mime_type)
                 when :receipt
                   service.extract_receipt(image_data, mime_type: mime_type)
                 when :document
                   service.extract_document(image_data, mime_type: mime_type)
                 when :whiteboard
                   service.extract_whiteboard(image_data, mime_type: mime_type)
                 end

          if data[:error].present?
            render json: { success: false, error: data[:error] }, status: :unprocessable_entity
          else
            render json: { success: true, mode: mode, data: data }
          end
        rescue GeminiVisionService::RateLimitError
          render json: { success: false, error: "Rate limit exceeded" }, status: :too_many_requests
        rescue GeminiVisionService::VisionError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("Scan error: #{e.class.name}: #{e.message}")
          render json: { success: false, error: "An unexpected error occurred" }, status: :internal_server_error
        end
      end

      # POST /api/v1/vision/scan_and_save
      # Unified scan + save endpoint
      #
      def scan_and_save
        image_data, mime_type = extract_image_from_request
        mode = params[:mode]&.to_sym || :business_card

        unless image_data.present?
          return render json: { success: false, error: "No image provided" }, status: :bad_request
        end

        begin
          service = GeminiVisionService.new

          case mode
          when :business_card
            save_business_card(service, image_data, mime_type)
          when :receipt
            save_receipt(service, image_data, mime_type)
          when :document
            save_document(service, image_data, mime_type)
          when :whiteboard
            save_whiteboard(service, image_data, mime_type)
          else
            render json: { success: false, error: "Invalid mode" }, status: :bad_request
          end
        rescue GeminiVisionService::RateLimitError
          render json: { success: false, error: "Rate limit exceeded" }, status: :too_many_requests
        rescue GeminiVisionService::VisionError => e
          render json: { success: false, error: e.message }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("Scan and save error: #{e.class.name}: #{e.message}")
          render json: { success: false, error: "An unexpected error occurred" }, status: :internal_server_error
        end
      end

      # POST /api/v1/vision/scan_business_card_and_save
      # Scans a business card and creates a contact in one step
      #
      def scan_business_card_and_save
        image_data, mime_type = extract_image_from_request

        unless image_data.present?
          return render json: {
            success: false,
            error: "No image provided"
          }, status: :bad_request
        end

        begin
          # Extract contact info from image
          service = GeminiVisionService.new
          contact_data = service.extract_business_card(image_data, mime_type: mime_type)

          if contact_data[:error].present?
            return render json: {
              success: false,
              error: contact_data[:error],
              raw_text: contact_data[:raw_text]
            }, status: :unprocessable_entity
          end

          # Create the contact
          contact = Contact.new(
            user: current_user,
            entity: current_user.entity,
            email: contact_data[:email],
            first_name: contact_data[:first_name] || contact_data[:name]&.split&.first,
            last_name: contact_data[:last_name] || contact_data[:name]&.split&.drop(1)&.join(" "),
            phone: contact_data[:phone] || contact_data[:mobile],
            status: "active",
            lead: true,
            metadata: {
              company: contact_data[:company],
              title: contact_data[:title],
              website: contact_data[:website],
              address: contact_data[:address],
              linkedin: contact_data[:linkedin],
              twitter: contact_data[:twitter],
              notes: contact_data[:notes],
              source: "business_card_scan",
              scanned_at: Time.current.iso8601
            }.compact
          )

          if contact.save
            render json: {
              success: true,
              message: "Contact created successfully",
              contact: {
                id: contact.id,
                email: contact.email,
                first_name: contact.first_name,
                last_name: contact.last_name,
                phone: contact.phone,
                company: contact_data[:company],
                title: contact_data[:title]
              },
              extracted_data: contact_data
            }
          else
            render json: {
              success: false,
              error: "Failed to save contact",
              validation_errors: contact.errors.full_messages,
              extracted_data: contact_data
            }, status: :unprocessable_entity
          end
        rescue GeminiVisionService::RateLimitError
          render json: {
            success: false,
            error: "Rate limit exceeded. Please try again later."
          }, status: :too_many_requests
        rescue GeminiVisionService::VisionError => e
          render json: {
            success: false,
            error: e.message
          }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("Error in scan_business_card_and_save: #{e.class.name}: #{e.message}")
          render json: {
            success: false,
            error: "An unexpected error occurred"
          }, status: :internal_server_error
        end
      end

      private

      def save_business_card(service, image_data, mime_type)
        data = service.extract_business_card(image_data, mime_type: mime_type)
        return render json: { success: false, error: data[:error] }, status: :unprocessable_entity if data[:error]

        contact = Contact.new(
          user: current_user,
          entity: current_user.entity,
          email: data[:email],
          first_name: data[:first_name] || data[:name]&.split&.first,
          last_name: data[:last_name] || data[:name]&.split&.drop(1)&.join(" "),
          phone: data[:phone] || data[:mobile],
          status: "active",
          lead: true,
          metadata: {
            company: data[:company], title: data[:title], website: data[:website],
            address: data[:address], linkedin: data[:linkedin], twitter: data[:twitter],
            notes: data[:notes], source: "scan", scanned_at: Time.current.iso8601
          }.compact
        )

        if contact.save
          render json: { success: true, id: contact.id, message: "Contact saved!" }
        else
          render json: { success: false, error: contact.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def save_receipt(service, image_data, mime_type)
        data = service.extract_receipt(image_data, mime_type: mime_type)
        return render json: { success: false, error: data[:error] }, status: :unprocessable_entity if data[:error]

        # Create a note with the receipt data for now
        # TODO: Create proper Expense model when needed
        note = current_user.entity.hub_threads.create!(
          user: current_user,
          thread_type: "personal_note",
          title: "Receipt: #{data[:merchant] || 'Unknown'}",
          content: format_receipt_note(data),
          metadata: { source: "receipt_scan", receipt_data: data }
        )

        render json: { success: true, id: note.id, message: "Receipt saved to notes!" }
      end

      def save_document(service, image_data, mime_type)
        data = service.extract_document(image_data, mime_type: mime_type)
        return render json: { success: false, error: data[:error] }, status: :unprocessable_entity if data[:error]

        # Find or create default RAG store for entity
        rag_store = current_user.entity.rag_stores.find_or_create_by!(
          name: "Knowledge Base",
          app_name: "amos",
          store_type: "entity",
          user: current_user
        ) do |store|
          store.status = "active"
        end

        # Create a temp file from the scanned image
        extension = mime_type_to_extension(mime_type)
        filename = "#{sanitize_filename(data[:title] || 'Scanned_Document')}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.#{extension}"
        temp_file = Tempfile.new([filename, ".#{extension}"])
        temp_file.binmode
        temp_file.write(Base64.decode64(image_data))
        temp_file.rewind

        # Calculate file hash
        file_hash = Digest::SHA256.file(temp_file.path).hexdigest

        # Create RAG document
        document = rag_store.rag_documents.create!(
          original_filename: filename,
          title: data[:title] || "Scanned Document",
          content_type: mime_type,
          file_size_bytes: temp_file.size,
          file_hash: file_hash,
          processing_status: "completed",
          is_latest_version: true,
          version: 1,
          docling_metadata: {
            extracted_text: data[:text],
            scan_data: data,
            source: "mobile_scanner",
            scanned_at: Time.current.iso8601
          }
        )

        # Attach the image file
        document.file.attach(
          io: temp_file,
          filename: filename,
          content_type: mime_type
        )

        # Clean up temp file
        temp_file.close
        temp_file.unlink

        # Create a single chunk with the extracted text for RAG queries
        if data[:text].present?
          document.rag_chunks.create!(
            content: data[:text],
            chunk_index: 0,
            metadata: {
              source: "mobile_scan",
              title: data[:title],
              type: data[:type]
            }
          )
        end

        render json: {
          success: true,
          id: document.id,
          message: "Document added to Knowledge Base!"
        }
      rescue => e
        Rails.logger.error("Failed to save scanned document: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: "Failed to save document: #{e.message}" }, status: :internal_server_error
      end

      def save_whiteboard(service, image_data, mime_type)
        data = service.extract_whiteboard(image_data, mime_type: mime_type)
        return render json: { success: false, error: data[:error] }, status: :unprocessable_entity if data[:error]

        # Create a note with the whiteboard content
        note = current_user.entity.hub_threads.create!(
          user: current_user,
          thread_type: "personal_note",
          title: data[:title] || "Whiteboard Notes",
          content: format_whiteboard_note(data),
          metadata: { source: "whiteboard_scan", whiteboard_data: data }
        )

        render json: { success: true, id: note.id, message: "Whiteboard saved to notes!" }
      end

      def format_receipt_note(data)
        lines = []
        lines << "## Receipt from #{data[:merchant]}" if data[:merchant]
        lines << "**Date:** #{data[:date]}" if data[:date]
        lines << "**Total:** #{data[:total]}" if data[:total]
        lines << ""
        if data[:items].present?
          lines << "### Items"
          data[:items].each { |item| lines << "- #{item}" }
        end
        lines << ""
        lines << "**Category:** #{data[:category]}" if data[:category]
        lines.join("\n")
      end

      def format_whiteboard_note(data)
        lines = []
        lines << data[:summary] if data[:summary]
        lines << ""
        if data[:key_points].present?
          lines << "## Key Points"
          data[:key_points].each { |point| lines << "- #{point}" }
        end
        if data[:action_items].present?
          lines << ""
          lines << "## Action Items"
          data[:action_items].each { |item| lines << "- [ ] #{item}" }
        end
        lines << ""
        lines << "---"
        lines << "*Raw text:*"
        lines << data[:text] if data[:text]
        lines.join("\n")
      end

      def mime_type_to_extension(mime_type)
        case mime_type&.downcase
        when 'image/jpeg', 'image/jpg'
          'jpg'
        when 'image/png'
          'png'
        when 'image/heic', 'image/heif'
          'heic'
        when 'image/webp'
          'webp'
        else
          'jpg'
        end
      end

      def sanitize_filename(name)
        name.to_s.gsub(/[^a-zA-Z0-9_\-]/, '_').slice(0, 50)
      end

      def extract_image_from_request
        # Check for file upload first
        if params[:image].is_a?(ActionDispatch::Http::UploadedFile)
          file = params[:image]
          return [
            Base64.strict_encode64(file.read),
            file.content_type || "image/jpeg"
          ]
        end

        # Check for base64 encoded image in JSON body
        if params[:image].is_a?(String) && params[:image].present?
          # Remove data URL prefix if present (e.g., "data:image/jpeg;base64,")
          image_data = params[:image]
          mime_type = params[:mime_type] || "image/jpeg"

          if image_data.include?(",")
            # Parse data URL
            match = image_data.match(/data:([^;]+);base64,(.+)/)
            if match
              mime_type = match[1]
              image_data = match[2]
            else
              image_data = image_data.split(",").last
            end
          end

          return [image_data, mime_type]
        end

        [nil, nil]
      end
    end
  end
end
