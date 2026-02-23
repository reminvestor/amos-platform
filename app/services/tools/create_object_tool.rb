module Tools
  class CreateObjectTool < BaseTool
    def self.metadata
      {
        name: "create_object",
        description: "Create basic objects like campaigns, contacts, or groups",
        category: "data",
        input_schema: {
          type: "object",
          properties: {
            object_type: {
              type: "string",
              description: "The type of object to create (e.g., 'campaigns', 'contacts', 'contact_groups')"
            },
            data: {
              type: "object",
              description: "The data for creating the object"
            }
          },
          required: [ "object_type", "data" ]
        }
      }
    end

    IDENTITY_FIELDS = %w[user_id entity_id user entity created_by_id].freeze

    def execute(args)
      log_execution(args)

      object_type = get_arg(args, :object_type)
      data = get_arg(args, :data, {})

      # SECURITY: Strip identity fields — these are injected server-side, never from LLM
      data = sanitize_identity_fields(data)

      # Validate required args
      if error = validate_required_args(args, [ :object_type, :data ])
        return error
      end

      # Validate object type - check static types first, then dynamic modules
      valid_types = [ "campaigns", "contacts", "contact_groups", "email_templates", "email_sequences", "sequence_steps", "sequence_enrollments", "opportunities", "activities", "support_tickets" ]
      
      # Check for dynamic module type
      if !valid_types.include?(object_type)
        config = ScoutDataRegistry.object_config(object_type, entity)
        if config && config[:dynamic]
          return create_module_record(object_type, config, data)
        else
          available_modules = entity.app_modules.active.pluck(:slug).map(&:pluralize)
          return error_response(
            "Cannot create objects of type: #{object_type}",
            valid_types: valid_types + available_modules,
            note: "For landing pages, websites, apps, or workflows, use platform_create with the appropriate type"
          )
        end
      end

      begin
        result = case object_type
        when "campaigns"
          create_campaign(data)
        when "contacts"
          create_contact(data)
        when "contact_groups"
          create_contact_group(data)
        when "email_templates"
          create_email_template(data)
        when "email_sequences"
          create_email_sequence(data)
        when "sequence_steps"
          create_sequence_step(data)
        when "sequence_enrollments"
          create_sequence_enrollment(data)
        when "opportunities"
          create_opportunity(data)
        when "activities"
          create_activity(data)
        when "support_tickets"
          create_support_ticket(data)
        end

        # Determine if this was a find-or-create merge vs a new record
        was_existing = @was_existing || false
        @was_existing = nil  # reset for next call

        response = {
          object_type: object_type,
          id: result.id,
          created: !was_existing,
          updated: was_existing,
          record: serialize_record(result)
        }
        response[:note] = "Existing record found and updated (matched by email)" if was_existing
        
        # Include corrections so Amos can inform the user what was adjusted
        if @field_corrections&.any?
          response[:auto_corrections] = @field_corrections.map { |c| 
            "Set #{c[:corrected_field]} to '#{c[:corrected_value]}' (#{c[:reason]})"
          }
          note = response[:note] || ""
          note += ". " if note.present?
          note += "Some values were automatically adjusted: #{response[:auto_corrections].join('; ')}"
          response[:note] = note
        end

        response[:next_actions] = next_actions_for(object_type, result)
        
        success_response(response)
      rescue => e
        Rails.logger.error "CreateObjectTool error: #{e.class}: #{e.message}"
        V3::AiErrorTransformer.transform(e, type: object_type&.singularize, tool: "create_object", data: data)
      end
    end

    private

    def create_campaign(data)
      data = data.symbolize_keys

      # Check for drip mode -- route to EmailSequence internally
      mode = data.delete(:mode)&.to_s&.downcase
      steps = data.delete(:steps)

      if mode == "drip" && steps.present?
        return create_drip_campaign(data, steps)
      end

      data[:status] ||= "draft"

      # Remove fields that don't exist on Campaign model
      data.delete(:from_email)
      data.delete(:from_name)

      # Auto-create template if subject+body provided but no template_id
      if data[:email_template_id].blank? && data[:subject].present? && data[:body].present?
        template = EmailTemplate.create!(
          name: "#{data[:name]} Template",
          subject: data.delete(:subject),
          body: data.delete(:body),
          user: user,
          entity: entity
        )
        data[:email_template_id] = template.id
        Rails.logger.info "✅ Auto-created email template '#{template.name}' (ID: #{template.id}) for campaign"
      end

      # Handle unresolved variables
      if data[:email_template_id].is_a?(String) && data[:email_template_id].include?("{{")
        data[:email_template_id] = nil
      end

      # Clean up foreign keys
      if data[:email_template_id].to_s == "0" || data[:email_template_id].to_s.empty?
        data[:email_template_id] = nil
      end
      if data[:email_template_id].is_a?(String) && data[:email_template_id].match?(/^\d+$/)
        data[:email_template_id] = data[:email_template_id].to_i
      end

      # Find-or-create by name
      name = data[:name]
      if name.present?
        existing = entity.campaigns.find_by(name: name)
        if existing
          Rails.logger.info "♻️ Campaign '#{name}' already exists (ID: #{existing.id}) — returning existing"
          @was_existing = true
          return existing
        end
      end

      campaign = Campaign.new(data)
      campaign.user = user
      campaign.entity = entity
      campaign.save!

      Rails.logger.info "✅ Created campaign: #{campaign.name} (ID: #{campaign.id})"
      campaign
    end

    def create_drip_campaign(data, steps)
      # Drip campaigns are stored as EmailSequences internally
      # The AI sees "campaign" with mode: "drip", platform routes to EmailSequence

      # Need a contact_group_id for sequences
      contact_group_id = data[:contact_group_id]
      unless contact_group_id
        # Create a default group if none specified
        group = ContactGroup.create!(
          name: "#{data[:name]} Recipients",
          user: user,
          entity: entity
        )
        contact_group_id = group.id
      end

      sequence = EmailSequence.create!(
        name: data[:name] || "Drip Campaign",
        entity: entity,
        contact_group_id: contact_group_id,
        status: "draft"
      )

      # Create steps
      steps.each_with_index do |step_data, index|
        step_data = step_data.symbolize_keys if step_data.is_a?(Hash)
        template_id = step_data[:template_id] || step_data[:email_template_id]
        delay = step_data[:delay_days] || step_data[:delay_hours].to_i / 24 || 0

        SequenceStep.create!(
          email_sequence: sequence,
          email_template_id: template_id,
          step_number: index + 1,
          delay_hours: delay * 24,
          subject: step_data[:subject],
          body: step_data[:body]
        )
      end

      Rails.logger.info "✅ Created drip campaign (sequence): #{sequence.name} (ID: #{sequence.id}) with #{steps.length} steps"
      sequence
    end

    def create_contact(data)
      # Smart field mapping - auto-correct common mistakes
      mapper = SmartFieldMapper.new
      mapping_result = mapper.map_data(data)
      data = mapping_result[:corrected_data].symbolize_keys
      @field_corrections = mapping_result[:corrections]
      
      if @field_corrections.any?
        Rails.logger.info "[CreateContact] Auto-corrected fields: #{@field_corrections.map { |c| "#{c[:original_field]}=#{c[:original_value]} → #{c[:corrected_field]}=#{c[:corrected_value]}" }.join(', ')}"
      end
      
      # Handle status values - must be lowercase, default to active
      if data[:status].present?
        data[:status] = data[:status].downcase
      end

      # Remove deprecated lead boolean -- lifecycle_stage handles this now
      data.delete(:lead)

      # Smart name defaults: extract from email if missing
      if data[:email].present?
        if data[:first_name].blank? || data[:last_name].blank?
          prefix = data[:email].split('@').first.to_s
          parts = prefix.split(/[._-]/).map(&:capitalize)
          data[:first_name] = parts.first || "Contact" if data[:first_name].blank?
          data[:last_name] = parts.length > 1 ? parts.last : data[:first_name] if data[:last_name].blank?
        end
      end

      # Strip unknown attributes — store them as custom_fields so data isn't lost
      valid_columns = Contact.column_names.map(&:to_sym)
      unknown_attrs = data.keys - valid_columns - [:contact_group_ids]
      if unknown_attrs.any?
        custom_fields = (data[:custom_fields] || {}).symbolize_keys
        unknown_attrs.each do |attr|
          custom_fields[attr] = data.delete(attr)
        end
        data[:custom_fields] = custom_fields
        Rails.logger.info "[CreateContact] Moved unknown attrs to custom_fields: #{unknown_attrs.join(', ')}"
      end

      # ═══ FIND-OR-UPDATE-OR-CREATE by email ═══
      # If a contact with this email already exists for this entity, merge new data
      # instead of crashing on a duplicate. This saves the LLM from having to check first.
      existing = data[:email].present? ? entity.contacts.find_by(email: data[:email]) : nil

      if existing
        # Merge: only overwrite fields that are provided and non-blank
        update_data = data.except(:email) # don't update the email itself
        update_data.reject! { |_k, v| v.blank? }
        
        # Merge custom_fields additively (don't overwrite existing custom fields)
        if update_data[:custom_fields].present? && existing.custom_fields.present?
          update_data[:custom_fields] = existing.custom_fields.merge(update_data[:custom_fields].stringify_keys)
        end

        existing.update!(update_data) if update_data.any?
        Rails.logger.info "♻️ Found existing contact #{existing.email} (ID: #{existing.id}) — merged new data"
        @was_existing = true
        return existing
      end

      # New contact
      contact = Contact.new(data)
      contact.entity = entity
      contact.user = user
      
      begin
        contact.save!
      rescue ActiveRecord::RecordInvalid => e
        error_msg = e.record.errors.full_messages.join(', ')
        hints = build_validation_hints(e.record)
        hint = hints.any? ? " HINT: #{hints.join(' ')}" : ""
        raise ActiveRecord::RecordInvalid.new(e.record), "#{error_msg}.#{hint}"
      end

      Rails.logger.info "✅ Created contact: #{contact.email} (ID: #{contact.id})"
      contact
    end

    # Build helpful hints from validation errors so the Brain can self-correct in one try
    def build_validation_hints(record)
      hints = []
      record.errors.each do |error|
        case error.attribute.to_s
        when 'status'
          hints << "Valid status values: #{Contact::STATUSES.join(', ')}."
        when 'lifecycle_stage'
          hints << "Valid lifecycle_stage values: #{Contact::LIFECYCLE_STAGES.keys.join(', ')}."
        when 'lead_source'
          hints << "Valid lead_source values: #{Contact::LEAD_SOURCES.join(', ')}."
        when 'email'
          hints << "Email must be present and valid (e.g., user@example.com)."
        when 'first_name', 'last_name'
          hints << "#{error.attribute.to_s.titleize} is required."
        end
      end
      hints.uniq
    end

    def create_contact_group(data)
      data = data.symbolize_keys
      name = data[:name]
      member_ids = Array(data.delete(:contact_ids)).compact
      member_emails = Array(data.delete(:contact_emails)).compact

      if name.present?
        existing = entity.contact_groups.find_by(name: name)
        if existing
          Rails.logger.info "♻️ Contact group '#{name}' already exists (ID: #{existing.id}) — returning existing"
          @was_existing = true
          assign_group_members(existing, member_ids, member_emails)
          return existing
        end
      end

      group = ContactGroup.new(data)
      group.entity = entity
      group.user = user
      group.save!

      assign_group_members(group, member_ids, member_emails)

      Rails.logger.info "✅ Created contact group: #{group.name} (ID: #{group.id}, members: #{group.contacts.count})"
      group
    end

    def assign_group_members(group, member_ids, member_emails)
      contacts_to_add = []
      contacts_to_add += entity.contacts.where(id: member_ids) if member_ids.any?
      contacts_to_add += entity.contacts.where(email: member_emails) if member_emails.any?

      contacts_to_add.uniq.each do |contact|
        group.contacts << contact unless group.contact_ids.include?(contact.id)
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end

    def create_email_template(data)
      data = data.symbolize_keys
      name = data[:name]

      # Find-or-create by name: if template already exists, return it
      if name.present?
        existing = entity.email_templates.find_by(name: name)
        if existing
          Rails.logger.info "♻️ Email template '#{name}' already exists (ID: #{existing.id}) — returning existing"
          @was_existing = true
          return existing
        end
      end

      template = EmailTemplate.new(data)
      template.user = user
      template.entity = entity
      template.save!

      Rails.logger.info "✅ Created email template: #{template.name} (ID: #{template.id})"
      template
    end

    def create_email_sequence(data)
      data = data.symbolize_keys

      data[:status] ||= "draft"
      data[:enrolled_count] ||= 0
      data[:completed_count] ||= 0
      data[:active_count] ||= 0

      # Find-or-create by name
      name = data[:name]
      if name.present?
        existing = EmailSequence.visible_to_user(user).find_by(name: name)
        if existing
          Rails.logger.info "♻️ Email sequence '#{name}' already exists (ID: #{existing.id}) — returning existing"
          @was_existing = true
          return existing
        end
      end

      # Verify contact group exists, or auto-create one
      if data[:contact_group_id].present?
        contact_group = entity.contact_groups.find_by(id: data[:contact_group_id])
        return error_response("Contact group not found with ID: #{data[:contact_group_id]}") unless contact_group
      else
        group_name = data.delete(:contact_group_name) || "#{name || 'Sequence'} Recipients"
        contact_group = entity.contact_groups.find_by(name: group_name)
        contact_group ||= ContactGroup.create!(
          name: group_name,
          user: user,
          entity: entity
        )
        data[:contact_group_id] = contact_group.id
        Rails.logger.info "✅ Auto-created contact group '#{contact_group.name}' (ID: #{contact_group.id}) for sequence"
      end

      sequence = EmailSequence.new(data)
      sequence.entity = entity
      sequence.save!

      Rails.logger.info "✅ Created email sequence: #{sequence.name} (ID: #{sequence.id})"
      sequence
    end

    def create_sequence_step(data)
      data = data.symbolize_keys

      data[:delay_hours] ||= 0
      data[:sent_count] ||= 0
      data[:opened_count] ||= 0
      data[:clicked_count] ||= 0

      # Convert delay_days to delay_hours if provided
      if data[:delay_days].present? && data[:delay_hours] == 0
        data[:delay_hours] = data.delete(:delay_days).to_i * 24
      end

      # Verify email sequence exists (user-scoped asset)
      if data[:email_sequence_id].present?
        sequence = EmailSequence.visible_to_user(user).find_by(id: data[:email_sequence_id])
        return error_response("Email sequence not found with ID: #{data[:email_sequence_id]}") unless sequence
      end

      # Verify email template exists if provided (CRM data — entity-scoped)
      if data[:email_template_id].present?
        template = entity.email_templates.find_by(id: data[:email_template_id])
        return error_response("Email template not found with ID: #{data[:email_template_id]}") unless template
      end

      # Auto-create template from subject+body if no template_id
      if data[:email_template_id].blank? && data[:subject].present? && data[:body].present?
        seq_name = sequence&.name || "Sequence"
        step_num = data[:step_number] || "?"
        template = EmailTemplate.create!(
          name: "#{seq_name} - Step #{step_num}",
          subject: data.delete(:subject),
          body: data.delete(:body),
          user: user,
          entity: entity
        )
        data[:email_template_id] = template.id
        Rails.logger.info "✅ Auto-created email template '#{template.name}' (ID: #{template.id}) for sequence step"
      end

      # Auto-assign step_number if missing
      if data[:step_number].blank? && sequence
        data[:step_number] = (sequence.sequence_steps.maximum(:step_number) || 0) + 1
      end

      # Find-or-update by sequence + step_number
      if sequence && data[:step_number].present?
        existing = sequence.sequence_steps.find_by(step_number: data[:step_number])
        if existing
          existing.update!(data.except(:email_sequence_id, :step_number))
          Rails.logger.info "♻️ Updated existing step #{existing.step_number} (ID: #{existing.id})"
          @was_existing = true
          return existing
        end
      end

      step = SequenceStep.new(data)
      step.save!

      Rails.logger.info "✅ Created sequence step #{step.step_number} for sequence #{step.email_sequence_id} (ID: #{step.id})"
      step
    end

    def create_sequence_enrollment(data)
      # Symbolize keys for consistent access
      data = data.symbolize_keys

      # Ensure required fields
      data[:status] ||= "pending"
      data[:current_step_number] ||= 0

      # Verify email sequence exists
      if data[:email_sequence_id].present?
        sequence = EmailSequence.visible_to_user(user).find_by(id: data[:email_sequence_id])
        return error_response("Email sequence not found with ID: #{data[:email_sequence_id]}") unless sequence
      end

      # Verify contact exists
      if data[:contact_id].present?
        contact = entity.contacts.find_by(id: data[:contact_id])
        return error_response("Contact not found with ID: #{data[:contact_id]}") unless contact
      end

      # Check if already enrolled
      if SequenceEnrollment.exists?(email_sequence_id: data[:email_sequence_id], contact_id: data[:contact_id])
        Rails.logger.info "ℹ️ Contact #{data[:contact_id]} already enrolled in sequence #{data[:email_sequence_id]}"
        return SequenceEnrollment.find_by(email_sequence_id: data[:email_sequence_id], contact_id: data[:contact_id])
      end

      Rails.logger.info "📝 Creating sequence enrollment with data: #{data.inspect}"

      enrollment = SequenceEnrollment.new(data)
      enrollment.entity = entity
      enrollment.save!

      Rails.logger.info "✅ Enrolled contact #{enrollment.contact_id} in sequence #{enrollment.email_sequence_id} (ID: #{enrollment.id})"
      enrollment
    end

    def create_opportunity(data)
      data = data.symbolize_keys

      data[:stage] ||= "lead"
      data[:probability] ||= Opportunity::STAGES.dig(data[:stage], :probability) || 10

      # Find-or-create by name within entity
      name = data[:name]
      if name.present?
        existing = entity.opportunities.find_by(name: name)
        if existing
          Rails.logger.info "♻️ Opportunity '#{name}' already exists (ID: #{existing.id}) — returning existing"
          @was_existing = true
          return existing
        end
      end

      # Verify contact exists if provided
      if data[:contact_id].present?
        contact = entity.contacts.find_by(id: data[:contact_id])
        unless contact
          # Try to find by email
          if data[:contact_email].present?
            contact = entity.contacts.find_by(email: data[:contact_email])
          end
          unless contact
            return error_response("Contact not found with ID: #{data[:contact_id]}")
          end
        end
        data[:contact_id] = contact.id
      elsif data[:contact_email].present?
        # Find or create contact by email
        contact = entity.contacts.find_by(email: data[:contact_email])
        unless contact
          contact = entity.contacts.create!(
            email: data[:contact_email],
            first_name: data[:contact_first_name] || data[:contact_email].split('@').first,
            last_name: data[:contact_last_name] || '',
            status: 'active',
            lead: true,
            user: user
          )
          Rails.logger.info "✅ Auto-created contact: #{contact.email} (ID: #{contact.id})"
        end
        data[:contact_id] = contact.id
        data.delete(:contact_email)
        data.delete(:contact_first_name)
        data.delete(:contact_last_name)
      end

      Rails.logger.info "📝 Creating opportunity with data: #{data.inspect}"

      opportunity = Opportunity.new(data)
      opportunity.entity = entity
      opportunity.user = user
      opportunity.save!

      # Create initial activity
      Activity.create!(
        entity: entity,
        opportunity: opportunity,
        contact: opportunity.contact,
        user: user,
        activity_type: 'opportunity_created',
        subject: "Opportunity created: #{opportunity.name}",
        description: "New opportunity created with value #{opportunity.value || 0} in stage #{opportunity.stage}",
        status: 'completed',
        completed_at: Time.current
      )

      Rails.logger.info "✅ Created opportunity: #{opportunity.name} (ID: #{opportunity.id})"
      opportunity
    end

    def create_activity(data)
      data = data.symbolize_keys

      data[:activity_type] ||= "note"
      data[:status] ||= "pending"
      data[:priority] ||= "normal"

      # Verify contact exists if provided
      if data[:contact_id].present?
        contact = entity.contacts.find_by(id: data[:contact_id])
        unless contact
          return error_response("Contact not found with ID: #{data[:contact_id]}")
        end
      elsif data[:contact_email].present?
        # Auto-find or create contact from email
        contact = entity.contacts.find_by(email: data[:contact_email])
        unless contact
          contact = entity.contacts.create!(
            email: data[:contact_email],
            first_name: data.delete(:contact_first_name) || data[:contact_email].split("@").first.capitalize,
            last_name: data.delete(:contact_last_name) || "",
            status: "active",
            user: user
          )
          Rails.logger.info "✅ Auto-created contact '#{contact.email}' (ID: #{contact.id}) for activity"
        end
        data[:contact_id] = contact.id
        data.delete(:contact_email)
      end

      # Verify opportunity exists if provided
      if data[:opportunity_id].present?
        opportunity = entity.opportunities.find_by(id: data[:opportunity_id])
        unless opportunity
          return error_response("Opportunity not found with ID: #{data[:opportunity_id]}")
        end
        data[:contact_id] ||= opportunity.contact_id
      end

      # Handle due date/time
      if data[:due_in_hours].present?
        data[:due_at] = data[:due_in_hours].to_i.hours.from_now
        data.delete(:due_in_hours)
      elsif data[:due_in_days].present?
        data[:due_at] = data[:due_in_days].to_i.days.from_now
        data.delete(:due_in_days)
      end

      activity = Activity.new(data)
      activity.entity = entity
      activity.user = user
      activity.save!

      Rails.logger.info "✅ Created activity: #{activity.activity_type} - #{activity.subject} (ID: #{activity.id})"
      activity
    end

    def create_support_ticket(data)
      data = data.symbolize_keys

      title = data[:title] || data[:subject] || data[:name]
      return error_response("Missing: title (describe the issue)") if title.blank?

      description = data[:description] || data[:body] || ""
      category = data[:category]&.downcase
      priority = data[:priority]&.downcase || "medium"

      # Use the model's built-in factory for dedup, fingerprinting, and signal emission
      ticket = SupportTicket.create_from_user_report!(
        entity: entity,
        user: user,
        title: title,
        description: description
      )

      # Apply category/priority overrides if provided
      updates = {}
      updates[:category] = category if category.present? && SupportTicket::CATEGORIES.include?(category)
      updates[:priority] = priority if SupportTicket::PRIORITIES.include?(priority)
      ticket.update!(updates) if updates.any?

      Rails.logger.info "✅ Created support ticket: #{ticket.ticket_number} — #{ticket.title}"
      ticket
    end

    def create_module_record(object_type, config, data)
      # Parse "module_slug/model_name" format
      parts = object_type.to_s.split('/')
      module_slug = parts[0]
      model_name = parts[1]
      
      # Find the module
      app_module = entity.app_modules.active.find_by(slug: module_slug)
      app_module ||= entity.app_modules.active.find_by(slug: module_slug.singularize)
      
      unless app_module
        return error_response("Module not found: #{module_slug}")
      end
      
      # Get or load the model
      if model_name.present?
        model_code = app_module.module_codes.models.find_by(name: model_name)
        model_code ||= app_module.module_codes.models.find_by(name: model_name.classify)
      else
        model_codes = app_module.module_codes.models.validated_or_deployed
        if model_codes.count > 1
          return error_response(
            "Module #{app_module.name} has multiple models. Specify which one to create.",
            available_models: model_codes.map { |mc| "#{module_slug}/#{mc.name}" }
          )
        end
        model_code = model_codes.first
      end
      
      unless model_code
        available = app_module.module_codes.models.pluck(:name)
        return error_response(
          "Model not found: #{model_name}",
          available_models: available.map { |m| "#{module_slug}/#{m}" }
        )
      end
      
      # Load the model class
      model_class = Modules::DynamicModelLoader.instance.get_model(app_module, model_code.name)
      unless model_class
        model_class = Modules::DynamicModelLoader.instance.load_model(model_code)
      end
      
      unless model_class
        return error_response("Could not load model: #{model_code.name}")
      end
      
      # SECURITY: sanitize + inject identity server-side
      data = sanitize_identity_fields(data || {}).symbolize_keys
      data[:entity_id] = entity.id
      
      # Filter to valid columns only
      valid_columns = model_class.column_names.map(&:to_sym)
      filtered_data = data.slice(*valid_columns)
      
      Rails.logger.info "[CreateObjectTool] Creating #{app_module.name} with: #{filtered_data.keys.join(', ')}"
      
      record = model_class.create!(filtered_data)
      
      success_response(
        object_type: object_type,
        module_name: app_module.name,
        id: record.id,
        created: true,
        record: record.attributes
      )
    rescue ActiveRecord::RecordInvalid => e
      error_response(
        "Validation failed: #{e.message}",
        validation_errors: e.record.errors.full_messages
      )
    rescue => e
      Rails.logger.error "[CreateObjectTool] Module record creation failed: #{e.message}"
      error_response("Creation failed: #{e.message}")
    end
    
    def next_actions_for(object_type, record)
      id = record.id
      case object_type
      when "campaigns"
        [
          "Add recipients: platform_update(type: 'campaign', id: #{id}, data: { contact_group_ids: [GROUP_ID] })",
          "Send it: platform_execute(action: 'send_campaign', campaign_id: #{id})"
        ]
      when "contacts"
        [
          "Add to a group: platform_create(type: 'contact_group', data: { name: '...', contact_ids: [#{id}] })",
          "Create an opportunity: platform_create(type: 'opportunity', data: { name: '...', contact_id: #{id} })"
        ]
      when "contact_groups"
        [
          "Create a campaign for this group: platform_create(type: 'campaign', data: { name: '...', email_template_id: TEMPLATE_ID })",
          "Create an email sequence: platform_create(type: 'email_sequence', data: { name: '...', contact_group_id: #{id} })"
        ]
      when "email_templates"
        [
          "Use in a campaign: platform_create(type: 'campaign', data: { name: '...', email_template_id: #{id} })",
          "Use in a sequence step: platform_create(type: 'sequence_step', data: { email_sequence_id: SEQ_ID, email_template_id: #{id}, step_number: 1, delay_hours: 0 })"
        ]
      when "email_sequences"
        [
          "Add steps: platform_create(type: 'sequence_step', data: { email_sequence_id: #{id}, step_number: 1, delay_hours: 0, email_template_id: TEMPLATE_ID })",
          "Enroll contacts: platform_execute(action: 'enroll_sequence', sequence_id: #{id})"
        ]
      when "sequence_steps"
        ["Step added. Add more steps or enroll contacts in the sequence."]
      when "opportunities"
        [
          "Add an activity: platform_create(type: 'activity', data: { activity_type: 'note', subject: '...', opportunity_id: #{id} })"
        ]
      when "activities"
        ["Activity recorded. Present the result to the user."]
      when "support_tickets"
        ["Ticket created. Let the user know their issue has been logged and will be investigated."]
      else
        []
      end
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
          lifecycle_stage: record.lifecycle_stage,
          status: record.status,
          created_at: record.created_at
        }
      when ContactGroup
        {
          id: record.id,
          name: record.name,
          description: record.description,
          created_at: record.created_at
        }
      when EmailSequence
        {
          id: record.id,
          name: record.name,
          goal: record.goal,
          status: record.status,
          contact_group_id: record.contact_group_id,
          enrolled_count: record.enrolled_count,
          completed_count: record.completed_count,
          active_count: record.active_count,
          created_at: record.created_at
        }
      when SequenceStep
        {
          id: record.id,
          email_sequence_id: record.email_sequence_id,
          step_number: record.step_number,
          delay_hours: record.delay_hours,
          delay_in_days: record.delay_in_days,
          email_template_id: record.email_template_id,
          subject: record.subject,
          body: record.body&.truncate(100),
          created_at: record.created_at
        }
      when SequenceEnrollment
        {
          id: record.id,
          email_sequence_id: record.email_sequence_id,
          contact_id: record.contact_id,
          status: record.status,
          current_step_number: record.current_step_number,
          next_send_at: record.next_send_at,
          progress_percentage: record.progress_percentage,
          created_at: record.created_at
        }
      when SupportTicket
        {
          id: record.id,
          ticket_number: record.ticket_number,
          title: record.title,
          status: record.status,
          priority: record.priority,
          category: record.category,
          source: record.source,
          created_at: record.created_at
        }
      else
        record.as_json
      end
    end

    def sanitize_identity_fields(data)
      data = data.is_a?(Hash) ? data.dup : {}
      IDENTITY_FIELDS.each do |field|
        data.delete(field)
        data.delete(field.to_sym)
      end
      data
    end
  end
end
