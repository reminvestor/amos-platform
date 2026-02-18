# frozen_string_literal: true

# ApplicationPlannerService creates comprehensive application plans
# based on user requirements. It uses archetype intelligence to
# suggest appropriate components (modules, integrations, workflows, etc.)
#
# Usage:
#   service = ApplicationPlannerService.new(entity: entity, user: user)
#   plan = service.create_plan(
#     name: "Knowledge Base",
#     description: "Product documentation for customers",
#     requirements: { ... }
#   )
#
class ApplicationPlannerService
  attr_reader :entity, :user
  
  def initialize(entity:, user:)
    @entity = entity
    @user = user
  end
  
  # Create a new application plan from user requirements
  def create_plan(name:, description: nil, requirements: {})
    # Detect archetype from name and description
    archetype_result = detect_archetype(name, description)
    archetype = archetype_result[:archetype]
    
    # Build the plan spec based on archetype + requirements
    plan_spec = build_plan_spec(
      name: name,
      description: description,
      archetype: archetype,
      archetype_data: archetype_result[:data],
      requirements: requirements
    )
    
    # Create the plan record
    ApplicationPlan.create!(
      entity: entity,
      created_by: user,
      name: name,
      description: description || generate_description(name, archetype),
      archetype: archetype.to_s,
      status: 'drafting',
      plan_spec: plan_spec
    )
  end
  
  # Update an existing plan with new requirements
  def refine_plan(plan, updates)
    raise ArgumentError, "Plan is not editable" unless plan.editable?
    
    # Merge updates into existing spec
    refined_spec = plan.plan_spec.deep_dup
    
    updates.each do |key, value|
      case key.to_s
      when 'add_module'
        refined_spec['modules'] ||= []
        refined_spec['modules'] << normalize_module_spec(value)
      when 'add_integration'
        refined_spec['integrations'] ||= []
        refined_spec['integrations'] << normalize_integration_spec(value)
      when 'add_workflow'
        refined_spec['workflows'] ||= []
        refined_spec['workflows'] << normalize_workflow_spec(value)
      when 'add_scheduled_task'
        refined_spec['scheduled_tasks'] ||= []
        refined_spec['scheduled_tasks'] << normalize_task_spec(value)
      when 'add_website_feature'
        refined_spec['website'] ||= { 'pages' => [], 'features' => [] }
        refined_spec['website']['features'] ||= []
        refined_spec['website']['features'] << value
      when 'add_website_page'
        refined_spec['website'] ||= { 'pages' => [], 'features' => [] }
        refined_spec['website']['pages'] ||= []
        refined_spec['website']['pages'] << normalize_page_spec(value)
      when 'update_agent'
        refined_spec['agent'] ||= {}
        refined_spec['agent'].merge!(value.deep_stringify_keys)
      when 'modules', 'integrations', 'workflows', 'scheduled_tasks', 'tools'
        refined_spec[key.to_s] = value.map(&:deep_stringify_keys)
      else
        refined_spec[key.to_s] = value
      end
    end
    
    plan.update!(plan_spec: refined_spec)
    plan
  end
  
  # Generate a complete plan from AI analysis
  def generate_from_ai_analysis(plan, ai_recommendations)
    raise ArgumentError, "Plan is not editable" unless plan.editable?
    
    plan_spec = plan.plan_spec.deep_dup
    
    # Merge AI recommendations
    if ai_recommendations[:modules].present?
      plan_spec['modules'] = ai_recommendations[:modules].map { |m| normalize_module_spec(m) }
    end
    
    if ai_recommendations[:website].present?
      plan_spec['website'] = normalize_website_spec(ai_recommendations[:website])
    end
    
    if ai_recommendations[:agent].present?
      plan_spec['agent'] = normalize_agent_spec(ai_recommendations[:agent])
    end
    
    if ai_recommendations[:tools].present?
      plan_spec['tools'] = ai_recommendations[:tools].map { |t| normalize_tool_spec(t) }
    end
    
    if ai_recommendations[:integrations].present?
      plan_spec['integrations'] = ai_recommendations[:integrations].map { |i| normalize_integration_spec(i) }
    end
    
    if ai_recommendations[:workflows].present?
      plan_spec['workflows'] = ai_recommendations[:workflows].map { |w| normalize_workflow_spec(w) }
    end
    
    if ai_recommendations[:scheduled_tasks].present?
      plan_spec['scheduled_tasks'] = ai_recommendations[:scheduled_tasks].map { |t| normalize_task_spec(t) }
    end
    
    plan.update!(plan_spec: plan_spec)
    plan
  end
  
  private
  
  # ============================================
  # ARCHETYPE DETECTION
  # ============================================
  
  def detect_archetype(name, description)
    # Use the existing archetype intelligence from Platform Factory
    Modules::ArchetypeIntelligence.detect(name: name, description: description)
  rescue => e
    Rails.logger.warn "[ApplicationPlannerService] Archetype detection failed: #{e.message}"
    { archetype: :custom, data: nil, confidence: :none }
  end
  
  def generate_description(name, archetype)
    case archetype.to_sym
    when :knowledge_base
      "A searchable knowledge base for organizing and publishing documentation, FAQs, and help articles."
    when :crm
      "Customer relationship management system for tracking contacts, deals, and interactions."
    when :sales_pipeline
      "Sales pipeline to manage leads, opportunities, and deal stages from prospect to close."
    when :inventory
      "Inventory management system for tracking products, stock levels, suppliers, and purchase orders."
    when :project, :project_mgmt
      "Project management system for tasks, milestones, time tracking, and team collaboration."
    when :social_media
      "Social media command center for scheduling, publishing, and analyzing content."
    when :events
      "Event management system for planning events, managing registrations, and tracking attendees."
    when :finance
      "Financial tracking system for invoices, expenses, budgets, and payment management."
    when :hr
      "HR and people management system for employees, time off, recruitment, and onboarding."
    when :real_estate
      "Real estate management system for properties, tenants, maintenance, and showings."
    when :helpdesk
      "Help desk and support system for tickets, SLA tracking, and customer satisfaction."
    when :education
      "Learning management system for courses, students, enrollments, assignments, and grade tracking."
    when :fleet_management
      "Fleet management system for vehicles, drivers, trips, maintenance, and fuel tracking."
    when :restaurant
      "Restaurant management system for menu items, orders, tables, reservations, and kitchen inventory."
    else
      "Custom application: #{name}"
    end
  end
  
  # ============================================
  # PLAN SPEC BUILDING
  # ============================================
  
  def build_plan_spec(name:, description:, archetype:, archetype_data:, requirements:)
    spec = {
      'modules' => [],
      'website' => nil,
      'agent' => nil,
      'tools' => [],
      'integrations' => [],
      'workflows' => [],
      'scheduled_tasks' => []
    }
    
    # Build from archetype suggestions
    if archetype != :custom && archetype_data.present?
      spec = build_from_archetype(spec, name, archetype, archetype_data)
    else
      # Build minimal custom spec
      spec = build_custom_spec(spec, name, description, requirements)
    end
    
    # Apply any explicit requirements
    spec = apply_requirements(spec, requirements)
    
    spec
  end
  
  def build_from_archetype(spec, name, archetype, archetype_data)
    slug = name.parameterize.underscore
    
    # Get core fields from archetype (uses :core_fields key in ArchetypeIntelligence)
    core_fields = archetype_data[:core_fields] || []
    
    # Get canvas views from archetype (or defaults)
    canvas_views = archetype_data[:canvas_views] || %w[list form detail dashboard]
    
    # Primary module
    spec['modules'] << {
      'name' => name,
      'slug' => slug,
      'description' => archetype_data[:description] || "#{name} data management",
      'fields' => core_fields.map { |f| normalize_field(f) },
      'views' => canvas_views,
      'is_primary' => true
    }
    
    # Sub-modules from archetype (multi-model relationships)
    if archetype_data[:sub_models].present?
      archetype_data[:sub_models].each do |sub_model|
        sub_slug = "#{slug}_#{sub_model[:slug]}"
        
        # Build relationship spec with parent reference
        relationship = build_relationship_spec(sub_model[:relationship], slug)
        
        spec['modules'] << {
          'name' => sub_model[:name],
          'slug' => sub_slug,
          'description' => sub_model[:description],
          'fields' => (sub_model[:fields] || []).map { |f| normalize_field(f) },
          'views' => sub_model[:canvas_views] || %w[list form],
          'is_primary' => false,
          'relationship' => relationship
        }
      end
    end
    
    # Agent
    spec['agent'] = {
      'name' => "#{name} Expert",
      'slug' => "#{slug}_expert",
      'description' => "AI expert for managing and querying #{name.downcase}",
      'capabilities' => default_agent_capabilities(name),
      'personality' => 'helpful, knowledgeable, proactive'
    }
    
    # Suggested integrations
    if archetype_data[:suggested_integrations].present?
      spec['integrations'] = archetype_data[:suggested_integrations].map do |i|
        normalize_integration_spec(i)
      end
    end
    
    # Suggested workflows
    if archetype_data[:suggested_workflows].present?
      spec['workflows'] = archetype_data[:suggested_workflows].map do |w|
        normalize_workflow_spec(w)
      end
    end
    
    # Suggested scheduled tasks
    if archetype_data[:suggested_scheduled_tasks].present?
      spec['scheduled_tasks'] = archetype_data[:suggested_scheduled_tasks].map do |t|
        normalize_task_spec(t)
      end
    end
    
    # Suggested hub hooks for team collaboration
    if archetype_data[:suggested_hub_hooks].present?
      spec['hub_hooks'] = archetype_data[:suggested_hub_hooks].map do |h|
        {
          'event' => h[:event],
          'action' => h[:action].to_s,
          'message' => h[:message],
          'threshold' => h[:threshold],
          'mention' => h[:mention]
        }.compact
      end
    end
    
    Rails.logger.info "[ApplicationPlannerService] Built archetype plan: #{archetype} with #{spec['modules'].count} modules " \
                      "(1 primary + #{spec['modules'].count - 1} sub-models), " \
                      "#{spec['integrations'].count} integrations, #{spec['workflows'].count} workflows"
    
    spec
  end
  
  def build_custom_spec(spec, name, description, requirements)
    # Try AI-driven schema design first
    ai_spec = design_schema_with_ai(name, description, requirements)
    if ai_spec && ai_spec['modules'].present?
      return apply_ai_designed_schema(spec, name, ai_spec)
    end

    # Fallback to minimal custom spec
    build_minimal_spec(spec, name, description)
  end

  def build_minimal_spec(spec, name, description)
    slug = name.parameterize.underscore
    
    # Minimal module with basic fields
    spec['modules'] << {
      'name' => name,
      'slug' => slug,
      'description' => description || "Custom #{name} management",
      'fields' => [
        { 'name' => 'name', 'field_type' => 'string', 'required' => true },
        { 'name' => 'description', 'field_type' => 'text', 'required' => false },
        { 'name' => 'status', 'field_type' => 'select', 'options' => %w[active inactive archived] }
      ],
      'views' => %w[list form detail]
    }
    
    # Basic agent
    spec['agent'] = {
      'name' => "#{name} Assistant",
      'slug' => "#{slug}_assistant",
      'description' => "AI assistant for #{name.downcase}",
      'capabilities' => ['create records', 'query data', 'answer questions'],
      'personality' => 'helpful, concise'
    }
    
    spec
  end

  # Use PlatformBrain (Claude) to design a data schema for a custom app type
  def design_schema_with_ai(name, description, requirements)
    prompt = build_schema_design_prompt(name, description, requirements)

    response = bedrock_client.converse(
      model_id: "global.anthropic.claude-sonnet-4-6",
      messages: [{ role: "user", content: [{ text: prompt }] }],
      inference_config: { max_tokens: 4096, temperature: 0.3 },
      system: [{ text: schema_design_system_prompt }]
    )

    raw_text = response.output.message.content
                       .select { |b| b.respond_to?(:text) && b.text }
                       .map(&:text)
                       .join("\n")

    parse_schema_design_response(raw_text)
  rescue => e
    Rails.logger.warn "[ApplicationPlannerService] AI schema design failed: #{e.message}"
    nil
  end

  def schema_design_system_prompt
    <<~PROMPT
      You are a database schema architect for a business application platform.
      Your job is to design data models (modules) for custom business applications.

      OUTPUT FORMAT: Return ONLY a single JSON code block with this exact structure:
      ```json
      {
        "modules": [
          {
            "name": "ModuleName",
            "slug": "module_name",
            "description": "What this module stores",
            "is_primary": true,
            "fields": [
              { "name": "field_name", "field_type": "string|text|select|integer|decimal|boolean|date|datetime", "required": true, "options": ["opt1", "opt2"] }
            ],
            "views": ["list", "form", "detail", "dashboard", "kanban", "calendar"]
          }
        ],
        "workflows": [
          { "name": "Workflow Name", "trigger": "status_change|record_created|field_changed", "from_status": "x", "to_status": "y", "actions": ["action_name"] }
        ],
        "suggested_integrations": [
          { "name": "integration_name", "description": "why" }
        ]
      }
      ```

      RULES:
      - Always include a primary module (is_primary: true) and 1-3 sub-modules
      - Sub-modules should have a "relationship" field: { "type": "belongs_to", "parent_model": "primary_slug", "parent_field": "parent_slug_id" }
      - Every module needs at minimum: a name/title field (string, required), a status field (select), and a description/notes field (text)
      - Use appropriate field types: dates for deadlines, decimals for money, selects for status/category
      - The primary slug should be derived from the app name (lowercase, underscored)
      - Sub-module slugs should be prefixed with the primary slug (e.g., "project_management_task")
      - Include 2-3 relevant workflows
      - Include 1-2 relevant integration suggestions
      - Keep it practical — focus on what a real business user would need
      - Views should match the data type: kanban for status-driven data, calendar for date-driven data
    PROMPT
  end

  def build_schema_design_prompt(name, description, requirements)
    req_text = if requirements.present?
      "Additional requirements: #{requirements.to_json}"
    else
      ""
    end

    <<~PROMPT
      Design a data schema for a custom business application:

      Application Name: #{name}
      Description: #{description || "A #{name.downcase} management system"}
      #{req_text}

      Create a complete schema with a primary module and relevant sub-modules, appropriate fields, workflows, and integration suggestions.
    PROMPT
  end

  def parse_schema_design_response(raw_text)
    # Extract JSON from the response
    json_match = raw_text.match(/```json\s*\n(.*?)```/m) ||
                 raw_text.match(/```\s*\n(\{.*?\})\s*```/m)

    if json_match
      JSON.parse(json_match.captures.first)
    else
      # Try parsing the whole response as JSON
      JSON.parse(raw_text)
    end
  rescue JSON::ParserError => e
    Rails.logger.warn "[ApplicationPlannerService] Failed to parse AI schema response: #{e.message}"
    nil
  end

  def apply_ai_designed_schema(spec, name, ai_spec)
    slug = name.parameterize.underscore

    # Add modules from AI design
    (ai_spec['modules'] || []).each do |mod|
      mod_spec = normalize_module_spec(mod)
      # Ensure slug is properly namespaced
      mod_spec['slug'] = "#{slug}_#{mod_spec['slug']}" unless mod_spec['slug']&.start_with?(slug)
      spec['modules'] << mod_spec
    end

    # If no modules were generated, add a minimal primary
    if spec['modules'].empty?
      return build_minimal_spec(spec, name, nil)
    end

    # Add agent
    spec['agent'] = {
      'name' => "#{name} Expert",
      'slug' => "#{slug}_expert",
      'description' => "AI expert for managing #{name.downcase}",
      'capabilities' => default_agent_capabilities(name),
      'personality' => 'helpful, knowledgeable, proactive'
    }

    # Add workflows from AI
    if ai_spec['workflows'].present?
      spec['workflows'] = ai_spec['workflows'].map { |w| normalize_workflow_spec(w) }
    end

    # Add suggested integrations from AI
    if ai_spec['suggested_integrations'].present?
      spec['integrations'] = ai_spec['suggested_integrations'].map { |i| normalize_integration_spec(i) }
    end

    Rails.logger.info "[ApplicationPlannerService] AI-designed schema for '#{name}': " \
                      "#{spec['modules'].count} modules, #{spec['workflows']&.count || 0} workflows"
    spec
  end

  def bedrock_client
    @bedrock_client ||= Aws::BedrockRuntime::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
      http_read_timeout: 120,
      http_open_timeout: 30
    )
  end
  
  def apply_requirements(spec, requirements)
    return spec if requirements.blank?
    
    # Add public website if requested
    if requirements[:public_website] || requirements[:website]
      spec['website'] = build_website_spec(spec['modules'].first, requirements[:website] || {})
    end
    
    # Add specific integrations
    if requirements[:integrations].present?
      requirements[:integrations].each do |integration|
        spec['integrations'] << normalize_integration_spec(integration)
      end
    end
    
    # Add specific workflows
    if requirements[:workflows].present?
      requirements[:workflows].each do |workflow|
        spec['workflows'] << normalize_workflow_spec(workflow)
      end
    end
    
    # Add specific scheduled tasks
    if requirements[:scheduled_tasks].present?
      requirements[:scheduled_tasks].each do |task|
        spec['scheduled_tasks'] << normalize_task_spec(task)
      end
    end
    
    # Add additional fields to primary module
    if requirements[:additional_fields].present?
      spec['modules'].first['fields'] += requirements[:additional_fields].map { |f| normalize_field(f) }
    end
    
    spec
  end
  
  def build_website_spec(module_spec, website_requirements)
    module_name = module_spec['name']
    slug = module_spec['slug']
    
    {
      'name' => "#{module_name} Portal",
      'slug' => "#{slug}_portal",
      'theme' => website_requirements[:theme] || 'modern',
      'features' => website_requirements[:features] || %w[search categories],
      'pages' => [
        {
          'name' => 'Home',
          'slug' => 'index',
          'is_homepage' => true,
          'template' => 'homepage'
        },
        {
          'name' => 'Browse',
          'slug' => 'browse',
          'template' => 'list'
        },
        {
          'name' => 'Detail',
          'slug' => 'detail',
          'template' => 'detail',
          'is_dynamic' => true
        }
      ]
    }
  end
  
  # ============================================
  # NORMALIZATION HELPERS
  # ============================================
  
  def normalize_field(field)
    field = field.deep_stringify_keys if field.is_a?(Hash)
    {
      'name' => field['name'] || field[:name],
      'field_type' => field['field_type'] || field['type'] || field[:type] || 'string',
      'required' => field['required'] || field[:required] || false,
      'description' => field['description'] || field[:description],
      'options' => field['options'] || field[:options],
      'default_value' => field['default_value'] || field['default'] || field[:default],
      'reference_model' => field['reference_model'] || field[:reference_model]
    }.compact
  end
  
  def normalize_module_spec(mod)
    mod = mod.deep_stringify_keys if mod.is_a?(Hash)
    result = {
      'name' => mod['name'],
      'slug' => mod['slug'] || mod['name']&.parameterize&.underscore,
      'description' => mod['description'],
      'fields' => (mod['fields'] || []).map { |f| normalize_field(f) },
      'views' => mod['views'] || %w[list form detail],
      'is_primary' => mod['is_primary'] || false
    }
    
    # Preserve relationship info for sub-modules
    if mod['relationship'].present?
      result['relationship'] = mod['relationship']
    end
    
    result.compact
  end
  
  def build_relationship_spec(relationship, primary_slug)
    return nil unless relationship.present?
    
    rel_type = relationship[:type].to_s
    
    case rel_type
    when 'belongs_to'
      parent_model = relationship[:parent_model]
      parent_field = relationship[:parent_field]
      
      # If parent_model is specified, use it; otherwise default to primary module
      parent_slug = if parent_model.present?
                      "#{primary_slug}_#{parent_model.to_s.underscore}"
                    else
                      primary_slug
                    end
      
      {
        'type' => 'belongs_to',
        'parent_slug' => parent_slug,
        'foreign_key' => parent_field
      }
    when 'standalone'
      { 'type' => 'standalone' }
    when 'has_many'
      {
        'type' => 'has_many',
        'child_slug' => relationship[:child_model].to_s.underscore,
        'foreign_key' => relationship[:parent_field]
      }
    else
      { 'type' => rel_type }
    end
  end
  
  def normalize_integration_spec(integration)
    integration = integration.deep_stringify_keys if integration.is_a?(Hash)
    {
      'slug' => integration['slug'] || integration['name']&.parameterize&.underscore,
      'name' => integration['name'],
      'purpose' => integration['purpose'] || 'sync',
      'is_critical' => integration['is_critical'] || false,
      'description' => integration['description']
    }.compact
  end
  
  def normalize_workflow_spec(workflow)
    workflow = workflow.deep_stringify_keys if workflow.is_a?(Hash)
    {
      'name' => workflow['name'],
      'trigger' => workflow['trigger'] || 'status_change',
      'from_status' => workflow['from_status'],
      'to_status' => workflow['to_status'],
      'field' => workflow['field'],
      'delay' => workflow['delay'],
      'actions' => workflow['actions'] || []
    }.compact
  end
  
  def normalize_task_spec(task)
    task = task.deep_stringify_keys if task.is_a?(Hash)
    {
      'name' => task['name'],
      'schedule' => task['schedule'] || 'daily',
      'time' => task['time'] || '09:00',
      'day' => task['day'],
      'action' => task['action'],
      'description' => task['description']
    }.compact
  end
  
  def normalize_tool_spec(tool)
    tool = tool.deep_stringify_keys if tool.is_a?(Hash)
    {
      'name' => tool['name'],
      'description' => tool['description'],
      'type' => tool['type'] || 'crud',
      'parameters' => tool['parameters'] || {}
    }.compact
  end
  
  def normalize_agent_spec(agent)
    agent = agent.deep_stringify_keys if agent.is_a?(Hash)
    {
      'name' => agent['name'],
      'slug' => agent['slug'] || agent['name']&.parameterize&.underscore,
      'description' => agent['description'],
      'capabilities' => agent['capabilities'] || [],
      'personality' => agent['personality'] || 'helpful, knowledgeable'
    }.compact
  end
  
  def normalize_website_spec(website)
    website = website.deep_stringify_keys if website.is_a?(Hash)
    {
      'name' => website['name'],
      'slug' => website['slug'] || website['name']&.parameterize&.underscore,
      'theme' => website['theme'] || 'modern',
      'features' => website['features'] || [],
      'pages' => (website['pages'] || []).map { |p| normalize_page_spec(p) }
    }.compact
  end
  
  def normalize_page_spec(page)
    page = page.deep_stringify_keys if page.is_a?(Hash)
    {
      'name' => page['name'],
      'slug' => page['slug'] || page['name']&.parameterize,
      'template' => page['template'] || 'content',
      'is_homepage' => page['is_homepage'] || false,
      'is_dynamic' => page['is_dynamic'] || false
    }.compact
  end
  
  def default_agent_capabilities(name)
    [
      "Create new #{name.downcase} records",
      "Search and query #{name.downcase} data",
      "Update and manage records",
      "Answer questions about #{name.downcase}",
      "Generate reports and analytics",
      "Help with data entry"
    ]
  end
end

