module Tools
  class UpdateObjectTool < BaseTool
    # Core supported types
    CORE_TYPES = %w[campaign contact contact_group landing_page email_template email_sequence sequence_step sequence_enrollment affiliate commission payout].freeze
    
    def self.metadata
      {
        name: 'update_object',
        description: 'Update existing objects like campaigns, contacts, groups, OR custom module records (e.g., multi_armed_bandit_testing, social_media_posts)',
        category: 'data',
        input_schema: {
          type: 'object',
          properties: {
            object_type: {
              type: 'string',
              description: "The type of object to update. Can be a core type (campaign, contact, landing_page) OR a custom module slug (e.g., 'multi_armed_bandit_testing', 'social_media_posts')"
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
      
      # Parse data if it's a string (JSON)
      if data.is_a?(String)
        begin
          data = JSON.parse(data)
        rescue JSON::ParserError => e
          return error_response("Invalid JSON in data: #{e.message}")
        end
      end
      
      # Normalize object type (remove 's' if present, convert to snake_case)
      object_type = object_type.to_s.singularize.underscore

      begin
        # Check if it's a core type
        if CORE_TYPES.include?(object_type)
          result = update_core_object(object_type, object_id, data)
        else
          # Try as a custom module
          result = update_module_record(object_type, object_id, data)
        end
        
        success_response(
          object: result,
          message: "Successfully updated #{object_type} with ID #{object_id}"
        )
      rescue ActiveRecord::RecordNotFound => e
        error_response("#{object_type.titleize} not found with ID: #{object_id}")
      rescue ActiveRecord::RecordInvalid => e
        error_response("Validation failed: #{e.record.errors.full_messages.join(', ')}")
      rescue => e
        Rails.logger.error "[UpdateObject] Error updating #{object_type}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to update #{object_type}: #{e.message}")
      end
    end
    
    private
    
    def update_core_object(object_type, object_id, data)
      case object_type
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
      when 'email_sequence'
        update_email_sequence(object_id, data)
      when 'sequence_step'
        update_sequence_step(object_id, data)
      when 'sequence_enrollment'
        update_sequence_enrollment(object_id, data)
      else
        raise "Unsupported core object type: #{object_type}"
      end
    end
    
    # Update a record in a custom module
    def update_module_record(module_slug, record_id, data)
      Rails.logger.info "[UpdateObject] Updating custom module record: #{module_slug} ID #{record_id}"
      
      # Find the module
      app_module = entity.app_modules.find_by(slug: module_slug)
      app_module ||= entity.app_modules.find_by("slug LIKE ?", "%#{module_slug.gsub('_', '%')}%")
      
      unless app_module
        available = entity.app_modules.pluck(:slug).join(', ')
        raise "Module '#{module_slug}' not found. Available modules: #{available}"
      end
      
      # Get the dynamic model class
      model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
      
      unless model_class
        raise "Could not load model for module '#{app_module.slug}'. Module may not be deployed."
      end
      
      # SECURITY: Find record scoped to entity to prevent cross-tenant data access
      # This ensures Amos cannot accidentally (or maliciously) access another entity's data
      record = model_class.where(entity_id: entity.id).find_by(id: record_id)
      
      unless record
        raise ActiveRecord::RecordNotFound, "Record not found with ID: #{record_id}"
      end
      
      # Filter data to only include valid columns
      valid_columns = model_class.column_names
      filtered_data = data.stringify_keys.slice(*valid_columns)
      
      invalid_keys = data.stringify_keys.keys - valid_columns
      if invalid_keys.any?
        Rails.logger.warn "[UpdateObject] Ignoring invalid columns for #{module_slug}: #{invalid_keys.join(', ')}"
      end
      
      # Update the record
      record.update!(filtered_data)
      
      Rails.logger.info "[UpdateObject] ✅ Updated #{module_slug} record #{record_id}"
      
      # Return the updated record as a hash
      format_module_record(record, app_module)
    end
    
    def format_module_record(record, app_module)
      result = { id: record.id }
      
      # Get display fields from schema
      schema_fields = app_module.metadata&.dig('schema', 'fields') || []
      field_names = schema_fields.map { |f| f['name'] }
      
      # Add schema fields
      field_names.each do |field_name|
        result[field_name] = record.try(field_name) if record.respond_to?(field_name)
      end
      
      # Add timestamps
      result[:created_at] = record.created_at if record.respond_to?(:created_at)
      result[:updated_at] = record.updated_at if record.respond_to?(:updated_at)
      
      result
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
      
      # Smart field mapping - auto-correct common mistakes
      mapper = SmartFieldMapper.new
      mapping_result = mapper.map_data(data)
      corrected_data = mapping_result[:corrected_data]
      corrections = mapping_result[:corrections]
      
      if corrections.any?
        Rails.logger.info "[UpdateContact] Auto-corrected fields: #{corrections.map { |c| "#{c[:original_field]}=#{c[:original_value]} → #{c[:corrected_field]}=#{c[:corrected_value]}" }.join(', ')}"
      end
      
      begin
        contact.update!(corrected_data)
      rescue ActiveRecord::RecordInvalid => e
        # If still fails, provide helpful guidance for Amos to self-correct
        error_msg = e.record.errors.full_messages.join(', ')
        hint = build_field_hints(e.record.errors)
        raise ActiveRecord::RecordInvalid.new(e.record), "#{error_msg}. #{hint}"
      end
      
      result = format_contact(contact)
      
      # Include corrections so Amos can inform the user
      if corrections.any?
        result[:auto_corrections] = corrections.map { |c| 
          "Set #{c[:corrected_field]} to '#{c[:corrected_value]}' (#{c[:reason]})"
        }
        result[:note] = "Some values were automatically adjusted: #{result[:auto_corrections].join('; ')}"
      end
      
      result
    end
    
    # Build helpful hints when validation fails
    def build_field_hints(errors)
      hints = []
      
      errors.attribute_names.each do |attr|
        case attr.to_s
        when 'status'
          hints << "Valid status values: active, inactive, unsubscribed, bounced. For sales stages like 'qualified' or 'lead', use lifecycle_stage instead."
        when 'lifecycle_stage'
          hints << "Valid lifecycle_stage values: subscriber, lead, mql, sql, opportunity, customer, evangelist, other."
        end
      end
      
      hints.any? ? "HINT: #{hints.join(' ')}" : ""
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
      page = LandingPage.visible_to_user(user).find_by!(id: id)
      
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

    def update_email_sequence(id, data)
      sequence = EmailSequence.visible_to_user(user).find_by!(id: id)

      # Handle status changes with special actions
      if data['status'].present?
        case data['status']
        when 'active'
          unless sequence.activate!
            return error_response("Cannot activate sequence: #{sequence.errors.full_messages.join(', ')}")
          end
          data.delete('status') # Already handled by activate!
        when 'paused'
          unless sequence.pause!
            return error_response("Cannot pause sequence")
          end
          data.delete('status')
        when 'completed'
          unless sequence.complete!
            return error_response("Cannot complete sequence")
          end
          data.delete('status')
        end
      end

      # Handle enrollment trigger
      if data['enroll_contacts'] == true
        enrolled_count = sequence.enroll_contacts!
        Rails.logger.info "✅ Enrolled #{enrolled_count} contacts in sequence"
        data.delete('enroll_contacts')
      end

      sequence.update!(data) if data.any?
      format_email_sequence(sequence)
    end

    def update_sequence_step(id, data)
      visible_seq_ids = EmailSequence.visible_to_user(user).select(:id)
      step = SequenceStep.where(email_sequence_id: visible_seq_ids).find(id)

      step.update!(data)
      format_sequence_step(step)
    end

    def update_sequence_enrollment(id, data)
      enrollment = entity.sequence_enrollments.find(id)

      # Handle status actions
      if data['action'].present?
        case data['action']
        when 'start'
          unless enrollment.start!
            return error_response("Cannot start enrollment")
          end
        when 'pause'
          unless enrollment.pause!
            return error_response("Cannot pause enrollment")
          end
        when 'resume'
          unless enrollment.resume!
            return error_response("Cannot resume enrollment")
          end
        when 'cancel'
          unless enrollment.cancel!
            return error_response("Cannot cancel enrollment")
          end
        when 'complete'
          unless enrollment.complete!
            return error_response("Cannot complete enrollment")
          end
        end
        data.delete('action')
      end

      enrollment.update!(data) if data.any?
      format_sequence_enrollment(enrollment)
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
        title: page.title,
        slug: page.slug,
        status: page.status,
        is_published: page.status == "published",
        subdomain: page.subdomain,
        subdomain_url: page.subdomain_url,
        description: page.description,
        has_content: page.html_content.present?,
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

    def format_email_sequence(sequence)
      {
        id: sequence.id,
        name: sequence.name,
        goal: sequence.goal,
        status: sequence.status,
        contact_group_id: sequence.contact_group_id,
        step_count: sequence.step_count,
        enrolled_count: sequence.enrolled_count,
        active_count: sequence.active_count,
        completed_count: sequence.completed_count,
        open_rate: sequence.open_rate,
        click_rate: sequence.click_rate,
        completion_rate: sequence.completion_rate,
        created_at: sequence.created_at,
        updated_at: sequence.updated_at
      }
    end

    def format_sequence_step(step)
      {
        id: step.id,
        email_sequence_id: step.email_sequence_id,
        step_number: step.step_number,
        delay_hours: step.delay_hours,
        delay_in_days: step.delay_in_days,
        subject: step.effective_subject,
        email_template_id: step.email_template_id,
        sent_count: step.sent_count,
        opened_count: step.opened_count,
        clicked_count: step.clicked_count,
        open_rate: step.open_rate,
        click_rate: step.click_rate,
        created_at: step.created_at,
        updated_at: step.updated_at
      }
    end

    def format_sequence_enrollment(enrollment)
      {
        id: enrollment.id,
        email_sequence_id: enrollment.email_sequence_id,
        contact_id: enrollment.contact_id,
        status: enrollment.status,
        current_step_number: enrollment.current_step_number,
        next_send_at: enrollment.next_send_at,
        started_at: enrollment.started_at,
        completed_at: enrollment.completed_at,
        progress_percentage: enrollment.progress_percentage,
        days_in_sequence: enrollment.days_in_sequence,
        created_at: enrollment.created_at,
        updated_at: enrollment.updated_at
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
