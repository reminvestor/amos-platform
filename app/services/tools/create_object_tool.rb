module Tools
  class CreateObjectTool < BaseTool
    def self.metadata
      {
        name: 'create_object',
        description: 'Create basic objects like campaigns, contacts, or groups',
        category: 'data',
        input_schema: {
          type: 'object',
          properties: {
            object_type: {
              type: 'string',
              description: "The type of object to create (e.g., 'campaigns', 'contacts', 'contact_groups')"
            },
            data: {
              type: 'object',
              description: 'The data for creating the object'
            }
          },
          required: ['object_type', 'data']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      object_type = get_arg(args, :object_type)
      data = get_arg(args, :data, {})
      
      # Validate required args
      if error = validate_required_args(args, [:object_type, :data])
        return error
      end
      
      # Validate object type
      valid_types = ['campaigns', 'contacts', 'contact_groups', 'email_templates']
      unless valid_types.include?(object_type)
        return error_response(
          "Cannot create objects of type: #{object_type}",
          valid_types: valid_types,
          note: "Use generate_ai_landing_page for landing pages"
        )
      end
      
      begin
        result = case object_type
        when 'campaigns'
          create_campaign(data)
        when 'contacts'
          create_contact(data)
        when 'contact_groups'
          create_contact_group(data)
        when 'email_templates'
          create_email_template(data)
        end
        
        success_response(
          object_type: object_type,
          id: result.id,
          created: true,
          record: serialize_record(result)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response(
          "Validation failed: #{e.message}",
          validation_errors: e.record.errors.full_messages
        )
      rescue => e
        Rails.logger.error "CreateObjectTool error: #{e.message}"
        error_response("Creation failed: #{e.message}")
      end
    end
    
    private
    
    def create_campaign(data)
      # Symbolize keys for consistent access
      data = data.symbolize_keys
      
      # Ensure required fields
      data[:status] ||= 'draft'
      
      # Remove fields that don't exist on Campaign model
      data.delete(:from_email)
      data.delete(:from_name)
      
      # Handle unresolved variables - if email_template_id contains {{, it's unresolved
      if data[:email_template_id].is_a?(String) && data[:email_template_id].include?('{{')
        Rails.logger.warn "Unresolved variable in email_template_id: #{data[:email_template_id]}"
        data[:email_template_id] = nil
      end
      
      # Convert empty string or "0" to nil for foreign keys
      if data[:email_template_id].to_s == "0" || data[:email_template_id].to_s.empty?
        data[:email_template_id] = nil
      end
      
      # Convert string IDs to integers for foreign keys
      if data[:email_template_id].is_a?(String) && data[:email_template_id].match?(/^\d+$/)
        data[:email_template_id] = data[:email_template_id].to_i
      end
      
      Rails.logger.info "📝 Creating campaign with data: #{data.inspect}"
      
      campaign = Campaign.new(data)
      campaign.user = user
      campaign.entity = entity
      campaign.save!
      
      Rails.logger.info "✅ Created campaign: #{campaign.name} (ID: #{campaign.id}), template_id: #{campaign.email_template_id}"
      campaign
    end
    
    def create_contact(data)
      # Handle status values - must be lowercase
      if data[:status].present?
        data[:status] = data[:status].downcase
      else
        data[:status] = 'active'
      end
      
      # Set lead flag default
      data[:lead] = true unless data.key?(:lead)
      
      contact = Contact.new(data)
      contact.entity = entity
      contact.user = user  # AUTO-SET user_id - fixes "User must exist" error
      contact.save!
      
      Rails.logger.info "✅ Created contact: #{contact.email} (ID: #{contact.id})"
      contact
    end
    
    def create_contact_group(data)
      group = ContactGroup.new(data)
      group.entity = entity
      group.save!
      
      Rails.logger.info "✅ Created contact group: #{group.name} (ID: #{group.id})"
      group
    end
    
    def create_email_template(data)
      template = EmailTemplate.new(data)
      template.user = user
      template.entity = entity
      template.save!
      
      Rails.logger.info "✅ Created email template: #{template.name} (ID: #{template.id})"
      template
    end
    
    def serialize_record(record)
      case record
      when Campaign
        {
          id: record.id,
          name: record.name,
          description: record.description,
          status: record.status,
          email_template_id: record.email_template_id,
          scheduled_at: record.scheduled_at,
          created_at: record.created_at
        }
      when EmailTemplate
        {
          id: record.id,
          name: record.name,
          subject: record.subject,
          body: record.body&.truncate(100),
          created_at: record.created_at
        }
      when Contact
        {
          id: record.id,
          email: record.email,
          first_name: record.first_name,
          last_name: record.last_name,
          status: record.status,
          lead: record.lead,
          created_at: record.created_at
        }
      when ContactGroup
        {
          id: record.id,
          name: record.name,
          description: record.description,
          created_at: record.created_at
        }
      else
        record.as_json
      end
    end
  end
end
