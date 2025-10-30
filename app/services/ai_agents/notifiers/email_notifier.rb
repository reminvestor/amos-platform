require 'faraday'

module AiAgents::Notifiers
  class EmailNotifier
    # Mailgun API endpoint
    MAILGUN_API_URL = 'https://api.mailgun.net/v3'

    def initialize
      @api_key = ENV['MAILGUN_API_KEY']
      @domain = ENV['MAILGUN_DOMAIN'] || 'mg.example.com'
      @from_email = ENV['PIPELINE_FROM_EMAIL'] || 'ai-pipeline@example.com'
      @from_name = ENV['PIPELINE_FROM_NAME'] || 'AI Development Pipeline'
    end

    # Send interaction notification (clarifications, approvals)
    def send_interaction_notification(pipeline_interaction)
      return false unless email_configured?

      pipeline = pipeline_interaction.pipeline_execution
      recipients = determine_recipients(pipeline_interaction)

      return false if recipients.empty?

      subject = build_subject(pipeline_interaction)
      html_body = build_interaction_email_html(pipeline_interaction)
      text_body = build_interaction_email_text(pipeline_interaction)

      recipients.each do |email|
        send_email(
          to: email,
          subject: subject,
          html: html_body,
          text: text_body,
          tags: ['pipeline', 'interaction', pipeline_interaction.interaction_type]
        )
      end

      true
    rescue => e
      Rails.logger.error "Email notification failed: #{e.message}"
      false
    end

    # Send state change notification
    def send_state_change_notification(pipeline_execution, new_state)
      return false unless email_configured?

      # Only send email for significant state changes
      return false unless significant_state?(new_state)

      recipients = [pipeline_execution.mcp_connection.metadata&.dig('notify_email')].compact
      return false if recipients.empty?

      subject = "Pipeline Update: #{pipeline_execution.ticket_id} → #{new_state.upcase}"
      html_body = build_state_change_email_html(pipeline_execution, new_state)
      text_body = build_state_change_email_text(pipeline_execution, new_state)

      recipients.each do |email|
        send_email(
          to: email,
          subject: subject,
          html: html_body,
          text: text_body,
          tags: ['pipeline', 'status', new_state]
        )
      end

      true
    rescue => e
      Rails.logger.error "Email state change notification failed: #{e.message}"
      false
    end

    # Send failure alert
    def send_failure_alert(pipeline_execution, error_message)
      return false unless email_configured?

      recipients = [
        pipeline_execution.mcp_connection.metadata&.dig('notify_email'),
        ENV['PIPELINE_ONCALL_EMAIL']
      ].compact

      return false if recipients.empty?

      subject = "🚨 Pipeline Failed: #{pipeline_execution.ticket_id}"
      html_body = build_failure_email_html(pipeline_execution, error_message)
      text_body = build_failure_email_text(pipeline_execution, error_message)

      recipients.each do |email|
        send_email(
          to: email,
          subject: subject,
          html: html_body,
          text: text_body,
          tags: ['pipeline', 'alert', 'failure']
        )
      end

      true
    rescue => e
      Rails.logger.error "Email failure alert failed: #{e.message}"
      false
    end

    # Send approval request
    def send_approval_request(pipeline_execution)
      return false unless email_configured?

      recipients = ENV['PIPELINE_APPROVERS_EMAIL']&.split(',')&.map(&:strip) || []
      return false if recipients.empty?

      subject = "✋ Production Approval Required: #{pipeline_execution.ticket_id}"
      html_body = build_approval_email_html(pipeline_execution)
      text_body = build_approval_email_text(pipeline_execution)

      recipients.each do |email|
        send_email(
          to: email,
          subject: subject,
          html: html_body,
          text: text_body,
          tags: ['pipeline', 'approval']
        )
      end

      true
    rescue => e
      Rails.logger.error "Email approval request failed: #{e.message}"
      false
    end

    private

    def email_configured?
      @api_key.present? && @domain.present?
    end

    # Send email via Mailgun API
    def send_email(to:, subject:, html:, text:, tags: [])
      response = http_client.post("/#{@domain}/messages") do |req|
        req.headers['Authorization'] = "Basic #{Base64.strict_encode64("api:#{@api_key}")}"
        req.body = {
          from: "#{@from_name} <#{@from_email}>",
          to: to,
          subject: subject,
          html: html,
          text: text,
          'o:tag' => tags
        }
      end

      if response.success?
        data = JSON.parse(response.body)
        Rails.logger.info "Email sent to #{to}: #{data['id']}"
        { success: true, message_id: data['id'] }
      else
        Rails.logger.error "Email failed to #{to}: #{response.status} - #{response.body}"
        { success: false, error: response.body }
      end
    rescue => e
      Rails.logger.error "Email error: #{e.message}"
      { success: false, error: e.message }
    end

    # Determine email recipients based on interaction type
    def determine_recipients(interaction)
      pipeline = interaction.pipeline_execution
      assignee_email = pipeline.ticket_metadata&.dig('assignee_email')

      case interaction.interaction_type
      when 'clarification'
        [assignee_email, ENV['PIPELINE_DEFAULT_EMAIL']].compact
      when 'approval'
        ENV['PIPELINE_APPROVERS_EMAIL']&.split(',')&.map(&:strip) || []
      else
        [ENV['PIPELINE_DEFAULT_EMAIL']].compact
      end
    end

    # Build email subject
    def build_subject(interaction)
      pipeline = interaction.pipeline_execution
      type = interaction.interaction_type.titleize

      "🤖 AI Pipeline #{type} Required: #{pipeline.ticket_id}"
    end

    # Check if state change is significant enough to email about
    def significant_state?(state)
      %w[review dev staging awaiting_prod_approval prod done failed].include?(state.to_s)
    end

    # Build HTML email for interaction
    def build_interaction_email_html(interaction)
      pipeline = interaction.pipeline_execution

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #4CAF50; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
            .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
            .footer { background: #333; color: white; padding: 10px; text-align: center; border-radius: 0 0 5px 5px; }
            .button { display: inline-block; padding: 10px 20px; background: #4CAF50; color: white; text-decoration: none; border-radius: 5px; margin: 10px 5px; }
            .info-box { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #4CAF50; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h2>🤖 AI Pipeline #{interaction.interaction_type.titleize} Required</h2>
            </div>
            <div class="content">
              <div class="info-box">
                <p><strong>Ticket:</strong> <a href="#{pipeline.ticket_url}">#{pipeline.ticket_id}</a></p>
                <p><strong>Title:</strong> #{pipeline.ticket_title}</p>
                <p><strong>Status:</strong> #{pipeline.status.upcase}</p>
                <p><strong>Timeout:</strong> #{interaction.timeout_at&.strftime('%B %d, %Y at %I:%M %p %Z') || 'N/A'}</p>
              </div>

              <h3>Question:</h3>
              <div style="background: white; padding: 15px; border: 1px solid #ddd; white-space: pre-wrap;">#{CGI.escapeHTML(interaction.question)}</div>

              <div style="text-align: center; margin-top: 20px;">
                <a href="#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}" class="button">View in Admin UI</a>
                <a href="#{pipeline.ticket_url}" class="button">View Ticket</a>
              </div>
            </div>
            <div class="footer">
              <p>AI Development Pipeline | Automated by Claude</p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    # Build plain text email for interaction
    def build_interaction_email_text(interaction)
      pipeline = interaction.pipeline_execution

      <<~TEXT
        AI Pipeline #{interaction.interaction_type.titleize} Required

        Ticket: #{pipeline.ticket_id}
        Title: #{pipeline.ticket_title}
        Status: #{pipeline.status.upcase}
        Timeout: #{interaction.timeout_at&.strftime('%B %d, %Y at %I:%M %p %Z') || 'N/A'}

        Question:
        #{interaction.question}

        View in Admin UI: #{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}
        View Ticket: #{pipeline.ticket_url}

        ---
        AI Development Pipeline | Automated by Claude
      TEXT
    end

    # Build HTML email for state change
    def build_state_change_email_html(pipeline, new_state)
      latest_agent = pipeline.agent_executions.order(created_at: :desc).first

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #2196F3; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
            .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
            .footer { background: #333; color: white; padding: 10px; text-align: center; border-radius: 0 0 5px 5px; }
            .info-box { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #2196F3; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h2>🤖 Pipeline Update</h2>
            </div>
            <div class="content">
              <div class="info-box">
                <p><strong>Ticket:</strong> <a href="#{pipeline.ticket_url}">#{pipeline.ticket_id}</a></p>
                <p><strong>Title:</strong> #{pipeline.ticket_title}</p>
                <p><strong>Status:</strong> #{pipeline.status_was&.upcase} → #{new_state.upcase}</p>
                #{latest_agent ? "<p><strong>Agent:</strong> #{latest_agent.agent_id} (#{latest_agent.duration_human}, $#{latest_agent.cost&.round(2)})</p>" : ''}
                #{pipeline.pr_url ? "<p><strong>PR:</strong> <a href='#{pipeline.pr_url}'>View Pull Request</a></p>" : ''}
              </div>
            </div>
            <div class="footer">
              <p>AI Development Pipeline | Automated by Claude</p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    # Build plain text email for state change
    def build_state_change_email_text(pipeline, new_state)
      latest_agent = pipeline.agent_executions.order(created_at: :desc).first

      text = <<~TEXT
        Pipeline Update

        Ticket: #{pipeline.ticket_id}
        Title: #{pipeline.ticket_title}
        Status: #{pipeline.status_was&.upcase} → #{new_state.upcase}
      TEXT

      if latest_agent
        text += "Agent: #{latest_agent.agent_id} (#{latest_agent.duration_human}, $#{latest_agent.cost&.round(2)})\n"
      end

      if pipeline.pr_url
        text += "PR: #{pipeline.pr_url}\n"
      end

      text += "\n---\nAI Development Pipeline | Automated by Claude\n"
      text
    end

    # Build HTML email for failure
    def build_failure_email_html(pipeline, error_message)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #f44336; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
            .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
            .footer { background: #333; color: white; padding: 10px; text-align: center; border-radius: 0 0 5px 5px; }
            .button { display: inline-block; padding: 10px 20px; background: #f44336; color: white; text-decoration: none; border-radius: 5px; margin: 10px 5px; }
            .error-box { background: #ffebee; padding: 15px; margin: 10px 0; border-left: 4px solid #f44336; font-family: monospace; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h2>🚨 AI Pipeline Failed</h2>
            </div>
            <div class="content">
              <p><strong>Ticket:</strong> <a href="#{pipeline.ticket_url}">#{pipeline.ticket_id}</a></p>
              <p><strong>Title:</strong> #{pipeline.ticket_title}</p>
              <p><strong>Status:</strong> #{pipeline.status.upcase}</p>
              <p><strong>Duration:</strong> #{pipeline.duration_human}</p>
              <p><strong>Cost:</strong> #{pipeline.cost_dollars}</p>

              <h3>Error:</h3>
              <div class="error-box">#{CGI.escapeHTML(error_message[0..500])}</div>

              <div style="text-align: center; margin-top: 20px;">
                <a href="#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}" class="button">View Details</a>
              </div>
            </div>
            <div class="footer">
              <p>AI Development Pipeline | Automated by Claude</p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    # Build plain text email for failure
    def build_failure_email_text(pipeline, error_message)
      <<~TEXT
        🚨 AI Pipeline Failed

        Ticket: #{pipeline.ticket_id}
        Title: #{pipeline.ticket_title}
        Status: #{pipeline.status.upcase}
        Duration: #{pipeline.duration_human}
        Cost: #{pipeline.cost_dollars}

        Error:
        #{error_message[0..500]}

        View Details: #{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}

        ---
        AI Development Pipeline | Automated by Claude
      TEXT
    end

    # Build HTML email for approval
    def build_approval_email_html(pipeline)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #FF9800; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
            .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
            .footer { background: #333; color: white; padding: 10px; text-align: center; border-radius: 0 0 5px 5px; }
            .button { display: inline-block; padding: 10px 20px; color: white; text-decoration: none; border-radius: 5px; margin: 10px 5px; }
            .approve { background: #4CAF50; }
            .reject { background: #f44336; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h2>✋ Production Approval Required</h2>
            </div>
            <div class="content">
              <p><strong>Ticket:</strong> <a href="#{pipeline.ticket_url}">#{pipeline.ticket_id}</a></p>
              <p><strong>Title:</strong> #{pipeline.ticket_title}</p>
              <p><strong>PR:</strong> <a href="#{pipeline.pr_url}">View Pull Request</a></p>
              <p><strong>Branch:</strong> #{pipeline.branch_name}</p>

              <p><strong>Summary:</strong> Staging tests passed. Ready for production deployment.</p>

              <div style="text-align: center; margin-top: 20px;">
                <a href="#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}/approve" class="button approve">✅ Approve</a>
                <a href="#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}/reject" class="button reject">❌ Reject</a>
              </div>
            </div>
            <div class="footer">
              <p>AI Development Pipeline | Automated by Claude</p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    # Build plain text email for approval
    def build_approval_email_text(pipeline)
      <<~TEXT
        ✋ Production Approval Required

        Ticket: #{pipeline.ticket_id}
        Title: #{pipeline.ticket_title}
        PR: #{pipeline.pr_url}
        Branch: #{pipeline.branch_name}

        Summary: Staging tests passed. Ready for production deployment.

        Approve: #{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}/approve
        Reject: #{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}/reject

        ---
        AI Development Pipeline | Automated by Claude
      TEXT
    end

    # HTTP client for Mailgun API
    def http_client
      @http_client ||= Faraday.new(url: MAILGUN_API_URL) do |f|
        f.request :multipart
        f.request :url_encoded
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
