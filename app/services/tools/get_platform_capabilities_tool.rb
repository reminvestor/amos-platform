# frozen_string_literal: true

module Tools
  # GetPlatformCapabilitiesTool - Provides Amos with knowledge about the platform's capabilities
  #
  # This tool enables platform self-awareness by giving the AI agent access to
  # documentation about how different features work, what field types are supported,
  # how canvases are rendered, and other architectural details.
  #
  class GetPlatformCapabilitiesTool < BaseTool
    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "get_platform_capabilities",
        description: "Retrieves documentation about how the platform works internally. Use this to understand supported field types, canvas rendering, module architecture, and other technical capabilities before creating or fixing modules. Use deep_search for complex questions about agent collaboration, workflows, integrations, or the Hub system.",
        category: "platform_knowledge",
        input_schema: {
          type: "object",
          properties: {
            topic: {
              type: "string",
              enum: [
                "form_rendering",
                "field_types", 
                "canvas_types",
                "module_architecture",
                "reference_fields",
                "module_creation",
                "module_troubleshooting",
                "available_models",
                "tool_system",
                "customer_context",
                "ui_components",
                "agent_collaboration",
                "hub_system",
                "integrations",
                "workflows",
                "core_objects",
                "all"
              ],
              description: "The topic to get information about. Use 'customer_context' to understand this user's setup. Use 'core_objects' for landing pages, contacts, campaigns schemas. Use 'all' for a complete overview."
            },
            deep_search: {
              type: "string",
              description: "Optional: A specific question to search in the comprehensive platform documentation (PLATFORM_CAPABILITIES.md). Use for complex queries about agent systems, collaboration, learning, or advanced features."
            }
          },
          required: ["topic"]
        }
      }
    end

    def execute(args)
      log_execution(args)
      topic = get_arg(args, :topic)
      deep_search = get_arg(args, :deep_search)
      
      if error = validate_required_args(args, [:topic])
        return error
      end

      capabilities = case topic
      when "all"
        {
          form_rendering: form_rendering_docs,
          field_types: field_types_docs,
          canvas_types: canvas_types_docs,
          module_architecture: module_architecture_docs,
          reference_fields: reference_fields_docs,
          module_creation: module_creation_docs,
          module_troubleshooting: module_troubleshooting_docs,
          available_models: available_models_docs,
          tool_system: tool_system_docs,
          ui_components: ui_components_docs,
          customer_context: customer_context_docs
        }
      when "form_rendering"
        form_rendering_docs
      when "field_types"
        field_types_docs
      when "canvas_types"
        canvas_types_docs
      when "module_architecture"
        module_architecture_docs
      when "reference_fields"
        reference_fields_docs
      when "module_creation"
        module_creation_docs
      when "module_troubleshooting"
        module_troubleshooting_docs
      when "available_models"
        available_models_docs
      when "tool_system"
        tool_system_docs
      when "customer_context"
        customer_context_docs
      when "ui_components"
        ui_components_docs
      when "agent_collaboration"
        search_platform_docs("How does multi-agent collaboration work? Agent communication, ask_agent_for_help, energy economy, Hub system.")
      when "hub_system"
        search_platform_docs("What is the Collaborative Intelligence Hub? Hub threads, DM canvas, agent handoffs, BridgeService.")
      when "integrations"
        search_platform_docs("How do integrations work? Integration factory, integration agents, connected services.")
      when "workflows"
        search_platform_docs("How does the workflow engine work? WorkflowEngineV2, workflow templates, scheduled tasks.")
      when "core_objects"
        core_objects_docs
      else
        return error_response("Unknown topic: #{topic}")
      end

      # Add deep search results if requested
      if deep_search.present?
        rag_results = search_platform_docs(deep_search)
        capabilities = capabilities.is_a?(Hash) ? capabilities.merge(deep_search_results: rag_results) : { topic_results: capabilities, deep_search_results: rag_results }
      end

      success_response(
        topic: topic,
        capabilities: capabilities
      )
    end

    private

    # Search the PLATFORM_CAPABILITIES.md document via RAG
    def search_platform_docs(query)
      Rails.logger.info "🔍 Searching platform docs for: #{query.truncate(80)}"
      
      # Find the Platform Capabilities system store
      store = RagStore.find_by(name: "Platform Capabilities (System)", store_type: 'system')
      
      unless store&.ready?
        return {
          error: "Platform documentation not loaded. Run: rake rag:load_platform_capabilities",
          fallback: "The platform has comprehensive documentation covering agent architecture, collaboration, modules, integrations, and more."
        }
      end

      begin
        # Generate query embedding
        vector_store = AiAgents::VectorStore.instance
        query_embedding = vector_store.generate_embedding(query)
        
        # Search for relevant chunks using pgvector
        chunks = store.rag_chunks
          .where.not(embedding: nil)
          .order(Arel.sql("embedding <=> '#{query_embedding}'"))
          .limit(5)

        if chunks.any?
          {
            source: "PLATFORM_CAPABILITIES.md",
            query: query,
            results: chunks.map.with_index do |chunk, idx|
              {
                rank: idx + 1,
                content: chunk.content.truncate(1500),
                section: chunk.metadata['section'] || chunk.metadata['source']
              }
            end
          }
        else
          { error: "No relevant documentation found for: #{query}" }
        end
      rescue => e
        Rails.logger.error "Platform docs search failed: #{e.message}"
        { error: "Search failed: #{e.message}" }
      end
    end

    def form_rendering_docs
      {
        summary: "Forms in modules are DYNAMICALLY GENERATED by scout_controller.rb, NOT from html_content",
        key_points: [
          "Form canvases are rendered by the render_module_form_canvas method",
          "The html_content field in ModuleCanvas is NOT used for form rendering",
          "Forms are generated from the 'fields' array in canvas.metadata",
          "If a field is missing from canvas.metadata['fields'], it won't appear in the form",
          "When adding fields to a module, you MUST also update the form canvas metadata"
        ],
        how_it_works: {
          step_1: "Controller finds the ModuleCanvas for the form",
          step_2: "Reads fields from canvas.metadata['fields'] (or falls back to module schema)",
          step_3: "For each field, generates appropriate HTML input based on field_type",
          step_4: "Reference fields become <select> dropdowns populated from the referenced model",
          step_5: "Form submission sends data to Amos via chat message"
        },
        important: "To fix a form, update the metadata['fields'] array, NOT the html_content"
      }
    end

    def field_types_docs
      {
        summary: "Supported field types for module schemas and form rendering",
        supported_types: {
          string: {
            renders_as: "text input",
            use_for: "short text, names, titles, single-line values"
          },
          text: {
            renders_as: "textarea",
            use_for: "long text, descriptions, notes, multi-line content"
          },
          integer: {
            renders_as: "number input",
            use_for: "whole numbers, counts, IDs"
          },
          decimal: {
            renders_as: "number input",
            use_for: "monetary values, percentages, measurements"
          },
          boolean: {
            renders_as: "checkbox",
            use_for: "yes/no, true/false, enabled/disabled flags"
          },
          date: {
            renders_as: "date picker",
            use_for: "dates without time (birthdays, due dates)"
          },
          datetime: {
            renders_as: "datetime-local input",
            use_for: "dates with time (scheduled events, timestamps)"
          },
          json: {
            renders_as: "textarea with monospace font",
            use_for: "complex nested data, arrays, flexible structures"
          },
          enum: {
            renders_as: "select dropdown",
            use_for: "fixed set of options (status, category, type)",
            requires: "options array in field definition"
          },
          select: {
            renders_as: "select dropdown",
            use_for: "same as enum - fixed options",
            requires: "options array in field definition"
          },
          reference: {
            renders_as: "select dropdown populated from another model",
            use_for: "foreign keys, relationships to other records",
            requires: "reference_model or references in field definition"
          }
        },
        field_definition_example: {
          name: "status",
          field_type: "enum",
          label: "Status",
          required: true,
          options: ["draft", "active", "completed"],
          default_value: "draft",
          description: "Current status of the record"
        },
        reference_field_example: {
          name: "landing_page_id",
          field_type: "reference",
          reference_model: "LandingPage",
          label: "Landing Page",
          required: false,
          description: "The landing page this record is associated with"
        }
      }
    end

    def canvas_types_docs
      {
        summary: "Different canvas types available for modules",
        types: {
          list: {
            description: "Data grid/table view showing multiple records",
            renders: "Table with columns for display_fields",
            supports: "filtering, sorting, pagination, row actions"
          },
          form: {
            description: "Form for creating/editing a single record",
            renders: "Dynamically generated form inputs based on field definitions",
            supports: "all field types, validation, save/cancel actions"
          },
          detail: {
            description: "Read-only view of a single record",
            renders: "Formatted display of record data",
            supports: "edit button, related records"
          },
          calendar: {
            description: "Calendar view for date-based records",
            renders: "FullCalendar grid with events",
            requires: "date or datetime field for event positioning"
          },
          kanban: {
            description: "Kanban board for status-based workflows",
            renders: "Columns with draggable cards",
            requires: "status/enum field for column grouping"
          },
          dashboard: {
            description: "Summary view with metrics and charts",
            renders: "Cards, charts, statistics",
            supports: "aggregations, visualizations"
          }
        },
        rendering_note: "list and form canvases are dynamically rendered. Other types use html_content."
      }
    end

    def module_architecture_docs
      {
        summary: "How custom modules are structured in the platform",
        components: {
          AppModule: {
            description: "Main module record containing metadata and schema",
            key_fields: ["slug", "name", "metadata (contains schema)", "status", "icon"]
          },
          ModuleCanvas: {
            description: "UI views for the module (list, form, etc.)",
            key_fields: ["canvas_type", "slug", "metadata (contains fields, display_fields)"]
          },
          ModuleCode: {
            description: "Generated code for database table and model",
            key_fields: ["code_type (model)", "schema_definition (columns)", "status"]
          },
          ModuleAction: {
            description: "Custom buttons and actions for the module",
            key_fields: ["action_type", "behavior_config", "location", "visibility_rules"]
          }
        },
        data_flow: {
          schema: "AppModule.metadata['schema']['fields'] defines the data structure",
          form_canvas: "ModuleCanvas.metadata['fields'] drives form rendering",
          list_canvas: "ModuleCanvas.metadata['display_fields'] determines visible columns",
          database: "ModuleCode.schema_definition defines the actual database table"
        },
        critical_sync: "Schema fields, canvas fields, and database columns must stay in sync!"
      }
    end

    def reference_fields_docs
      {
        summary: "How to properly create reference (foreign key) fields",
        definition: {
          name: "Must end with _id (e.g., landing_page_id, contact_id)",
          field_type: "Must be 'reference'",
          reference_model: "Must specify the model class (e.g., 'LandingPage', 'Contact')"
        },
        example: {
          name: "landing_page_id",
          field_type: "reference",
          reference_model: "LandingPage",
          label: "Landing Page",
          required: false,
          description: "Select a landing page"
        },
        supported_reference_models: [
          "LandingPage",
          "Contact",
          "Campaign",
          "User",
          "EmailTemplate",
          "Opportunity"
        ],
        how_dropdowns_work: {
          step_1: "render_reference_field method detects reference type",
          step_2: "Looks up the model class (e.g., LandingPage)",
          step_3: "Queries records scoped to current entity",
          step_4: "Builds <select> with options using name/title/email as display",
          step_5: "Pre-selects current value if editing"
        },
        common_mistakes: [
          "Missing field_type: 'reference' - falls through to text input",
          "Missing reference_model - cannot populate dropdown",
          "Field not in canvas metadata - doesn't appear in form",
          "Field not in database - save fails"
        ]
      }
    end

    def module_creation_docs
      {
        summary: "Proper workflow for creating modules that work correctly",
        workflow: {
          step_1: {
            tool: "start_module_design",
            purpose: "Initiate design session and gather requirements"
          },
          step_2: {
            tool: "propose_module_schema", 
            purpose: "Define fields with correct types, including reference_model for references"
          },
          step_3: {
            tool: "approve_module_design",
            purpose: "Creates AppModule, ModuleCode, ModuleCanvases with synced metadata"
          }
        },
        checklist_before_approval: [
          "All fields have valid field_type",
          "Reference fields have reference_model specified",
          "Enum fields have options array",
          "Required fields are marked required: true",
          "Labels are human-readable"
        ],
        after_creation: [
          "Verify with diagnose_module tool",
          "Test the form canvas loads correctly",
          "Test reference dropdowns are populated",
          "Test creating and editing records"
        ]
      }
    end

    def module_troubleshooting_docs
      {
        summary: "Common module issues and how to fix them",
        issues: {
          form_not_loading: {
            symptoms: "Form canvas shows blank or error",
            causes: ["Canvas metadata missing fields", "JavaScript error", "Missing database table"],
            fix: "Use diagnose_module tool, then update_module to fix canvas metadata"
          },
          field_shows_as_text_input: {
            symptoms: "Reference field shows text input instead of dropdown",
            causes: ["Missing field_type: 'reference'", "Missing reference_model", "Field not in canvas metadata"],
            fix: "Update field definition with correct type and reference_model, sync to canvas"
          },
          dropdown_empty: {
            symptoms: "Select dropdown has no options",
            causes: ["reference_model not found", "No records in referenced model", "Entity scoping issue"],
            fix: "Verify reference_model is correct, check if records exist"
          },
          field_not_in_form: {
            symptoms: "Field exists in schema but not in form",
            causes: ["Field missing from canvas.metadata['fields']"],
            fix: "Use update_module with action: 'update_canvas' to add field to metadata"
          },
          save_fails: {
            symptoms: "Error when saving record",
            causes: ["Database column missing", "Validation error", "Type mismatch"],
            fix: "Check ModuleCode schema_definition matches schema fields"
          }
        },
        diagnostic_tool: "Use diagnose_module tool to automatically check for common issues"
      }
    end

    def available_models_docs
      {
        summary: "Core platform models available for reference fields",
        models: {
          LandingPage: {
            description: "Marketing landing pages",
            display_field: "name",
            common_use: "A/B testing, campaign tracking"
          },
          Contact: {
            description: "Customer/lead contacts",
            display_field: "email or name",
            common_use: "CRM, email sequences"
          },
          Campaign: {
            description: "Marketing campaigns",
            display_field: "name",
            common_use: "Attribution, reporting"
          },
          User: {
            description: "Platform users",
            display_field: "email",
            common_use: "Assigned to, created by"
          },
          EmailTemplate: {
            description: "Email templates",
            display_field: "name",
            common_use: "Email campaigns"
          },
          Opportunity: {
            description: "Sales opportunities",
            display_field: "name",
            common_use: "Sales pipeline"
          }
        },
        custom_modules: "Custom modules can also be referenced once created and deployed"
      }
    end

    def tool_system_docs
      {
        summary: "How the tool system works for module management",
        module_tools: {
          start_module_design: "Initiates interactive module design session",
          propose_module_schema: "Proposes field structure for approval",
          refine_module_schema: "Modifies schema based on feedback",
          approve_module_design: "Finalizes and builds the module",
          update_module: "Updates existing modules (add fields, fix canvases)",
          diagnose_module: "Checks module health and identifies issues",
          get_platform_capabilities: "This tool - explains how platform works"
        },
        update_module_actions: {
          add_field: "Add new field to schema AND syncs to canvases",
          remove_field: "Remove field from schema",
          update_field: "Modify field properties",
          update_canvas: "Update canvas metadata directly",
          fix_canvas_buttons: "Regenerate canvas with working buttons",
          regenerate_model: "Rebuild model from schema"
        },
        best_practices: [
          "Always use diagnose_module after making changes",
          "Use get_platform_capabilities before creating complex modules",
          "Test forms after adding reference fields",
          "Keep schema, canvas metadata, and database in sync"
        ]
      }
    end

    def core_objects_docs
      {
        summary: "Core platform objects and how to work with them",
        important_rule: "ALWAYS use get_schema(object_type: 'xxx') before modifying objects to understand their structure",
        objects: {
          landing_page: {
            description: "Marketing landing pages with HTML content",
            key_fields: {
              id: "Unique identifier",
              title: "Page title (NOT 'name')",
              slug: "URL-friendly identifier",
              status: "'draft' or 'published' (NOT a boolean 'published' field)",
              html_content: "The actual HTML content of the page",
              subdomain: "Optional subdomain for direct access",
              description: "Optional page description"
            },
            how_to_edit: {
              tool: "update_landing_page_content",
              parameters: {
                landing_page_id: "The ID of the page to edit",
                instruction: "Natural language instruction like 'Remove the privacy policy section'"
              },
              note: "This tool uses AI to intelligently modify HTML - you provide instructions, NOT raw HTML"
            },
            wrong_approach: "Do NOT use update_object with raw HTML - use update_landing_page_content instead"
          },
          contact: {
            description: "Customer and lead contacts",
            key_fields: ["id", "first_name", "last_name", "email", "phone", "status", "metadata"],
            how_to_modify: "update_object(object_type: 'contact', id: X, data: {...})"
          },
          campaign: {
            description: "Marketing campaigns",
            key_fields: ["id", "name", "subject", "status", "sent_count", "open_count", "click_count"],
            how_to_modify: "update_object(object_type: 'campaign', id: X, data: {...})"
          }
        },
        best_practice: "Before modifying ANY object, call get_schema(object_type: 'xxx') to see exact field names and types"
      }
    end

    def ui_components_docs
      {
        summary: "Advanced UI components available for module fields",
        components: {
          rich_text_editor: {
            description: "WYSIWYG editor for formatted content (Trix)",
            use_with: "field_type: 'text', ui_component: 'rich_text_editor'",
            renders: "Full editor with bold, italic, lists, links, headings",
            ideal_for: "Articles, descriptions, documentation, emails"
          },
          code_editor: {
            description: "Syntax-highlighted code editor",
            use_with: "field_type: 'text', ui_component: 'code_editor'",
            renders: "Monospace editor with syntax highlighting",
            ideal_for: "JSON, HTML, CSS, custom code"
          },
          color_picker: {
            description: "Visual color selection",
            use_with: "field_type: 'string', ui_component: 'color_picker'",
            renders: "Color swatch with picker",
            ideal_for: "Theming, branding, status colors"
          },
          image_upload: {
            description: "Direct image upload with preview",
            use_with: "field_type: 'string', ui_component: 'image_upload'",
            renders: "Drop zone with preview thumbnail",
            ideal_for: "Avatars, logos, product images"
          },
          file_upload: {
            description: "File attachment with preview",
            use_with: "field_type: 'string', ui_component: 'file_upload'",
            renders: "File picker with type indicator",
            ideal_for: "Documents, PDFs, spreadsheets"
          },
          rating: {
            description: "Star rating input",
            use_with: "field_type: 'integer', ui_component: 'rating'",
            renders: "5-star clickable rating",
            ideal_for: "Reviews, quality scores, priorities"
          },
          slider: {
            description: "Numeric slider",
            use_with: "field_type: 'integer', ui_component: 'slider', min: 0, max: 100",
            renders: "Horizontal slider with value display",
            ideal_for: "Percentages, progress, confidence scores"
          },
          tags: {
            description: "Tag input with autocomplete",
            use_with: "field_type: 'json', ui_component: 'tags'",
            renders: "Pill-style tags with add/remove",
            ideal_for: "Keywords, categories, labels"
          },
          user_select: {
            description: "User autocomplete dropdown",
            use_with: "field_type: 'reference', ui_component: 'user_select', reference_model: 'User'",
            renders: "Searchable user dropdown with avatars",
            ideal_for: "Assignment, ownership, mentions"
          },
          date_range: {
            description: "Start/end date picker",
            use_with: "field_type: 'json', ui_component: 'date_range'",
            renders: "Connected date pickers",
            ideal_for: "Projects, events, campaigns"
          },
          address: {
            description: "Structured address input",
            use_with: "field_type: 'json', ui_component: 'address'",
            renders: "Street, city, state, zip, country fields",
            ideal_for: "Contacts, locations, shipping"
          },
          money: {
            description: "Currency input",
            use_with: "field_type: 'decimal', ui_component: 'money', currency: 'USD'",
            renders: "Formatted currency input with symbol",
            ideal_for: "Prices, costs, budgets"
          }
        },
        usage_pattern: "Add ui_component to field definition to override default rendering"
      }
    end

    def customer_context_docs
      {
        summary: "This customer's current setup and installed modules",
        entity: entity_context,
        existing_modules: existing_modules_context,
        integrations: integrations_context,
        recent_activity: recent_activity_context,
        suggested_connections: suggested_connections
      }
    end

    def entity_context
      return { error: "No entity context" } unless entity

      {
        name: entity.name,
        industry: entity.metadata&.dig('industry'),
        team_size: entity.entity_users.count,
        created_at: entity.created_at.strftime("%Y-%m-%d"),
        plan: entity.billing_account&.plan_name || 'default'
      }
    end

    def existing_modules_context
      return [] unless entity

      entity.app_modules.active.map do |mod|
        record_count = begin
          mod.module_records.count
        rescue
          0
        end
        
        {
          name: mod.name,
          slug: mod.slug,
          description: mod.description,
          fields: mod.metadata&.dig('schema', 'fields')&.map { |f| f['name'] } || [],
          record_count: record_count,
          canvases: mod.module_canvases.pluck(:canvas_type)
        }
      end
    end

    def integrations_context
      return [] unless entity

      # Check for connected integrations
      connected = []
      
      if entity.settings&.dig('hubspot_connected')
        connected << { name: 'HubSpot', type: 'CRM', capabilities: ['contacts', 'companies', 'deals'] }
      end
      
      if entity.settings&.dig('stripe_connected') || entity.billing_account&.stripe_customer_id
        connected << { name: 'Stripe', type: 'Payments', capabilities: ['customers', 'subscriptions', 'invoices'] }
      end
      
      if entity.settings&.dig('sendgrid_connected')
        connected << { name: 'SendGrid', type: 'Email', capabilities: ['send_email', 'templates'] }
      end

      if entity.settings&.dig('slack_connected')
        connected << { name: 'Slack', type: 'Communication', capabilities: ['channels', 'messages', 'notifications'] }
      end

      connected
    end

    def recent_activity_context
      return {} unless entity && user

      {
        recent_modules_used: entity.app_modules.order(updated_at: :desc).limit(3).pluck(:name),
        recent_agent_tasks: user.agent_plugin_executions.where(status: 'completed').order(created_at: :desc).limit(5).map do |exec|
          exec.input_context['task']&.truncate(100) rescue nil
        end.compact
      }
    end

    def suggested_connections
      return [] unless entity

      suggestions = []
      existing_slugs = entity.app_modules.pluck(:slug)

      # Suggest based on what they have
      if existing_slugs.include?('knowledge_base') && !existing_slugs.include?('support_tickets')
        suggestions << "Support Tickets - would integrate well with your Knowledge Base"
      end

      if existing_slugs.include?('project_tracker') && !existing_slugs.include?('time_tracking')
        suggestions << "Time Tracking - track time against your projects"
      end

      if existing_slugs.include?('contacts') && !existing_slugs.include?('email_sequences')
        suggestions << "Email Sequences - automate outreach to your contacts"
      end

      suggestions
    end
  end
end



