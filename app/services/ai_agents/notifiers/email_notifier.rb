module AiAgents
  module Notifiers
    class EmailNotifier
      # Email notification service via Mailgun for AI Pipeline
      # Sends clarification requests, approvals, and timeout alerts

      def initialize
        @api_key = ENV['MAILGUN_API_KEY']
        @domain = ENV['MAILGUN_DOMAIN']
        @from_email = ENV['MAILGUN_FROM_EMAIL'] || "noreply@#{ENV['MAILGUN_DOMAIN']}"
        @to_email = ENV['PIPELINE_ALERT_EMAIL'] || ENV['ADMIN_EMAIL']
      end

      # Send interaction notification (clarification or approval request)
      def send_interaction_notification(interaction)
        return unless configured?

        subject = interaction.interaction_type == 'clarification' ? 
                    "Clarification Needed - Pipeline #{interaction.pipeline_execution.ticket_id}" :
                    "Approval Required - Pipeline #{interaction.pipeline_execution.ticket_id}"

        html_body = build_interaction_email(interaction)
        text_body = build_interaction_text(interaction)

        send_email(subject, html_body, text_body)

        Rails.logger.info "Sent email interaction notification for #{interaction.id}"
      rescue => e
        Rails.logger.error "Failed to send email interaction notification: #{e.message}"
      end

      # Send timeout notification
      def send_timeout_notification(pipeline, reason)
        return unless configured?

        subject = "Pipeline Timeout - #{pipeline.ticket_id}"
        html_body = build_timeout_email(pipeline, reason)
        text_body = build_timeout_text(pipeline, reason)

        send_email(subject, html_body, text_body)

        Rails.logger.info "Sent email timeout notification for pipeline #{pipeline.id}"
      rescue => e
        Rails.logger.error "Failed to send email timeout notification: #{e.message}"
      end

      # Send general state change notification
      def send_state_change_notification(pipeline, new_state)
        return unless configured?

        subject = "Pipeline #{pipeline.ticket_id} - #{new_state.titleize}"
        html_body = build_state_change_email(pipeline, new_state)
        text_body = build_state_change_text(pipeline, new_state)

        send_email(subject, html_body, text_body)

        Rails.logger.info "Sent email state change notification for pipeline #{pipeline.id}"
      rescue => e
        Rails.logger.error "Failed to send email state change notification: #{e.message}"
      end

      private

      def configured?
        @api_key.present? && @domain.present? && @to_email.present?
      end

      def build_interaction_email(interaction)
        pipeline = interaction.pipeline_execution
        emoji = interaction.interaction_type == 'clarification' ? '❓' : '🚀'
        title = interaction.interaction_type == 'clarification' ? 'Clarification Needed' : 'Approval Required'

        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background: #0078D4; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
              .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
              .info-table { width: 100%; margin: 20px 0; }
              .info-table td { padding: 8px; border-bottom: 1px solid #ddd; }
              .info-table td:first-child { font-weight: bold; width: 30%; }
              .button { display: inline-block; padding: 10px 20px; background: #0078D4; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
              .message-box { background: white; padding: 15px; border-left: 4px solid #0078D4; margin: 15px 0; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>#{emoji} #{title}</h1>
              </div>
              <div class="content">
                <table class="info-table">
                  <tr>
                    <td>Ticket:</td>
                    <td>#{pipeline.ticket_id}</td>
                  </tr>
                  <tr>
                    <td>Title:</td>
                    <td>#{pipeline.ticket_title}</td>
                  </tr>
                  <tr>
                    <td>Status:</td>
                    <td>#{pipeline.status.titleize}</td>
                  </tr>
                  <tr>
                    <td>Type:</td>
                    <td>#{interaction.interaction_type.titleize}</td>
                  </tr>
                  <tr>
                    <td>Priority:</td>
                    <td>#{interaction.priority&.titleize || 'Normal'}</td>
                  </tr>
                  <tr>
                    <td>Timeout:</td>
                    <td>#{interaction.timeout_at&.strftime('%Y-%m-%d %H:%M UTC') || 'No timeout'}</td>
                  </tr>
                </table>

                <div class="message-box">
                  <strong>Message:</strong><br>
                  #{interaction.message}
                </div>

                <a href="#{pipeline_url(pipeline)}" class="button">View Pipeline</a>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      def build_interaction_text(interaction)
        pipeline = interaction.pipeline_execution
        title = interaction.interaction_type == 'clarification' ? 'CLARIFICATION NEEDED' : 'APPROVAL REQUIRED'

        <<~TEXT
          #{title}

          Ticket: #{pipeline.ticket_id}
          Title: #{pipeline.ticket_title}
          Status: #{pipeline.status.titleize}
          Type: #{interaction.interaction_type.titleize}
          Priority: #{interaction.priority&.titleize || 'Normal'}
          Timeout: #{interaction.timeout_at&.strftime('%Y-%m-%d %H:%M UTC') || 'No timeout'}

          Message:
          #{interaction.message}

          View Pipeline: #{pipeline_url(pipeline)}
        TEXT
      end

      def build_timeout_email(pipeline, reason)
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background: #FF0000; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
              .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
              .button { display: inline-block; padding: 10px 20px; background: #FF0000; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>⏰ Pipeline Timeout</h1>
              </div>
              <div class="content">
                <p><strong>Ticket:</strong> #{pipeline.ticket_id}</p>
                <p><strong>Status:</strong> #{pipeline.status.titleize}</p>
                <p><strong>Reason:</strong> #{reason}</p>
                <a href="#{pipeline_url(pipeline)}" class="button">View Pipeline</a>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      def build_timeout_text(pipeline, reason)
        <<~TEXT
          PIPELINE TIMEOUT

          Ticket: #{pipeline.ticket_id}
          Status: #{pipeline.status.titleize}
          Reason: #{reason}

          View Pipeline: #{pipeline_url(pipeline)}
        TEXT
      end

      def build_state_change_email(pipeline, new_state)
        emoji = state_emoji(new_state)

        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background: #0078D4; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
              .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
              .button { display: inline-block; padding: 10px 20px; background: #0078D4; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>#{emoji} Pipeline State Change</h1>
              </div>
              <div class="content">
                <p>Pipeline <strong>#{pipeline.ticket_id}</strong> has transitioned to <strong>#{new_state.titleize}</strong></p>
                <a href="#{pipeline_url(pipeline)}" class="button">View Details</a>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      def build_state_change_text(pipeline, new_state)
        <<~TEXT
          PIPELINE STATE CHANGE

          Pipeline #{pipeline.ticket_id} has transitioned to #{new_state.titleize}

          View Details: #{pipeline_url(pipeline)}
        TEXT
      end

      def send_email(subject, html_body, text_body)
        require 'net/http'
        require 'uri'

        uri = URI("https://api.mailgun.net/v3/#{@domain}/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request.basic_auth('api', @api_key)
        request.set_form_data(
          from: @from_email,
          to: @to_email,
          subject: subject,
          text: text_body,
          html: html_body
        )

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "Mailgun API error: #{response.code} #{response.body}"
        end
      end

      def pipeline_url(pipeline)
        host = ENV['APP_HOST'] || 'http://localhost:3000'
        "#{host}/admin/pipeline/executions/#{pipeline.id}"
      end

      def state_emoji(state)
        case state.to_s
        when 'clarifying' then '❓'
        when 'planning' then '📋'
        when 'implementing' then '💻'
        when 'review' then '👀'
        when 'testing' then '🧪'
        when 'dev', 'staging' then '🚀'
        when 'prod' then '✅'
        when 'done' then '🎉'
        when 'failed' then '❌'
        when 'blocked' then '🚫'
        else '📌'
        end
      end
    end
  end
end
