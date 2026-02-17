class ScoutDataRegistry
  # Registry of all data objects that Scout can interact with
  AVAILABLE_OBJECTS = {
    "campaigns" => {
      model: "Campaign",
      description: "Email marketing campaigns with performance metrics",
      queryable_fields: [
        "id", "name", "subject", "status", "created_at", "sent_at", "scheduled_at",
        "description", "from_email", "from_name"
      ],
      filterable_fields: [
        "status", "created_at", "sent_at", "scheduled_at"
      ],
      metrics: [
        "total_sent", "total_delivered", "total_opened", "total_clicked",
        "total_unsubscribed", "open_rate", "click_rate", "unsubscribe_rate"
      ],
      relationships: [
        "email_deliveries", "contact_groups", "email_template", "entity", "user"
      ],
      scoped_by: "entity_id",
      creatable: true,
      creation_schema: {
        required: [ "name", "email_template_id" ],
        optional: [ "subject", "scheduled_at", "description", "from_email", "from_name", "contact_group_ids" ],
        defaults: {
          status: "draft",
          from_email: -> { entity.default_from_email },
          from_name: -> { entity.name }
        }
      }
    },

    "landing_pages" => {
      model: "LandingPage",
      description: "Landing pages with conversion and engagement metrics",
      queryable_fields: [
        "id", "title", "slug", "status", "created_at", "updated_at", "description"
      ],
      filterable_fields: [
        "status", "created_at", "updated_at"
      ],
      metrics: [
        "total_views", "unique_views", "conversion_count", "conversion_rate",
        "bounce_rate", "avg_time_on_page"
      ],
      relationships: [
        "landing_page_versions", "campaigns", "entity", "user"
      ],
      scoped_by: "entity_id",
      creatable: true,
      creation_schema: {
        required: [ "title", "description" ],
        optional: [ "slug", "campaign_id", "template_type", "status" ],
        defaults: {
          status: "draft"
        }
      }
    },

    "contacts" => {
      model: "Contact",
      description: "Contact list with engagement history and metrics",
      queryable_fields: [
        "id", "email", "first_name", "last_name", "lifecycle_stage", "status",
        "lead_score", "lead_source", "phone", "company",
        "created_at", "updated_at", "opted_out", "opted_out_at", "last_engagement_at"
      ],
      filterable_fields: [
        "id", "email", "first_name", "last_name", "created_at", "updated_at",
        "opted_out", "last_engagement_at", "lifecycle_stage", "status"
      ],
      metrics: [
        "total_campaigns_received", "total_opens", "total_clicks", "engagement_score",
        "last_open_date", "last_click_date"
      ],
      relationships: [
        "contact_groups", "email_deliveries", "entity"
      ],
      scoped_by: "entity_id",
      creatable: true,
      creation_schema: {
        required: [ "email", "first_name", "last_name" ],
        optional: [ "lifecycle_stage", "status", "phone", "company", "lead_source", "lead_score", "contact_group_ids", "custom_fields", "tags" ],
        defaults: {
          lifecycle_stage: "lead",
          status: "active",
          opted_out: false
        },
        notes: "lifecycle_stage values: subscriber, lead, mql, sql, opportunity, customer, evangelist, other. status values: active, inactive, unsubscribed, bounced. tags are stored as custom_fields automatically."
      }
    },

    "contact_groups" => {
      model: "ContactGroup",
      description: "Contact segments and groups with performance metrics",
      queryable_fields: [
        "id", "name", "description", "created_at", "updated_at"
      ],
      filterable_fields: [
        "created_at", "updated_at"
      ],
      metrics: [
        "contact_count", "avg_engagement_rate", "total_campaigns_sent"
      ],
      relationships: [
        "contacts", "campaigns", "entity", "user"
      ],
      scoped_by: "entity_id",
      creatable: true,
      creation_schema: {
        required: [ "name" ],
        optional: [ "description", "contact_ids" ],
        defaults: {}
      }
    },

    "email_templates" => {
      model: "EmailTemplate",
      description: "Email templates used in campaigns",
      queryable_fields: [
        "id", "name", "subject", "created_at", "updated_at"
      ],
      filterable_fields: [
        "created_at", "updated_at"
      ],
      metrics: [
        "usage_count", "avg_open_rate", "avg_click_rate"
      ],
      relationships: [
        "campaigns", "entity", "user"
      ],
      scoped_by: "entity_id",
      creatable: true,
      creation_schema: {
        required: [ "name", "subject", "body" ],
        optional: [ "description" ],
        defaults: {}
      }
    },

    "email_deliveries" => {
      model: "EmailDelivery",
      description: "Individual email delivery records with engagement tracking",
      queryable_fields: [
        "id", "sent_at", "opened_at", "clicked_at", "unsubscribed_at", "bounced_at"
      ],
      filterable_fields: [
        "sent_at", "opened_at", "clicked_at", "unsubscribed_at", "bounced_at"
      ],
      metrics: [
        "delivery_status", "engagement_level"
      ],
      relationships: [
        "campaign", "contact"
      ],
      scoped_by: "campaign.entity_id",
      creatable: false  # These are created automatically by campaigns
    },

    "websites" => {
      model: "Website",
      description: "Multi-page websites with shared layout, navigation, and theme",
      queryable_fields: [
        "id", "name", "slug", "status", "theme", "subdomain",
        "created_at", "updated_at"
      ],
      filterable_fields: [
        "status", "slug", "name", "created_at", "updated_at"
      ],
      metrics: [],
      relationships: [
        "website_pages", "entity", "created_by", "custom_domain"
      ],
      scoped_by: "entity_id",
      creatable: false
    },

    "website_pages" => {
      model: "WebsitePage",
      description: "Individual pages within a multi-page website",
      queryable_fields: [
        "id", "name", "slug", "template", "status", "is_homepage",
        "website_id", "created_at", "updated_at"
      ],
      filterable_fields: [
        "website_id", "status", "slug", "is_homepage", "template", "created_at"
      ],
      metrics: [],
      relationships: [
        "website", "entity"
      ],
      scoped_by: "entity_id",
      creatable: false
    },

    'email_sequences' => {
      model: 'EmailSequence',
      description: 'Automated email sequences (drip campaigns) with time-based delays',
      queryable_fields: [
        'id', 'name', 'goal', 'status', 'created_at', 'updated_at',
        'enrolled_count', 'completed_count', 'active_count'
      ],
      filterable_fields: [
        'status', 'created_at', 'updated_at'
      ],
      metrics: [
        'enrolled_count', 'active_count', 'completed_count', 'step_count',
        'total_sent', 'total_opened', 'total_clicked', 'open_rate', 'click_rate', 'completion_rate'
      ],
      relationships: [
        'entity', 'contact_group', 'sequence_steps', 'sequence_enrollments', 'contacts'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['name', 'contact_group_id'],
        optional: ['goal', 'status'],
        defaults: {
          status: 'draft',
          enrolled_count: 0,
          completed_count: 0,
          active_count: 0
        }
      }
    },

    'sequence_steps' => {
      model: 'SequenceStep',
      description: 'Individual email steps within an email sequence',
      queryable_fields: [
        'id', 'step_number', 'delay_hours', 'subject', 'created_at', 'updated_at',
        'sent_count', 'opened_count', 'clicked_count'
      ],
      filterable_fields: [
        'email_sequence_id', 'step_number', 'delay_hours'
      ],
      metrics: [
        'sent_count', 'opened_count', 'clicked_count', 'open_rate', 'click_rate', 'delay_in_days'
      ],
      relationships: [
        'email_sequence', 'email_template'
      ],
      scoped_by: 'email_sequence.entity_id',
      creatable: true,
      creation_schema: {
        required: ['email_sequence_id', 'step_number', 'delay_hours'],
        optional: ['email_template_id', 'subject', 'body'],
        defaults: {
          delay_hours: 0,
          sent_count: 0,
          opened_count: 0,
          clicked_count: 0
        }
      }
    },

    'sequence_enrollments' => {
      model: 'SequenceEnrollment',
      description: 'Contact enrollment records tracking progress through email sequences',
      queryable_fields: [
        'id', 'status', 'current_step_number', 'created_at', 'updated_at',
        'next_send_at', 'started_at', 'completed_at', 'last_email_sent_at'
      ],
      filterable_fields: [
        'email_sequence_id', 'contact_id', 'status', 'next_send_at'
      ],
      metrics: [
        'progress_percentage', 'days_in_sequence'
      ],
      relationships: [
        'email_sequence', 'contact', 'entity'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['email_sequence_id', 'contact_id', 'entity_id'],
        optional: ['status', 'next_send_at'],
        defaults: {
          status: 'pending',
          current_step_number: 0
        }
      }
    },

    'opportunities' => {
      model: 'Opportunity',
      description: 'Sales opportunities/deals in the pipeline with stage tracking and revenue forecasting',
      queryable_fields: [
        'id', 'name', 'stage', 'value', 'probability', 'expected_close_date',
        'created_at', 'updated_at', 'closed_at', 'contact_id', 'user_id'
      ],
      filterable_fields: [
        'stage', 'created_at', 'updated_at', 'expected_close_date', 'contact_id', 'user_id'
      ],
      metrics: [
        'weighted_value', 'days_in_stage', 'total_activities', 'pipeline_value'
      ],
      relationships: [
        'contact', 'entity', 'user', 'assigned_agent', 'activities'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['name', 'contact_id'],
        optional: ['stage', 'value', 'probability', 'expected_close_date', 'user_id', 'notes'],
        defaults: {
          stage: 'lead',
          probability: 10,
          value: 0
        }
      }
    },

    'activities' => {
      model: 'Activity',
      description: 'CRM activities including tasks, calls, emails, meetings, and notes linked to contacts and opportunities',
      queryable_fields: [
        'id', 'activity_type', 'subject', 'description', 'status', 'priority',
        'due_at', 'completed_at', 'created_at', 'updated_at', 'contact_id', 'opportunity_id'
      ],
      filterable_fields: [
        'activity_type', 'status', 'priority', 'due_at', 'contact_id', 'opportunity_id', 'user_id'
      ],
      metrics: [
        'completion_rate', 'overdue_count', 'avg_completion_time'
      ],
      relationships: [
        'contact', 'opportunity', 'entity', 'user', 'assigned_agent'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['activity_type', 'subject'],
        optional: ['description', 'status', 'priority', 'due_at', 'contact_id', 'opportunity_id', 'user_id'],
        defaults: {
          status: 'pending',
          priority: 'medium',
          activity_type: 'task'
        }
      }
    }
  }.freeze

  class << self
    # Get list of available object types (including dynamic modules for an entity)
    def available_object_types(entity = nil)
      types = AVAILABLE_OBJECTS.keys.dup
      
      # Add dynamic module types if entity provided
      if entity
        entity.app_modules.active.each do |mod|
          # Add module slug for backwards compatibility
          types << mod.slug
          
          # Add each model as "module_slug/model_name" format
          mod.module_codes.models.validated_or_deployed.each do |model_code|
            types << "#{mod.slug}/#{model_code.name}"
            # Also add lowercase version for convenience
            types << "#{mod.slug}/#{model_code.name.underscore}"
          end
        end
      end
      
      types.uniq
    end

    # Get configuration for a specific object type
    def object_config(object_type, entity = nil)
      # Check static registry first
      static_config = AVAILABLE_OBJECTS[object_type.to_s]
      return static_config if static_config
      
      # Check for dynamic module
      return nil unless entity
      
      # Parse "module_slug/model_name" format
      parts = object_type.to_s.split('/')
      module_slug = parts[0]
      model_name = parts[1]
      
      # Try exact match first, then singular form
      app_module = entity.app_modules.active.find_by(slug: module_slug)
      app_module ||= entity.app_modules.active.find_by(slug: module_slug.singularize)
      return nil unless app_module
      
      # Build dynamic config from module schema
      build_module_config(app_module, model_name)
    end

    # Check if an object type is queryable
    def queryable?(object_type, entity = nil)
      return true if AVAILABLE_OBJECTS.key?(object_type.to_s)
      return false unless entity
      
      # Check for module
      slug = object_type.to_s.singularize
      entity.app_modules.active.exists?(slug: slug)
    end

    # Check if an object type is creatable
    def creatable?(object_type, entity = nil)
      config = object_config(object_type, entity)
      config && config[:creatable]
    end

    # Get model class for an object type
    def model_class(object_type, entity = nil)
      config = object_config(object_type, entity)
      return nil unless config

      if config[:dynamic]
        # Get the dynamically loaded model
        slug = object_type.to_s.singularize
        app_module = entity.app_modules.active.find_by(slug: slug)
        return nil unless app_module
        
        Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
      else
        config[:model].constantize
      end
    rescue NameError
      nil
    end
    
    # Build configuration for a dynamic module
    def build_module_config(app_module, model_name = nil)
      # Find the specific model if provided
      if model_name.present?
        model_code = app_module.module_codes.models.find_by(name: model_name)
        model_code ||= app_module.module_codes.models.find_by(name: model_name.classify)
        model_code ||= app_module.module_codes.models.find_by(name: model_name.underscore.classify)
      else
        model_code = app_module.module_codes.models.first
      end
      
      # Get schema from model_code if available, fallback to module metadata
      if model_code&.schema_definition.present?
        schema = model_code.schema_definition.deep_symbolize_keys
        fields = schema[:fields] || []
        model_class_name = model_code.name
      else
        schema = app_module.metadata&.dig('schema') || {}
        fields = schema['fields'] || schema[:fields] || []
        model_class_name = app_module.slug.classify
      end
      
      field_names = fields.map { |f| (f[:name] || f['name']).to_s }
      
      {
        model: model_class_name,
        model_code_id: model_code&.id,
        description: "#{app_module.name}: #{model_code&.name || 'data'}",
        queryable_fields: ['id', 'created_at', 'updated_at'] + field_names,
        filterable_fields: ['created_at', 'updated_at'] + field_names.select { |f| 
          field = fields.find { |fd| (fd[:name] || fd['name']).to_s == f }
          field_type = field&.dig(:type) || field&.dig('type') || field&.dig(:field_type) || field&.dig('field_type')
          %w[string date datetime boolean].include?(field_type.to_s)
        },
        metrics: [],
        relationships: ['entity'],
        scoped_by: 'entity_id',
        creatable: true,
        dynamic: true,
        app_module_id: app_module.id,
        module_slug: app_module.slug,
        creation_schema: {
          required: fields.select { |f| f[:null] == false || f['null'] == false || f[:required] || f['required'] }.map { |f| (f[:name] || f['name']).to_s },
          optional: fields.reject { |f| f[:null] == false || f['null'] == false || f[:required] || f['required'] }.map { |f| (f[:name] || f['name']).to_s },
          defaults: {}
        }
      }
    end

    # Get queryable fields for an object type
    def queryable_fields(object_type)
      config = object_config(object_type)
      config ? config[:queryable_fields] : []
    end

    # Get filterable fields for an object type
    def filterable_fields(object_type)
      config = object_config(object_type)
      config ? config[:filterable_fields] : []
    end

    # Get available metrics for an object type
    def metrics(object_type)
      config = object_config(object_type)
      config ? config[:metrics] : []
    end

    # Get available relationships for an object type
    def relationships(object_type)
      config = object_config(object_type)
      config ? config[:relationships] : []
    end

    # Get creation schema for an object type
    def creation_schema(object_type)
      config = object_config(object_type)
      config && config[:creatable] ? config[:creation_schema] : nil
    end

    # Format object registry for Claude AI function calling
    def for_claude_function_calling
      objects_description = AVAILABLE_OBJECTS.map do |type, config|
        "#{type}: #{config[:description]} (queryable fields: #{config[:queryable_fields].join(', ')})"
      end.join('\n')

      {
        available_objects: objects_description,
        object_types: AVAILABLE_OBJECTS.keys
      }
    end

    # Validate filters against object schema
    def validate_filters(object_type, filters)
      return {} unless filters.is_a?(Hash)

      allowed_fields = filterable_fields(object_type) + queryable_fields(object_type)

      filters.select do |field, _value|
        allowed_fields.include?(field.to_s)
      end
    end

    # Get scope field for entity filtering
    def scope_field(object_type)
      config = object_config(object_type)
      config ? config[:scoped_by] : nil
    end

    # Dynamic schema discovery methods
    def get_actual_schema(object_type)
      return nil unless queryable?(object_type)

      config = AVAILABLE_OBJECTS[object_type]
      model_class = config[:model].constantize

      {
        object_type: object_type,
        model: config[:model],
        description: config[:description],
        actual_columns: model_class.column_names,
        available_fields: get_available_fields(model_class),
        relationships: get_actual_relationships(model_class),
        sample_data_exists: model_class.exists?,
        record_count: model_class.count,
        scoped_by: config[:scoped_by],
        creatable: config[:creatable]
      }
    end

    def get_available_fields(model_class)
      # Get actual columns that exist in the database
      columns = model_class.column_names

      # Filter out system columns that aren't useful for queries
      excluded_columns = %w[id created_at updated_at encrypted_password reset_password_token
                           reset_password_sent_at remember_created_at confirmation_token
                           confirmed_at confirmation_sent_at unconfirmed_email]

      useful_columns = columns - excluded_columns

      # Add created_at and updated_at back if they exist (these are useful for filtering)
      useful_columns += (columns & %w[created_at updated_at])

      useful_columns.sort
    end

    def get_actual_relationships(model_class)
      # Get actual ActiveRecord associations
      associations = model_class.reflections.keys

      # Filter to common relationship types
      associations.select do |assoc|
        reflection = model_class.reflections[assoc]
        %w[belongs_to has_many has_one].include?(reflection.macro.to_s)
      end.sort
    end

    def validate_field_exists(object_type, field)
      return false unless queryable?(object_type)

      config = AVAILABLE_OBJECTS[object_type]
      model_class = config[:model].constantize

      model_class.column_names.include?(field.to_s)
    end

    def get_safe_order_field(object_type)
      return "id" unless queryable?(object_type)

      config = AVAILABLE_OBJECTS[object_type]
      model_class = config[:model].constantize
      columns = model_class.column_names

      # Preferred order: created_at, updated_at, id
      preferred_fields = %w[created_at updated_at id]

      preferred_fields.each do |field|
        return field if columns.include?(field)
      end

      # Fallback to first column if none of the preferred exist
      columns.first || "id"
    end

    def discover_all_schemas
      schemas = {}

      AVAILABLE_OBJECTS.each do |object_type, config|
        begin
          schemas[object_type] = get_actual_schema(object_type)
        rescue => e
          Rails.logger.error "Failed to discover schema for #{object_type}: #{e.message}"
          schemas[object_type] = { error: e.message }
        end
      end

      schemas
    end
  end
end
