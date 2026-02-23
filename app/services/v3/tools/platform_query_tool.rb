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
            Read-only query for platform data. Use for viewing existing records.
            For actions that CHANGE data, use platform_create/platform_update/platform_execute.
            
            Examples:
            - type: "contacts", filters: { lifecycle_stage: "lead" }, limit: 10
            - type: "landing_pages", id: 123
            - type: "schema", object: "contacts"
            - type: "stats"
            - type: "integrations"
            - type: "custom_domains" — list all custom domains and their status
            - type: "custom_domains", id: 123 — get specific domain with DNS records
            - type: "documents", search: "contract terms"
            - type: "tasks", filters: { status: "in_progress" }
            - type: "schema" — lists ALL types including custom app models
            - type: "canvases", search: "contact" — find canvases by name/slug
            - type: "canvases", id: 256 — get canvas details, lock status, and version history
            - type: "canvas_versions", id: 256 — list all saved versions of a canvas
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              type: {
                type: "string",
                description: "Object type to query (e.g., 'contacts', 'campaigns', 'landing_pages', 'schema', 'stats', 'integrations', 'custom_domains', 'integration_operations', 'integration_actions')"
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
        when "integration_operations"
          query_integration_operations(args)
        when "integration_actions"
          query_integration_actions(args)
        when "documents", "document"
          query_documents(args)
        when "usage", "credits", "tokens", "balance"
          query_usage
        when "custom_domains", "custom_domain", "domains", "domain"
          query_custom_domains(args)
        when "canvases", "canvas", "canva", "module_canvases", "module_canvas", "module_canva"
          query_canvases(args)
        when "canvas_versions", "canva_versions"
          query_canvas_versions(args)
        else
          query_data(type, args)
        end
      rescue => e
        Rails.logger.error "[V3::PlatformQuery] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        V3::AiErrorTransformer.transform(e, type: type, tool: "platform_query")
      end

      private

      def query_schema(args)
        object = get_arg(args, :object)

        if object.blank?
          # List all available object types (includes dynamic modules)
          types = ScoutDataRegistry.available_object_types(entity)
          type_info = types.map do |t|
            config = ScoutDataRegistry.object_config(t, entity)
            info = {
              type: t,
              description: config&.dig(:description),
              creatable: config&.dig(:creatable) || false
            }
            # Tag dynamic module types so the Brain knows they're user-built apps
            info[:dynamic] = true if config&.dig(:dynamic)
            info[:module_slug] = config[:module_slug] if config&.dig(:module_slug)
            info
          end.compact

          # Separate built-in and dynamic types for clarity
          built_in = type_info.reject { |t| t[:dynamic] }
          dynamic = type_info.select { |t| t[:dynamic] }

          success_response(
            available_types: type_info,
            built_in_types: built_in.map { |t| t[:type] },
            module_types: dynamic.map { |t| { type: t[:type], description: t[:description], module_slug: t[:module_slug] } },
            count: type_info.length,
            message: "#{type_info.length} object types available (#{built_in.length} built-in, #{dynamic.length} from custom apps). Query any type using the platform_query tool with type='typename'."
          )
        else
          # Get schema for specific object type
          config = ScoutDataRegistry.object_config(object, entity)

          # If not found in registry, try dynamic module resolution
          if config.nil?
            model_class = resolve_dynamic_model(object)
            if model_class
              fields = model_class.columns.map { |c| { name: c.name, type: c.type.to_s } }
              fields.reject! { |f| %w[id entity_id user_id created_by_id created_at updated_at].include?(f[:name]) }
              result = {
                object_type: object,
                description: "Dynamic module: #{object.titleize}",
                fields: fields,
                queryable_fields: model_class.column_names,
                filterable_fields: model_class.column_names,
                creatable: true,
                dynamic: true
              }

              # Auto-include custom fields for dynamic modules too
              custom_fields = CustomFieldDefinition.where(entity: entity, model_type: model_class.name, active: true).ordered rescue []
              if custom_fields.any?
                result[:custom_fields] = custom_fields.map do |f|
                  { field_name: f.field_name, field_type: f.field_type, label: f.label, required: f.required? }.compact
                end
                result[:custom_field_count] = custom_fields.length
              end

              return success_response(result)
            end
          end

          return error_response("Unknown object type: #{object}") unless config

          response = {
            object_type: object,
            description: config[:description],
            queryable_fields: config[:queryable_fields],
            filterable_fields: config[:filterable_fields],
            metrics: config[:metrics],
            relationships: config[:relationships],
            creatable: config[:creatable] || false,
            creation_schema: config[:creation_schema]
          }
          response[:dynamic] = true if config[:dynamic]
          response[:module_slug] = config[:module_slug] if config[:module_slug]

          # Auto-include custom fields for this entity + model type
          # so the Brain sees the full schema in ONE query (no separate custom field lookup needed)
          model_type = config[:model] || object.classify
          custom_fields = CustomFieldDefinition.where(entity: entity, model_type: model_type, active: true).ordered rescue []
          if custom_fields.any?
            response[:custom_fields] = custom_fields.map do |f|
              {
                field_name: f.field_name,
                field_type: f.field_type,
                label: f.label,
                display_type: f.display_type,
                required: f.required?,
                options: f.option_values.presence
              }.compact
            end
            response[:custom_field_count] = custom_fields.length
          end

          success_response(response)
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

      def query_usage
        account = UserBillingAccount.find_by(user: user)

        unless account
          return success_response(
            balance: 0,
            status: "no_account",
            message: "No billing account found. Contact support to set up billing."
          )
        end

        # Today's usage
        today_summary = WorkTokenUsageSummary.find_by(
          user: user, entity: entity,
          summary_date: Date.current, category: "ai_tokens"
        )

        success_response(
          balance: account.work_token_balance,
          lifetime_used: account.lifetime_tokens_used,
          status: account.status,
          has_payment_method: account.has_payment_method,
          auto_replenish: account.auto_replenish_enabled,
          today_tokens: today_summary&.tokens_used || 0,
          today_cost_cents: today_summary&.raw_cost_cents || 0,
          today_transactions: today_summary&.transaction_count || 0,
          message: "Balance: #{account.work_token_balance.to_i.abs} tokens. Today: #{today_summary&.tokens_used || 0} tokens used."
        )
      end

      def query_custom_domains(args)
        domain_id = get_arg(args, :id) || get_arg(args, :domain_id)

        if domain_id.present?
          # Single domain detail
          domain = entity.custom_domains.find_by(id: domain_id)
          return error_response("Custom domain not found: #{domain_id}") unless domain

          return success_response(
            domain: format_domain(domain),
            dns_records: domain.dns_records,
            message: "Domain: #{domain.full_domain} — Web: #{domain.web_status}, Email: #{domain.email_status}, SSL: #{domain.ssl_status}",
            canvas_type: "custom_domains"
          )
        end

        # List all domains
        domains = entity.custom_domains.order(created_at: :desc)

        success_response(
          domains: domains.map { |d| format_domain(d) },
          count: domains.count,
          message: domains.any? ?
            "#{domains.count} custom domain(s) configured." :
            "No custom domains configured yet. Use platform_create(type: 'custom_domain') to add one.",
          canvas_type: "custom_domains"
        )
      end

      def format_domain(domain)
        {
          id: domain.id,
          domain_name: domain.domain_name,
          subdomain: domain.subdomain,
          full_domain: domain.full_domain,
          cname_target: domain.cname_target,
          web_status: domain.web_status,
          email_status: domain.email_status,
          ssl_status: domain.ssl_status,
          is_primary: domain.is_primary,
          fully_configured: domain.fully_configured?,
          created_at: domain.created_at
        }
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

      def query_integration_operations(args)
        integration_slug = get_arg(args, :integration) || get_arg(args, :search)
        return error_response("Missing: integration slug (e.g., 'stripe')") if integration_slug.blank?

        integration = Integration.find_by(slug: integration_slug) ||
                      Integration.where(entity: entity).find_by(slug: integration_slug) ||
                      Integration.where("name ILIKE ?", "%#{integration_slug}%").first

        return error_response("Integration '#{integration_slug}' not found") unless integration

        operations = integration.integration_operations.order(:name).map do |op|
          {
            id: op.id,
            operation_id: op.operation_id,
            name: op.name,
            description: op.description,
            http_method: op.http_method,
            path: op.path_template,
            has_action: IntegrationAction.exists?(integration: integration, integration_operation: op),
            request_schema_fields: op.request_schema&.dig("properties")&.keys&.first(10)
          }
        end

        success_response(
          integration: integration.name,
          integration_id: integration.id,
          slug: integration.slug,
          operations: operations,
          count: operations.length,
          message: "#{operations.length} operation(s) for #{integration.name}. Operations with has_action=true have smart mapping code."
        )
      end

      def query_integration_actions(args)
        integration_slug = get_arg(args, :integration)
        search = get_arg(args, :search)

        if integration_slug.blank? && search.blank?
          return error_response("Provide 'integration' slug or 'search' term")
        end

        scope = IntegrationAction.for_entity(entity)

        if integration_slug.present?
          integration = Integration.find_by(slug: integration_slug) ||
                        Integration.where(entity: entity).find_by(slug: integration_slug)
          return error_response("Integration '#{integration_slug}' not found") unless integration
          scope = scope.where(integration: integration)
        end

        if search.present?
          scope = scope.where("action_name ILIKE :q OR description ILIKE :q OR slug ILIKE :q", q: "%#{search}%")
        end

        actions = scope.usable.order(:action_name).limit(50).map do |action|
          {
            id: action.id,
            slug: action.slug,
            name: action.action_name,
            description: action.description,
            category: action.category,
            status: action.status,
            input_schema: action.input_schema,
            required_fields: action.required_fields,
            usage_count: action.usage_count,
            success_rate: action.success_rate,
            has_mapping_code: action.mapping_code.present?,
            last_used_at: action.last_used_at
          }
        end

        success_response(
          integration: integration_slug,
          actions: actions,
          count: actions.length,
          message: actions.any? ?
            "#{actions.length} action(s) available. Each action has a normalized input_schema — use those field names when calling platform_execute." :
            "No actions found. Use platform_execute(action: 'generate_action', ...) to create one from an operation."
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
              "Found #{results.length} relevant section(s). Use the platform_query tool with type='documents' and the document id to read the full document." :
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
          # Fallback: try to find as a dynamic module model
          module_result = query_dynamic_module(type, args)
          return module_result if module_result

          closest = find_closest(normalized_type, available)
          return error_response(
            "Unknown type: #{type}",
            suggestion: closest ? "Did you mean: #{closest}?" : nil,
            available_types: available.first(20)
          )
        end

        # Check if this is a dynamic module type (ScoutDataRegistry knows about it)
        config = ScoutDataRegistry.object_config(normalized_type, entity)
        if config && config[:dynamic]
          return query_dynamic_module_via_registry(normalized_type, config, args)
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

      # ═══════════════════════════════════════════════════════════════
      # DYNAMIC MODULE QUERIES
      # ═══════════════════════════════════════════════════════════════

      def query_dynamic_module(type, args)
        model_class = resolve_dynamic_model(type)
        return nil unless model_class

        execute_dynamic_query(type, model_class, args)
      end

      def query_dynamic_module_via_registry(type, config, args)
        # Get model class from the registry config
        model_class = ScoutDataRegistry.model_class(type, entity)
        return error_response("Could not load model for #{type}") unless model_class

        execute_dynamic_query(type, model_class, args)
      end

      def execute_dynamic_query(type, model_class, args)
        object_id = get_arg(args, :id)
        filters = get_arg(args, :filters, {})
        order_by = get_arg(args, :order_by, "created_at desc")
        limit = [get_arg(args, :limit, 20).to_i, 100].min
        search = get_arg(args, :search)

        scope = model_class.where(entity_id: entity.id)

        if object_id
          record = scope.find_by(id: object_id)
          return error_response("#{type.titleize} ##{object_id} not found") unless record

          return success_response(
            type: type,
            record: record.attributes.except('entity_id', 'user_id', 'created_by_id'),
            message: "#{type.titleize} ##{object_id}"
          )
        end

        # Apply filters
        if filters.present? && filters.is_a?(Hash)
          filters = process_date_filters(filters)
          valid_columns = model_class.column_names
          filters.each do |key, value|
            next unless valid_columns.include?(key.to_s)
            scope = scope.where(key.to_s => value)
          end
        end

        # Apply search across string/text columns
        if search.present?
          string_columns = model_class.columns.select { |c| [:string, :text].include?(c.type) }.map(&:name)
          if string_columns.any?
            search_conditions = string_columns.map { |col| "#{col} ILIKE :q" }.join(" OR ")
            scope = scope.where(search_conditions, q: "%#{search}%")
          end
        end

        # Apply ordering
        if order_by.present?
          parts = order_by.split(' ')
          column = parts[0]
          direction = parts[1]&.downcase == 'asc' ? :asc : :desc
          scope = scope.order(column => direction) if model_class.column_names.include?(column)
        end

        total = scope.count
        records = scope.limit(limit).map { |r| r.attributes.except('entity_id', 'user_id', 'created_by_id') }

        success_response(
          type: type,
          records: records,
          count: records.length,
          total: total,
          has_more: total > records.length,
          filters_applied: filters,
          message: "#{records.length} #{type} record(s)#{total > records.length ? " (#{total} total)" : ''}"
        )
      rescue => e
        Rails.logger.error "[V3::PlatformQuery] Dynamic module query failed: #{e.class}: #{e.message}"
        V3::AiErrorTransformer.transform(e, type: type, tool: "platform_query")
      end

      def resolve_dynamic_model(type)
        return nil unless entity

        # Strategy 1: "module_slug/ModelName" format
        if type.include?('/')
          parts = type.split('/')
          app_module = entity.app_modules.active.find_by(slug: parts[0])
          return nil unless app_module
          return Modules::DynamicModelLoader.instance.get_model(app_module, parts[1].classify)
        end

        # Strategy 2: Direct slug match
        app_module = entity.app_modules.active.find_by(slug: type) ||
                     entity.app_modules.active.find_by(slug: type.singularize)
        if app_module
          model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
          return model_class if model_class
        end

        # Strategy 3: Check sub-module slugs and model names
        entity.app_modules.active.each do |mod|
          mod.module_codes.where(code_type: 'model').each do |model_code|
            model_name = model_code.name
            if model_name.underscore == type || model_name.underscore == type.singularize ||
               model_name.underscore.pluralize == type
              return Modules::DynamicModelLoader.instance.get_model(mod, model_name)
            end
            table = model_code.schema_definition&.dig('table_name')
            if table == type.pluralize || table == type
              return Modules::DynamicModelLoader.instance.get_model(mod, model_name)
            end
          end
        end

        nil
      end

      # ═══════════════════════════════════════════════════════════════
      # CANVAS QUERIES
      # ═══════════════════════════════════════════════════════════════

      def query_canvases(args)
        id = get_arg(args, :id)
        search = get_arg(args, :search)

        if id.present?
          canvas = find_canvas_for_query(id)
          return error_response("Canvas '#{id}' not found") unless canvas

          versions = canvas.version_summary
          return success_response(
            canvas: canvas_detail(canvas),
            version_count: versions.length + 1,
            versions: versions.map { |v| { version: v[:version], saved_at: v[:saved_at] } },
            message: "Canvas '#{canvas.name}' — v#{canvas.version}, #{canvas.locked? ? 'LOCKED' : 'unlocked'}, #{canvas.html_content.to_s.length + canvas.js_content.to_s.length + canvas.css_content.to_s.length} bytes total"
          )
        end

        scope = ModuleCanvas.joins(:app_module)
                            .where(entity_id: entity.id)
                            .includes(:app_module)

        if search.present?
          scope = scope.where(
            "LOWER(module_canvases.name) LIKE :q OR LOWER(module_canvases.slug) LIKE :q OR LOWER(app_modules.name) LIKE :q",
            q: "%#{search.downcase}%"
          )
        end

        canvases = scope.order(:name).limit(get_arg(args, :limit, 30).to_i)

        success_response(
          canvases: canvases.map { |c| canvas_summary(c) },
          count: canvases.length,
          locked_count: canvases.count(&:locked?),
          message: "#{canvases.length} canvas(es) found#{search ? " matching '#{search}'" : ''}. #{canvases.count(&:locked?)} locked."
        )
      end

      def query_canvas_versions(args)
        id = get_arg(args, :id)
        return error_response("Canvas ID required") if id.blank?

        canvas = find_canvas_for_query(id)
        return error_response("Canvas '#{id}' not found") unless canvas

        versions = canvas.parsed_previous_versions
        current = {
          'version' => canvas.version,
          'saved_at' => canvas.updated_at.iso8601,
          'html_size' => canvas.html_content.to_s.length,
          'js_size' => canvas.js_content.to_s.length,
          'css_size' => canvas.css_content.to_s.length,
          'current' => true
        }

        all_versions = versions.map do |v|
          {
            version: v['version'],
            saved_at: v['saved_at'],
            html_size: v['html_content'].to_s.length,
            js_size: v['js_content'].to_s.length,
            css_size: v['css_content'].to_s.length
          }
        end
        all_versions << {
          version: current['version'],
          saved_at: current['saved_at'],
          html_size: current['html_size'],
          js_size: current['js_size'],
          css_size: current['css_size'],
          current: true
        }

        success_response(
          canvas_id: canvas.id,
          canvas_name: canvas.name,
          is_locked: canvas.locked?,
          current_version: canvas.version,
          total_versions: all_versions.length,
          versions: all_versions,
          message: "Canvas '#{canvas.name}' has #{all_versions.length} version(s). Current: v#{canvas.version}. Use platform_update(type: 'canvas', id: #{canvas.id}, data: { restore_version: N }) to restore."
        )
      end

      def find_canvas_for_query(id)
        if id.to_s =~ /\A\d+\z/
          canvas = ModuleCanvas.where(entity_id: entity.id).find_by(id: id)
          return canvas if canvas
        end

        app_mod = entity.app_modules.find_by(slug: id.to_s) ||
                  entity.app_modules.find_by(slug: id.to_s.singularize)
        if app_mod
          return app_mod.module_canvases.find_by(is_default: true) ||
                 app_mod.module_canvases.first
        end

        ModuleCanvas.joins(:app_module)
                    .where(app_modules: { entity_id: entity.id })
                    .find_by(slug: id.to_s)
      end

      def canvas_detail(canvas)
        {
          id: canvas.id,
          name: canvas.name,
          slug: canvas.slug,
          canvas_type: canvas.canvas_type,
          module_name: canvas.app_module.name,
          module_slug: canvas.app_module.slug,
          version: canvas.version,
          is_locked: canvas.locked?,
          locked_at: canvas.locked_at&.iso8601,
          lock_reason: canvas.lock_reason,
          locked_by: canvas.locked_by&.first_name,
          updated_at: canvas.updated_at.iso8601,
          created_at: canvas.created_at.iso8601,
          html_size: canvas.html_content.to_s.length,
          js_size: canvas.js_content.to_s.length,
          css_size: canvas.css_content.to_s.length,
          html_preview: canvas.html_content.to_s[0..300]
        }
      end

      def canvas_summary(c)
        {
          id: c.id,
          name: c.name,
          slug: c.slug,
          canvas_type: c.canvas_type,
          module_name: c.app_module.name,
          module_slug: c.app_module.slug,
          version: c.version,
          is_locked: c.locked?,
          lock_reason: c.lock_reason,
          updated_at: c.updated_at.iso8601
        }
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
