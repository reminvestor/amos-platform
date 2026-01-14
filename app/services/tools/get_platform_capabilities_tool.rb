# frozen_string_literal: true

module Tools
  # GetPlatformCapabilitiesTool - Provides Amos with knowledge about the platform's capabilities
  #
  # SINGLE SOURCE OF TRUTH: Reads directly from PLATFORM_CAPABILITIES.md
  # This means updates to the doc are immediately available to Amos - no redeployment needed.
  #
  # For complex semantic searches, uses RAG (requires rake rag:load_platform_capabilities).
  #
  class GetPlatformCapabilitiesTool < BaseTool
    # Map topic names to section headers in PLATFORM_CAPABILITIES.md
    TOPIC_TO_SECTION = {
      "architecture" => "🏗️ Platform Architecture Overview",
      "agents" => "🤖 Agent Types",
      "models" => "🧬 AI Model Strategy",
      "available_models" => "🧬 AI Model Strategy",
      "memory" => "🧠 Learning & Memory System",
      "modules" => "📦 Module System (Platform Factory)",
      "module_architecture" => "📦 Module System (Platform Factory)",
      "module_creation" => "📦 Module System (Platform Factory)",
      "integrations" => "🔌 Integration System (iPaaS)",
      "tools" => "🔧 Tool System",
      "tool_system" => "🔧 Tool System",
      "core_objects" => "📄 Core Data Objects",
      "automation" => "📅 Automation System",
      "workflows" => "📅 Automation System",
      "hub" => "🤝 Hub Collaboration System",
      "hub_system" => "🤝 Hub Collaboration System",
      "agent_collaboration" => "🤝 Hub Collaboration System",
      "ui" => "📊 UI Components",
      "ui_components" => "📊 UI Components",
      "canvas_types" => "📊 UI Components",
      "energy" => "⚡ Energy & Reputation System",
      "school" => "🎓 Agent School (Rehabilitation)",
      "lightning" => "⚡ Agent Lightning (RL Training)",
      "spaces" => "🌐 Spaces (Context Modes)",
      "capabilities" => "✅ Current Capabilities (Shipped)",
      "roadmap" => "🚀 What's Next",
      "key_models" => "📚 Key Models Reference",
      "canvas_dm" => "🖼️ Agent Canvas in DM Mode"
    }.freeze

    def self.read_only?
      true
    end

    def self.metadata
      {
        name: "get_platform_capabilities",
        description: "Retrieves documentation about how the platform works. Reads directly from PLATFORM_CAPABILITIES.md for the latest info. Use topics like 'core_objects' (landing pages, contacts), 'integrations', 'modules', 'tools', 'agents', etc. Use 'customer_context' for this user's setup. Use deep_search for semantic search.",
        category: "platform_knowledge",
        input_schema: {
          type: "object",
          properties: {
            topic: {
              type: "string",
              enum: [
                "core_objects",
                "integrations",
                "modules",
                "tools",
                "agents",
                "models",
                "automation",
                "hub",
                "ui",
                "energy",
                "memory",
                "customer_context",
                "form_rendering",
                "field_types", 
                "reference_fields",
                "module_troubleshooting",
                "all"
              ],
              description: "Topic to look up. Use 'core_objects' for landing pages/contacts/campaigns. Use 'customer_context' for this user's setup."
            },
            deep_search: {
              type: "string",
              description: "Optional: Semantic search query across all documentation. Use for complex questions."
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
        # Return table of contents with section previews
        all_sections_overview
      when "customer_context"
        # Dynamic - queries the database
        customer_context_docs
      when "form_rendering"
        # Keep hardcoded - very technical, rarely changes
        form_rendering_docs
      when "field_types"
        # Keep hardcoded - technical reference
        field_types_docs
      when "reference_fields"
        # Keep hardcoded - technical reference
        reference_fields_docs
      when "module_troubleshooting"
        # Keep hardcoded - specific troubleshooting steps
        module_troubleshooting_docs
      else
        # Read directly from PLATFORM_CAPABILITIES.md
        section_name = TOPIC_TO_SECTION[topic]
        if section_name
          read_doc_section(section_name)
        else
          # Try to find a matching section
          find_best_section(topic)
        end
      end

      # Add deep search results if requested
      if deep_search.present?
        rag_results = search_platform_docs(deep_search)
        capabilities = capabilities.is_a?(Hash) ? 
          capabilities.merge(deep_search_results: rag_results) : 
          { topic_results: capabilities, deep_search_results: rag_results }
      end

      success_response(
        topic: topic,
        source: "PLATFORM_CAPABILITIES.md",
        capabilities: capabilities
      )
    end

    private

    # ═══════════════════════════════════════════════════════════════
    # MARKDOWN PARSING - Read sections directly from the doc
    # ═══════════════════════════════════════════════════════════════

    def platform_doc_path
      Rails.root.join('PLATFORM_CAPABILITIES.md')
    end

    def read_platform_doc
      @platform_doc ||= begin
        if File.exist?(platform_doc_path)
          File.read(platform_doc_path)
        else
          Rails.logger.warn "PLATFORM_CAPABILITIES.md not found at #{platform_doc_path}"
          nil
        end
      end
    end

    def read_doc_section(section_header)
      doc = read_platform_doc
      return { error: "Documentation file not found" } unless doc

      # Find the section by header (## 🏗️ Platform Architecture Overview)
      # The header in the doc includes the emoji
      section_pattern = /^## #{Regexp.escape(section_header)}\s*\n(.*?)(?=\n## |\z)/m
      
      match = doc.match(section_pattern)
      
      if match
        content = match[1].strip
        # Truncate if too long (keep context window manageable)
        if content.length > 8000
          content = content[0...8000] + "\n\n[... section truncated - use deep_search for specific questions ...]"
        end
        {
          section: section_header,
          content: content
        }
      else
        # Try without emoji prefix
        simple_header = section_header.gsub(/^[^\w]+/, '').strip
        section_pattern = /^## .*#{Regexp.escape(simple_header)}.*\n(.*?)(?=\n## |\z)/mi
        match = doc.match(section_pattern)
        
        if match
          {
            section: section_header,
            content: match[1].strip.truncate(8000)
          }
        else
          { error: "Section '#{section_header}' not found in documentation" }
        end
      end
    end

    def find_best_section(topic)
      doc = read_platform_doc
      return { error: "Documentation file not found" } unless doc

      # Extract all section headers
      headers = doc.scan(/^## (.+)$/).flatten
      
      # Find best match
      topic_lower = topic.downcase
      best_match = headers.find { |h| h.downcase.include?(topic_lower) }
      
      if best_match
        read_doc_section(best_match)
      else
        {
          error: "No section found matching '#{topic}'",
          available_sections: headers.map { |h| h.gsub(/^[^\w]+/, '').strip },
          suggestion: "Try one of: core_objects, integrations, modules, tools, agents, or use deep_search"
        }
      end
    end

    def all_sections_overview
      doc = read_platform_doc
      return { error: "Documentation file not found" } unless doc

      # Extract all section headers with first paragraph
      sections = {}
      doc.scan(/^## (.+)\n\n(.+?)(?=\n\n|\n#)/m) do |header, first_para|
        clean_header = header.gsub(/^[^\w]+/, '').strip
        sections[clean_header] = first_para.strip.truncate(200)
      end

      {
        overview: "PLATFORM_CAPABILITIES.md - Complete platform documentation",
        sections: sections,
        usage: "Call get_platform_capabilities(topic: 'section_name') for full details",
        topics_available: TOPIC_TO_SECTION.keys.sort
      }
    end

    # ═══════════════════════════════════════════════════════════════
    # RAG SEARCH - For semantic/deep search only
    # ═══════════════════════════════════════════════════════════════

    def search_platform_docs(query)
      Rails.logger.info "🔍 Searching platform docs for: #{query.truncate(80)}"
      
      store = RagStore.find_by(name: "Platform Capabilities (System)", store_type: 'system')
      
      unless store&.ready?
        # Fall back to simple text search in the doc
        return simple_text_search(query)
      end

      begin
        vector_store = AiAgents::VectorStore.instance
        query_embedding = vector_store.generate_embedding(query)
        
        chunks = store.rag_chunks
          .where.not(embedding: nil)
          .order(Arel.sql("embedding <=> '#{query_embedding}'"))
          .limit(5)

        if chunks.any?
          {
            source: "PLATFORM_CAPABILITIES.md (RAG)",
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
          simple_text_search(query)
        end
      rescue => e
        Rails.logger.error "Platform docs search failed: #{e.message}"
        simple_text_search(query)
      end
    end

    def simple_text_search(query)
      doc = read_platform_doc
      return { error: "Documentation file not found" } unless doc

      # Simple keyword search
      keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }
      
      results = []
      doc.split(/^## /).each do |section|
        next if section.strip.empty?
        
        lines = section.lines
        header = lines.first&.strip
        content = lines[1..].join
        
        # Score by keyword matches
        score = keywords.count { |kw| content.downcase.include?(kw) }
        
        if score > 0
          results << {
            section: header,
            score: score,
            excerpt: content.strip.truncate(500)
          }
        end
      end

      {
        source: "PLATFORM_CAPABILITIES.md (text search)",
        query: query,
        results: results.sort_by { |r| -r[:score] }.first(5)
      }
    end

    # ═══════════════════════════════════════════════════════════════
    # HARDCODED DOCS - Only for truly static technical references
    # ═══════════════════════════════════════════════════════════════

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
          string: { renders_as: "text input", use_for: "short text, names, titles" },
          text: { renders_as: "textarea", use_for: "long text, descriptions" },
          integer: { renders_as: "number input", use_for: "whole numbers" },
          decimal: { renders_as: "number input", use_for: "money, percentages" },
          boolean: { renders_as: "checkbox", use_for: "yes/no flags" },
          date: { renders_as: "date picker", use_for: "dates without time" },
          datetime: { renders_as: "datetime-local", use_for: "dates with time" },
          json: { renders_as: "textarea", use_for: "complex nested data" },
          enum: { renders_as: "select dropdown", requires: "options array" },
          select: { renders_as: "select dropdown", requires: "options array" },
          reference: { renders_as: "select from another model", requires: "reference_model" }
        },
        example: {
          name: "status",
          field_type: "enum",
          required: true,
          options: ["draft", "active", "completed"]
        }
      }
    end

    def reference_fields_docs
      {
        summary: "How to create foreign key relationships",
        definition: {
          name: "Must end with _id (e.g., landing_page_id)",
          field_type: "Must be 'reference'",
          reference_model: "Model class (e.g., 'LandingPage', 'Contact')"
        },
        example: {
          name: "landing_page_id",
          field_type: "reference",
          reference_model: "LandingPage",
          label: "Landing Page"
        },
        supported_models: ["LandingPage", "Contact", "Campaign", "User", "EmailTemplate"]
      }
    end

    def module_troubleshooting_docs
      {
        summary: "Common module issues and fixes",
        issues: {
          form_not_loading: {
            cause: "Canvas metadata missing fields",
            fix: "Use diagnose_module, then update_module to fix canvas metadata"
          },
          field_shows_as_text: {
            cause: "Missing field_type: 'reference' or reference_model",
            fix: "Update field definition with correct type"
          },
          dropdown_empty: {
            cause: "reference_model not found or no records",
            fix: "Verify reference_model is correct"
          },
          field_not_in_form: {
            cause: "Field missing from canvas.metadata['fields']",
            fix: "Use update_module with action: 'update_canvas'"
          }
        },
        diagnostic_tool: "Use diagnose_module to auto-check for issues"
      }
    end

    # ═══════════════════════════════════════════════════════════════
    # DYNAMIC CONTEXT - Queries the database
    # ═══════════════════════════════════════════════════════════════

    def customer_context_docs
      {
        summary: "This customer's current setup",
        entity: entity_context,
        existing_modules: existing_modules_context,
        integrations: integrations_context,
        recent_activity: recent_activity_context
      }
    end

    def entity_context
      return { error: "No entity context" } unless entity
      {
        name: entity.name,
        team_size: entity.entity_users.count,
        created_at: entity.created_at.strftime("%Y-%m-%d")
      }
    end

    def existing_modules_context
      return [] unless entity
      entity.app_modules.active.map do |mod|
        {
          name: mod.name,
          slug: mod.slug,
          fields: mod.metadata&.dig('schema', 'fields')&.map { |f| f['name'] } || [],
          canvases: mod.module_canvases.pluck(:canvas_type)
        }
      end
    end

    def integrations_context
      return [] unless entity
      connected = []
      connected << { name: 'Stripe', type: 'Payments' } if entity.settings&.dig('stripe_connected')
      connected << { name: 'HubSpot', type: 'CRM' } if entity.settings&.dig('hubspot_connected')
      connected << { name: 'SendGrid', type: 'Email' } if entity.settings&.dig('sendgrid_connected')
      connected << { name: 'Slack', type: 'Communication' } if entity.settings&.dig('slack_connected')
      connected
    end

    def recent_activity_context
      return {} unless entity && user
      {
        recent_modules_used: entity.app_modules.order(updated_at: :desc).limit(3).pluck(:name)
      }
    end
  end
end
