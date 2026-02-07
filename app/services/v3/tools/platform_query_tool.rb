# frozen_string_literal: true

module V3
  module Tools
    # PlatformQueryTool - Universal read tool for all platform data
    #
    # Consolidates: get_data, get_schema, list_*, view_*
    #
    # The model tells us WHAT it wants, we figure out HOW to get it.
    # Instead of 20+ specialized query tools, there's one tool that
    # can query any object type with any filters.
    #
    # Usage:
    #   platform_query(type: "contacts", filters: { status: "active" }, limit: 10)
    #   platform_query(type: "campaigns", include: ["metrics", "contact_groups"])
    #   platform_query(type: "schema", object: "contacts")  # Get schema info
    #   platform_query(type: "landing_pages", id: 123)       # Get specific record
    #
    class PlatformQueryTool < ::Tools::BaseTool
      def self.read_only?
        true
      end

      def self.metadata
        {
          name: "platform_query",
          description: <<~DESC.strip,
            Query any platform data. Use type to specify what to query.
            
            Examples:
            - platform_query(type: "contacts", filters: { lifecycle_stage: "lead" }, limit: 10)
            - platform_query(type: "landing_pages", id: 123)
            - platform_query(type: "schema", object: "contacts")
            - platform_query(type: "stats")
            - platform_query(type: "integrations")
            - platform_query(type: "documents", search: "contract terms")
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to query (e.g., 'contacts', 'campaigns', 'landing_pages', 'schema', 'stats', 'integrations')"
              },
              id: {
                type: ["string", "integer"],
                description: "Optional: specific record ID to fetch"
              },
              object: {
                type: "string",
                description: "For type='schema': which object to get schema for"
              },
              filters: {
                type: "object",
                description: "Filter criteria (e.g., { status: 'active', created_at: 'last_30_days' })"
              },
              include: {
                type: "array",
                description: "Related data to include (e.g., ['metrics', 'contact_groups'])",
                items: { type: "string" }
              },
              order_by: {
                type: "string",
                description: "Sort order (e.g., 'created_at desc')"
              },
              limit: {
                type: "integer",
                description: "Max records to return (default: 20, max: 100)"
              },
              search: {
                type: "string",
                description: "Text search across relevant fields"
              }
            },
            required: ["type"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        type = get_arg(args, :type)&.to_s&.downcase
        return error_response("Missing required field: type") if type.blank?

        case type
        when "schema"
          query_schema(args)
        when "stats"
          query_stats
        when "integrations"
          query_integrations(args)
        when "documents", "document"
          query_documents(args)
        else
          query_data(type, args)
        end
      rescue => e
        Rails.logger.error "[V3::PlatformQuery] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Query failed: #{e.message}")
      end

      private

      def query_schema(args)
        object = get_arg(args, :object)

        if object.blank?
          # List all available object types
          types = ScoutDataRegistry.available_object_types(entity)
          type_info = types.map do |t|
            config = ScoutDataRegistry.object_config(t, entity)
            {
              type: t,
              description: config&.dig(:description),
              creatable: config&.dig(:creatable) || false
            }
          end.compact

          success_response(
            available_types: type_info,
            count: type_info.length,
            message: "#{type_info.length} object types available. Query any type with platform_query(type: 'typename')."
          )
        else
          # Get schema for specific object type
          config = ScoutDataRegistry.object_config(object, entity)
          return error_response("Unknown object type: #{object}") unless config

          success_response(
            object_type: object,
            description: config[:description],
            queryable_fields: config[:queryable_fields],
            filterable_fields: config[:filterable_fields],
            metrics: config[:metrics],
            relationships: config[:relationships],
            creatable: config[:creatable] || false,
            creation_schema: config[:creation_schema]
          )
        end
      end

      def query_stats
        stats = {}

        # Safe count queries scoped to entity
        stat_models = {
          contacts: -> { entity.contacts.count },
          campaigns: -> { entity.campaigns.count },
          landing_pages: -> { entity.landing_pages.count },
          email_templates: -> { entity.email_templates.count },
          email_sequences: -> { entity.email_sequences.count },
          opportunities: -> { entity.opportunities.count rescue 0 },
          bounties: -> { entity.bounties.count rescue 0 },
          support_tickets: -> { entity.support_tickets.count rescue 0 },
          documents: -> { RagDocument.joins(:rag_store).where(rag_stores: { entity_id: entity.id }).count rescue 0 }
        }

        stat_models.each do |name, counter|
          stats[name] = counter.call rescue 0
        end

        # Active integrations
        stats[:active_integrations] = entity.connections.where(status: "active").count rescue 0

        success_response(
          stats: stats,
          entity: entity.name,
          message: "Platform overview for #{entity.name}"
        )
      end

      def query_integrations(args)
        connections = entity.connections.includes(:integration).map do |conn|
          {
            id: conn.id,
            integration: conn.integration&.name,
            slug: conn.integration&.slug,
            status: conn.status,
            connected_at: conn.created_at
          }
        end

        available = Integration.all.map do |i|
          {
            name: i.name,
            slug: i.slug,
            category: i.category,
            connected: connections.any? { |c| c[:slug] == i.slug }
          }
        end rescue connections

        success_response(
          connected: connections,
          available: available,
          count: connections.length
        )
      end

      def query_documents(args)
        doc_id = get_arg(args, :id)
        search_query = get_arg(args, :search)
        limit = [get_arg(args, :limit, 20).to_i, 50].min
        
        # Get all RAG stores for this entity
        rag_stores = entity.rag_stores.where(status: "active")
        
        if doc_id
          # Fetch specific document with content
          rag_doc = RagDocument.joins(:rag_store)
                               .where(rag_stores: { entity_id: entity.id })
                               .find_by(id: doc_id)
          
          return error_response("Document not found: #{doc_id}") unless rag_doc
          
          # Extract text content if available
          content = extract_document_content(rag_doc)
          
          success_response(
            document: {
              id: rag_doc.id,
              filename: rag_doc.original_filename,
              title: rag_doc.title || rag_doc.original_filename,
              content_type: rag_doc.content_type,
              size_bytes: rag_doc.file_size_bytes,
              status: rag_doc.processing_status,
              store: rag_doc.rag_store.name,
              created_at: rag_doc.created_at,
              content: content
            },
            content_length: content&.length || 0
          )
        elsif search_query.present?
          # Semantic search across documents
          search_documents(search_query, limit)
        else
          # List all documents
          documents = RagDocument.joins(:rag_store)
                                 .where(rag_stores: { entity_id: entity.id })
                                 .order(created_at: :desc)
                                 .limit(limit)
          
          doc_list = documents.map do |doc|
            {
              id: doc.id,
              filename: doc.original_filename,
              title: doc.title || doc.original_filename,
              content_type: doc.content_type,
              size_bytes: doc.file_size_bytes,
              status: doc.processing_status,
              store: doc.rag_store.name,
              created_at: doc.created_at
            }
          end
          
          success_response(
            documents: doc_list,
            count: doc_list.length,
            total: RagDocument.joins(:rag_store).where(rag_stores: { entity_id: entity.id }).count,
            message: "#{doc_list.length} document(s). Use id parameter to read content, or search parameter to find specific content."
          )
        end
      end
      
      def extract_document_content(rag_doc, max_chars: 50000)
        # Try to get content from chunks first (already processed)
        if rag_doc.rag_chunks.any?
          chunks = rag_doc.rag_chunks.order(:chunk_index).pluck(:content)
          content = chunks.join("\n\n")
          return content.truncate(max_chars) if content.present?
        end
        
        # Try extracted_text field
        return rag_doc.extracted_text.truncate(max_chars) if rag_doc.extracted_text.present?
        
        # Try to read file directly for simple text files
        if rag_doc.file.attached? && rag_doc.content_type&.start_with?("text/")
          begin
            content = rag_doc.file.download
            return content.force_encoding("UTF-8").truncate(max_chars)
          rescue => e
            Rails.logger.warn "[V3::PlatformQuery] Could not read file content: #{e.message}"
          end
        end
        
        nil
      end
      
      def search_documents(query, limit)
        # Use existing RAG infrastructure for semantic search
        begin
          results = []
          
          # Try vector search if available
          rag_service = RagStoreService.new(entity: entity)
          search_result = rag_service.search(query: query, top_k: limit)
          
          if search_result[:success] && search_result[:results].present?
            results = search_result[:results].map do |r|
              {
                document_id: r[:document_id],
                chunk_content: r[:content].truncate(500),
                relevance: r[:score],
                filename: r[:filename],
                title: r[:title]
              }
            end
          end
          
          success_response(
            query: query,
            results: results,
            count: results.length,
            search_type: "semantic",
            message: results.any? ? 
              "Found #{results.length} relevant section(s). Use platform_query(type: 'documents', id: X) to read full document." :
              "No matching content found."
          )
        rescue => e
          Rails.logger.warn "[V3::PlatformQuery] Semantic search failed: #{e.message}"
          
          # Fallback to text search
          docs = RagDocument.joins(:rag_store)
                            .where(rag_stores: { entity_id: entity.id })
                            .where("original_filename ILIKE :q OR title ILIKE :q OR extracted_text ILIKE :q", q: "%#{query}%")
                            .limit(limit)
          
          results = docs.map do |doc|
            {
              document_id: doc.id,
              filename: doc.original_filename,
              title: doc.title,
              match_type: "text"
            }
          end
          
          success_response(
            query: query,
            results: results,
            count: results.length,
            search_type: "text",
            message: results.any? ? "Found #{results.length} document(s) matching '#{query}'." : "No matching documents found."
          )
        end
      end

      def query_data(type, args)
        object_id = get_arg(args, :id)
        filters = get_arg(args, :filters, {})
        includes = get_arg(args, :include, [])
        order_by = get_arg(args, :order_by, "created_at desc")
        limit = [get_arg(args, :limit, 20).to_i, 100].min
        search = get_arg(args, :search)

        # Normalize type (handle singular/plural)
        normalized_type = normalize_type(type)

        # Validate object type exists
        available = ScoutDataRegistry.available_object_types(entity)
        unless available.include?(normalized_type)
          closest = find_closest(normalized_type, available)
          return error_response(
            "Unknown type: #{type}",
            suggestion: closest ? "Did you mean: #{closest}?" : nil,
            available_types: available.first(20)
          )
        end

        if object_id
          fetch_single_record(normalized_type, object_id, includes)
        else
          fetch_records(normalized_type, filters, order_by, limit, includes, search)
        end
      end

      def fetch_single_record(type, id, includes)
        # Use UniversalQueryEngine
        query_engine = UniversalQueryEngine.new(user, entity)
        result = query_engine.execute_get_data(
          objects: [type],
          filters: { id: id },
          limit: 1,
          include_metrics: includes.include?("metrics"),
          include_relationships: includes.any?
        )

        if result[:success]
          data = result[:data][type]
          records = data&.dig(:records) || []
          if records.any?
            success_response(
              type: type,
              record: records.first,
              metadata: result[:metadata]
            )
          else
            error_response("#{type.singularize.titleize} not found with ID: #{id}")
          end
        else
          error_response(result[:error] || "Query failed")
        end
      end

      def fetch_records(type, filters, order_by, limit, includes, search)
        # Process date range filters
        filters = process_date_filters(filters)

        query_engine = UniversalQueryEngine.new(user, entity)
        result = query_engine.execute_get_data(
          objects: [type],
          filters: filters,
          limit: limit,
          order_by: order_by,
          include_metrics: includes.include?("metrics"),
          include_relationships: includes.any?,
          search: search
        )

        if result[:success]
          data = result[:data][type] || {}
          records = data[:records] || []
          total = data[:total_available] || data[:total_count] || records.length

          success_response(
            type: type,
            records: records,
            count: records.length,
            total: total,
            has_more: total > records.length,
            filters_applied: filters,
            metadata: result[:metadata]
          )
        else
          error_response(result[:error] || "Query failed")
        end
      end

      def normalize_type(type)
        # Map common singular to plural, or leave as-is for module types
        singular_to_plural = {
          "campaign" => "campaigns",
          "contact" => "contacts",
          "landing_page" => "landing_pages",
          "email_template" => "email_templates",
          "email_sequence" => "email_sequences",
          "email_delivery" => "email_deliveries",
          "opportunity" => "opportunities",
          "activity" => "activities",
          "bounty" => "bounties",
          "support_ticket" => "support_tickets",
          "contact_group" => "contact_groups"
        }
        singular_to_plural[type] || type
      end

      def process_date_filters(filters)
        return filters unless filters.is_a?(Hash)

        filters.transform_values do |value|
          case value.to_s
          when "today" then Date.current
          when "yesterday" then Date.yesterday
          when "last_7_days" then 7.days.ago..Date.current
          when "last_30_days" then 30.days.ago..Date.current
          when "last_90_days" then 90.days.ago..Date.current
          when "this_month" then Date.current.beginning_of_month..Date.current
          when "this_year" then Date.current.beginning_of_year..Date.current
          else value
          end
        end
      end

      def find_closest(input, options)
        return nil if options.empty?
        options.min_by { |opt| levenshtein(input.downcase, opt.downcase) }
      end

      def levenshtein(s1, s2)
        m, n = s1.length, s2.length
        return n if m == 0
        return m if n == 0
        d = Array.new(m + 1) { Array.new(n + 1) }
        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }
        (1..n).each do |j|
          (1..m).each do |i|
            cost = s1[i - 1] == s2[j - 1] ? 0 : 1
            d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].min
          end
        end
        d[m][n]
      end
    end
  end
end
