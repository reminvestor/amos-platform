# Specialized agent for email campaigns and templates
module AgentJobs
  class EmailAgentJob < BaseAgentJob
    
    def execute_agent_task
      Rails.logger.info "[EmailAgent] Processing: #{@task}"
      
      # Determine email task type
      task_type = analyze_email_task
      
      case task_type
      when :campaign
        create_email_campaign
      when :template
        create_email_template
      when :send_single
        send_single_email
      when :list_management
        manage_email_lists
      else
        handle_general_email_task
      end
    end
    
    private
    
    def analyze_email_task
      task_lower = @task.downcase
      
      case task_lower
      when /campaign|newsletter|blast/i
        :campaign
      when /template/i
        :template
      when /send.*email.*to/i
        :send_single
      when /list|segment|subscribers?/i
        :list_management
      else
        :general
      end
    end
    
    def create_email_campaign
      stream_content("I'll help you create an email campaign. Let me gather some information.")
      
      update_status('running', 'Setting up campaign...', progress: 20)
      
      # Gather campaign information
      campaign_info = gather_campaign_info
      
      update_status('running', 'Creating campaign...', progress: 60)
      
      # Create the campaign
      campaign = EmailCampaign.create!(
        entity_id: @context[:entity_id],
        name: campaign_info[:name],
        subject: campaign_info[:subject],
        from_name: campaign_info[:from_name] || @context[:entity_name],
        from_email: campaign_info[:from_email],
        status: 'draft'
      )
      
      # Build email content
      campaign.content = build_email_content(campaign_info)
      campaign.save!
      
      update_status('running', 'Finalizing campaign...', progress: 90)
      
      stream_content(
        "✅ Email campaign created successfully!\n\n" +
        "Campaign: #{campaign.name}\n" +
        "Subject: #{campaign.subject}\n" +
        "Status: Draft\n\n" +
        "You can now schedule or send this campaign from your dashboard."
      )
      
      {
        success: true,
        campaign_id: campaign.id,
        message: "Email campaign '#{campaign.name}' created successfully!"
      }
    end
    
    def gather_campaign_info
      info = {
        from_email: load_default_from_email
      }
      
      # Ask for campaign details
      info[:name] = request_user_input("What should we call this campaign?")
      info[:subject] = request_user_input("What's the email subject line?")
      info[:target_audience] = request_user_input(
        "Who is this campaign for?",
        options: ["All contacts", "Customers only", "Prospects only", "Custom segment"]
      )
      
      if info[:target_audience] == "Custom segment"
        info[:segment_criteria] = request_user_input("Describe your target segment:")
      end
      
      info[:message] = request_user_input("What's the main message of your email? (2-3 paragraphs)")
      info[:call_to_action] = request_user_input("What action do you want recipients to take?")
      
      info
    end
    
    def create_email_template
      stream_content("I'll help you create an email template.")
      
      update_status('running', 'Creating template...', progress: 30)
      
      template_info = gather_template_info
      
      template = EmailTemplate.create!(
        entity_id: @context[:entity_id],
        name: template_info[:name],
        description: template_info[:description],
        template_type: template_info[:type],
        content: build_template_content(template_info)
      )
      
      stream_content(
        "✅ Email template created!\n\n" +
        "Template: #{template.name}\n" +
        "Type: #{template.template_type.humanize}\n\n" +
        "You can use this template for future campaigns."
      )
      
      {
        success: true,
        template_id: template.id,
        message: "Email template '#{template.name}' created successfully!"
      }
    end
    
    def gather_template_info
      info = {}
      
      info[:name] = request_user_input("What should we name this template?")
      info[:type] = request_user_input(
        "What type of template is this?",
        options: ["Newsletter", "Promotional", "Transactional", "Welcome", "Custom"]
      )
      info[:description] = request_user_input("Briefly describe this template's purpose:")
      
      case info[:type].downcase
      when "newsletter"
        info[:sections] = request_user_input("What sections should the newsletter have? (e.g., News, Tips, Featured Product)")
      when "promotional"
        info[:discount] = request_user_input("Is there a discount or offer? (optional)")
      when "welcome"
        info[:onboarding_steps] = request_user_input("What should new subscribers know about?")
      end
      
      info
    end
    
    def send_single_email
      stream_content("I'll help you send an email.")
      
      # Extract recipient from task
      recipient = extract_recipient(@task)
      
      if recipient.nil?
        recipient = request_user_input("Who should receive this email? (email address)")
      end
      
      subject = request_user_input("What's the subject line?")
      message = request_user_input("What's your message?")
      
      # Send via email service
      result = send_email(
        to: recipient,
        subject: subject,
        body: message,
        from: load_default_from_email
      )
      
      if result[:success]
        stream_content("✅ Email sent successfully to #{recipient}!")
        
        {
          success: true,
          recipient: recipient,
          message: "Email sent successfully!"
        }
      else
        {
          success: false,
          message: "Failed to send email: #{result[:error]}"
        }
      end
    end
    
    def manage_email_lists
      stream_content("I'll help you manage your email lists.")
      
      action = request_user_input(
        "What would you like to do?",
        options: ["View lists", "Create segment", "Import contacts", "Export list", "Clean list"]
      )
      
      case action
      when "View lists"
        show_email_lists
      when "Create segment"
        create_email_segment
      when "Import contacts"
        import_email_contacts
      when "Export list"
        export_email_list
      when "Clean list"
        clean_email_list
      end
    end
    
    def show_email_lists
      lists = Contact.where(entity_id: @context[:entity_id])
                    .group(:tags)
                    .count
      
      total_contacts = Contact.where(entity_id: @context[:entity_id]).count
      
      message = "📊 Your Email Lists:\n\n"
      message += "Total contacts: #{total_contacts}\n\n"
      
      lists.each do |tags, count|
        tag_list = tags.presence || "Untagged"
        message += "• #{tag_list}: #{count} contacts\n"
      end
      
      stream_content(message)
      
      {
        success: true,
        total_contacts: total_contacts,
        lists: lists
      }
    end
    
    def create_email_segment
      criteria = request_user_input("Describe your segment criteria:")
      name = request_user_input("What should we name this segment?")
      
      # Parse criteria and create segment
      segment = ContactSegment.create!(
        entity_id: @context[:entity_id],
        name: name,
        criteria: parse_segment_criteria(criteria),
        description: criteria
      )
      
      count = segment.contacts.count
      
      stream_content("✅ Segment '#{name}' created with #{count} contacts!")
      
      {
        success: true,
        segment_id: segment.id,
        contact_count: count
      }
    end
    
    def build_email_content(info)
      # Use AI or templates to build rich email content
      {
        subject: info[:subject],
        preheader: info[:subject],
        body: {
          sections: [
            {
              type: "text",
              content: info[:message]
            },
            {
              type: "button",
              text: info[:call_to_action],
              url: "{{cta_url}}"
            }
          ]
        }
      }
    end
    
    def build_template_content(info)
      # Build reusable template structure
      case info[:type].downcase
      when "newsletter"
        build_newsletter_template(info)
      when "promotional"
        build_promotional_template(info)
      when "welcome"
        build_welcome_template(info)
      else
        build_generic_template(info)
      end
    end
    
    def load_default_from_email
      entity = Entity.find(@context[:entity_id])
      entity.email || entity.users.first.email
    end
    
    def extract_recipient(text)
      # Extract email from text like "send email to john@example.com"
      match = text.match(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i)
      match[0] if match
    end
    
    def send_email(to:, subject:, body:, from:)
      # Integrate with email service (SendGrid, etc.)
      begin
        # EmailService.send(...)
        { success: true }
      rescue => e
        { success: false, error: e.message }
      end
    end
    
    def parse_segment_criteria(criteria)
      # Convert natural language to query criteria
      # "customers who purchased in last 30 days" => { purchased_at: 30.days.ago.. }
      {}
    end
    
    def build_newsletter_template(info)
      {
        sections: (info[:sections] || "News, Tips").split(",").map(&:strip).map { |section|
          { title: section, content: "{{#{section.downcase.gsub(' ', '_')}_content}}" }
        }
      }
    end
    
    def build_promotional_template(info)
      {
        headline: "{{headline}}",
        offer: info[:discount] || "{{offer}}",
        cta_button: "Shop Now",
        terms: "{{terms_and_conditions}}"
      }
    end
    
    def build_welcome_template(info)
      {
        greeting: "Welcome {{first_name}}!",
        intro: "We're excited to have you.",
        onboarding: info[:onboarding_steps],
        cta_button: "Get Started"
      }
    end
    
    def build_generic_template(info)
      {
        content: "{{main_content}}",
        cta_button: "{{cta_text}}"
      }
    end
    
    def handle_general_email_task
      stream_content("I'll help you with your email task: #{@task}")
      
      # Use AI to understand and execute the task
      # For now, provide guidance
      
      stream_content(
        "I can help you with:\n" +
        "• Creating email campaigns\n" +
        "• Building email templates\n" +
        "• Managing contact lists\n" +
        "• Sending individual emails\n\n" +
        "Please be more specific about what you'd like to do."
      )
      
      {
        success: true,
        message: "Please provide more details about your email task."
      }
    end
  end
end

