module Tools
  class UpdateObjectTool < BaseTool
    def self.metadata
      {
        name: 'update_object',
        description: 'Update existing objects like campaigns, contacts, or groups',
        category: 'data',
        input_schema: {
          type: 'object',
          properties: {
            object_type: {
              type: 'string',
              description: "The type of object to update (e.g., 'campaign', 'contact', 'contact_group')"
            },
            id: {
              type: ['string', 'integer'],
              description: 'The ID of the object to update'
            },
            data: {
              type: 'object',
              description: 'The data to update on the object (only specified fields will be updated)'
            }
          },
          required: ['object_type', 'id', 'data']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      object_type = get_arg(args, :object_type)
      object_id = get_arg(args, :id)
      data = get_arg(args, :data, {})
      
      # Validate required args
      if error = validate_required_args(args, [:object_type, :id, :data])
        return error
      end
      
      # Normalize object type (remove 's' if present)
      object_type = object_type.to_s.singularize
      
      # Validate object type
      valid_types = ['campaign', 'contact', 'contact_group', 'landing_page', 'email_template']
      unless valid_types.include?(object_type)
        return error_response(
          "Cannot update objects of type: #{object_type}",
          valid_types: valid_types
        )
      end
      
      begin
        result = case object_type
        when 'campaign'
          update_campaign(object_id, data)
        when 'contact'
          update_contact(object_id, data)
        when 'contact_group'
          update_contact_group(object_id, data)
        when 'landing_page'
          update_landing_page(object_id, data)
        when 'email_template'
          update_email_template(object_id, data)
        end
        
        success_response(
          object: result,
          message: "Successfully updated #{object_type}"
        )
      rescue ActiveRecord::RecordNotFound => e
        error_response("#{object_type.capitalize} not found with ID: #{object_id}")
      rescue ActiveRecord::RecordInvalid => e
        error_response("Validation failed: #{e.record.errors.full_messages.join(', ')}")
      rescue => e
        error_response("Failed to update #{object_type}: #{e.message}")
      end
    end
    
    private
    
    def update_campaign(id, data)
      campaign = entity.campaigns.find(id)
      
      # Handle special fields
      if data['email_template_id'].present?
        template = entity.email_templates.find_by(id: data['email_template_id'])
        return error_response("Email template not found") unless template
        data['email_template_id'] = template.id
      end
      
      if data['contact_group_ids'].present?
        group_ids = Array(data['contact_group_ids'])
        groups = entity.contact_groups.where(id: group_ids)
        return error_response("Some contact groups not found") if groups.count != group_ids.count
        
        # Update the contact groups association
        campaign.contact_groups = groups
        data.delete('contact_group_ids') # Remove from data since we handled it
      end
      
      # Handle add_contact_group_ids separately to append groups
      if data['add_contact_group_ids'].present?
        group_ids = Array(data['add_contact_group_ids'])
        groups_to_add = entity.contact_groups.where(id: group_ids)
        return error_response("Some contact groups not found") if groups_to_add.count != group_ids.count
        
        # Add to existing groups without removing current ones
        # Make idempotent - only add groups that aren't already there
        existing_group_ids = campaign.contact_group_ids
        new_groups = groups_to_add.reject { |g| existing_group_ids.include?(g.id) }
        already_added_groups = groups_to_add.select { |g| existing_group_ids.include?(g.id) }
        
        if new_groups.any?
          campaign.contact_groups << new_groups
          Rails.logger.info "✅ Added #{new_groups.count} new contact group(s) to campaign"
          
          # Store info about what was added
          @add_group_result = {
            newly_added: new_groups.count,
            already_existed: already_added_groups.count,
            message: "Added #{new_groups.count} contact group(s). #{already_added_groups.count > 0 ? "(#{already_added_groups.count} already existed)" : ""}"
          }
        else
          Rails.logger.info "ℹ️ All requested contact groups already associated with campaign"
          
          # Still a success - the goal is achieved (groups are on campaign)
          @add_group_result = {
            newly_added: 0,
            already_existed: already_added_groups.count,
            message: "Contact group(s) already on this campaign - no changes needed"
          }
        end
        
        data.delete('add_contact_group_ids')
      end
      
      # Handle remove_contact_group_ids to remove specific groups
      if data['remove_contact_group_ids'].present?
        group_ids = Array(data['remove_contact_group_ids'])
        campaign.contact_groups.delete(campaign.contact_groups.where(id: group_ids))
        data.delete('remove_contact_group_ids')
      end
      
      campaign.update!(data) if data.any?
      format_campaign(campaign)
    end
    
    def update_contact(id, data)
      contact = entity.contacts.find(id)
      
      # Handle contact groups
      if data['contact_group_ids'].present?
        group_ids = Array(data['contact_group_ids'])
        groups = entity.contact_groups.where(id: group_ids)
        return error_response("Some contact groups not found") if groups.count != group_ids.count
        contact.contact_groups = groups
        data.delete('contact_group_ids')
      end
      
      contact.update!(data)
      format_contact(contact)
    end
    
    def update_contact_group(id, data)
      group = entity.contact_groups.find(id)
      
      # Handle contact additions/removals
      if data['add_contact_ids'].present?
        contact_ids = Array(data['add_contact_ids'])
        contacts = entity.contacts.where(id: contact_ids)
        group.contacts << contacts
        data.delete('add_contact_ids')
      end
      
      if data['remove_contact_ids'].present?
        contact_ids = Array(data['remove_contact_ids'])
        group.contacts.delete(entity.contacts.where(id: contact_ids))
        data.delete('remove_contact_ids')
      end
      
      group.update!(data)
      format_contact_group(group)
    end
    
    def update_landing_page(id, data)
      page = entity.landing_pages.find(id)
      
      # Handle special fields
      if data['is_published'].present?
        data['published_at'] = data['is_published'] ? Time.current : nil
      end
      
      page.update!(data)
      format_landing_page(page)
    end
    
    def update_email_template(id, data)
      template = entity.email_templates.find(id)
      
      # Ensure HTML content is properly formatted
      if data['html_content'].present? && !data['html_content'].include?('<html')
        data['html_content'] = wrap_in_html(data['html_content'])
      end
      
      template.update!(data)
      format_email_template(template)
    end
    
    # Formatting helpers
    def format_campaign(campaign)
      result = {
        id: campaign.id,
        name: campaign.name,
        description: campaign.description,
        status: campaign.status,
        email_template_id: campaign.email_template_id,
        contact_groups: campaign.contact_groups.pluck(:id, :name),
        contact_group_count: campaign.contact_groups.count,
        created_at: campaign.created_at,
        updated_at: campaign.updated_at
      }
      
      # Include add_group result if it was an add operation
      if @add_group_result
        result[:add_group_result] = @add_group_result
        result[:operation_message] = @add_group_result[:message]
      end
      
      result
    end
    
    def format_contact(contact)
      {
        id: contact.id,
        email: contact.email,
        first_name: contact.first_name,
        last_name: contact.last_name,
        status: contact.status,
        contact_groups: contact.contact_groups.pluck(:id, :name),
        created_at: contact.created_at,
        updated_at: contact.updated_at
      }
    end
    
    def format_contact_group(group)
      {
        id: group.id,
        name: group.name,
        description: group.description,
        contact_count: group.contacts.count,
        created_at: group.created_at,
        updated_at: group.updated_at
      }
    end
    
    def format_landing_page(page)
      {
        id: page.id,
        name: page.name,
        slug: page.slug,
        is_published: page.published_at.present?,
        published_at: page.published_at,
        visits: page.visits,
        conversions: page.conversions,
        created_at: page.created_at,
        updated_at: page.updated_at
      }
    end
    
    def format_email_template(template)
      {
        id: template.id,
        name: template.name,
        subject: template.subject,
        from_name: template.from_name,
        from_email: template.from_email,
        campaign_count: template.campaigns.count,
        created_at: template.created_at,
        updated_at: template.updated_at
      }
    end
    
    def wrap_in_html(content)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body>
          #{content}
        </body>
        </html>
      HTML
    end
  end
end
