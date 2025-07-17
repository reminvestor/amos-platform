class ScoutDataRegistry
  # Registry of all data objects that Scout can interact with
  AVAILABLE_OBJECTS = {
    'campaigns' => {
      model: 'Campaign',
      description: 'Email marketing campaigns with performance metrics',
      queryable_fields: [
        'id', 'name', 'subject', 'status', 'created_at', 'sent_at', 'scheduled_at', 
        'description', 'from_email', 'from_name'
      ],
      filterable_fields: [
        'status', 'created_at', 'sent_at', 'scheduled_at'
      ],
      metrics: [
        'total_sent', 'total_delivered', 'total_opened', 'total_clicked', 
        'total_unsubscribed', 'open_rate', 'click_rate', 'unsubscribe_rate'
      ],
      relationships: [
        'email_deliveries', 'contact_groups', 'email_template', 'entity', 'user'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['name', 'email_template_id'],
        optional: ['subject', 'scheduled_at', 'description', 'from_email', 'from_name', 'contact_group_ids'],
        defaults: {
          status: 'draft',
          from_email: -> { entity.default_from_email },
          from_name: -> { entity.name }
        }
      }
    },
    
    'landing_pages' => {
      model: 'LandingPage',
      description: 'Landing pages with conversion and engagement metrics',
      queryable_fields: [
        'id', 'title', 'slug', 'status', 'created_at', 'updated_at', 'description'
      ],
      filterable_fields: [
        'status', 'created_at', 'updated_at'
      ],
      metrics: [
        'total_views', 'unique_views', 'conversion_count', 'conversion_rate', 
        'bounce_rate', 'avg_time_on_page'
      ],
      relationships: [
        'landing_page_versions', 'campaigns', 'entity', 'user'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['title', 'description'],
        optional: ['slug', 'campaign_id', 'template_type', 'status'],
        defaults: {
          status: 'draft'
        }
      }
    },
    
    'contacts' => {
      model: 'Contact',
      description: 'Contact list with engagement history and metrics',
      queryable_fields: [
        'id', 'email', 'first_name', 'last_name', 'created_at', 'updated_at',
        'opted_out', 'opted_out_at', 'last_engagement_at'
      ],
      filterable_fields: [
        'created_at', 'updated_at', 'opted_out', 'last_engagement_at'
      ],
      metrics: [
        'total_campaigns_received', 'total_opens', 'total_clicks', 'engagement_score',
        'last_open_date', 'last_click_date'
      ],
      relationships: [
        'contact_groups', 'email_deliveries', 'entity'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['email'],
        optional: ['first_name', 'last_name', 'contact_group_ids'],
        defaults: {
          opted_out: false
        }
      }
    },
    
    'contact_groups' => {
      model: 'ContactGroup',
      description: 'Contact segments and groups with performance metrics',
      queryable_fields: [
        'id', 'name', 'description', 'created_at', 'updated_at'
      ],
      filterable_fields: [
        'created_at', 'updated_at'
      ],
      metrics: [
        'contact_count', 'avg_engagement_rate', 'total_campaigns_sent'
      ],
      relationships: [
        'contacts', 'campaigns', 'entity', 'user'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['name'],
        optional: ['description', 'contact_ids'],
        defaults: {}
      }
    },
    
    'email_templates' => {
      model: 'EmailTemplate',
      description: 'Email templates used in campaigns',
      queryable_fields: [
        'id', 'name', 'subject', 'created_at', 'updated_at'
      ],
      filterable_fields: [
        'created_at', 'updated_at'
      ],
      metrics: [
        'usage_count', 'avg_open_rate', 'avg_click_rate'
      ],
      relationships: [
        'campaigns', 'entity', 'user'
      ],
      scoped_by: 'entity_id',
      creatable: true,
      creation_schema: {
        required: ['name', 'subject', 'body'],
        optional: ['description'],
        defaults: {}
      }
    },
    
    'email_deliveries' => {
      model: 'EmailDelivery',
      description: 'Individual email delivery records with engagement tracking',
      queryable_fields: [
        'id', 'sent_at', 'opened_at', 'clicked_at', 'unsubscribed_at', 'bounced_at'
      ],
      filterable_fields: [
        'sent_at', 'opened_at', 'clicked_at', 'unsubscribed_at', 'bounced_at'
      ],
      metrics: [
        'delivery_status', 'engagement_level'
      ],
      relationships: [
        'campaign', 'contact'
      ],
      scoped_by: 'campaign.entity_id',
      creatable: false  # These are created automatically by campaigns
    }
  }.freeze
  
  class << self
    # Get all available object types
    def available_objects
      AVAILABLE_OBJECTS.keys
    end
    
    # Get configuration for a specific object type
    def object_config(object_type)
      AVAILABLE_OBJECTS[object_type.to_s]
    end
    
    # Check if an object type is queryable
    def queryable?(object_type)
      AVAILABLE_OBJECTS.key?(object_type.to_s)
    end
    
    # Check if an object type is creatable
    def creatable?(object_type)
      config = object_config(object_type)
      config && config[:creatable]
    end
    
    # Get model class for an object type
    def model_class(object_type)
      config = object_config(object_type)
      return nil unless config
      
      config[:model].constantize
    rescue NameError
      nil
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
        object_types: available_objects
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
  end
end 