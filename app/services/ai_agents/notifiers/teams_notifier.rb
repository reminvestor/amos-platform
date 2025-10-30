module AiAgents
  module Notifiers
    class TeamsNotifier
      # Microsoft Teams webhook notification service for AI Pipeline
      # Sends clarification requests, approvals, and timeout alerts

      def initialize
        @webhook_url = ENV['TEAMS_WEBHOOK_URL']
      end

      # Send interaction notification (clarification or approval request)
      def send_interaction_notification(interaction)
        return unless configured?

        message = build_interaction_card(interaction)
        send_teams_message(message)

        Rails.logger.info "Sent Teams interaction notification for #{interaction.id}"
      rescue => e
        Rails.logger.error "Failed to send Teams interaction notification: #{e.message}"
      end

      # Send timeout notification
      def send_timeout_notification(pipeline, reason)
        return unless configured?

        message = build_timeout_card(pipeline, reason)
        send_teams_message(message)

        Rails.logger.info "Sent Teams timeout notification for pipeline #{pipeline.id}"
      rescue => e
        Rails.logger.error "Failed to send Teams timeout notification: #{e.message}"
      end

      # Send general state change notification
      def send_state_change_notification(pipeline, new_state)
        return unless configured?

        message = build_state_change_card(pipeline, new_state)
        send_teams_message(message)

        Rails.logger.info "Sent Teams state change notification for pipeline #{pipeline.id}"
      rescue => e
        Rails.logger.error "Failed to send Teams state change notification: #{e.message}"
      end

      private

      def configured?
        @webhook_url.present?
      end

      def build_interaction_card(interaction)
        pipeline = interaction.pipeline_execution
        title = interaction.interaction_type == 'clarification' ? '❓ Clarification Needed' : '🚀 Approval Required'
        theme_color = interaction.interaction_type == 'clarification' ? '0078D4' : 'FF8C00'

        {
          "@type": "MessageCard",
          "@context": "https://schema.org/extensions",
          "summary": title,
          "themeColor": theme_color,
          "title": title,
          "sections": [
            {
              "activityTitle": "Pipeline #{pipeline.ticket_id}",
              "activitySubtitle": pipeline.ticket_title,
              "facts": [
                {
                  "name": "Ticket:",
                  "value": pipeline.ticket_id
                },
                {
                  "name": "Status:",
                  "value": pipeline.status.titleize
                },
                {
                  "name": "Type:",
                  "value": interaction.interaction_type.titleize
                },
                {
                  "name": "Priority:",
                  "value": interaction.priority&.titleize || 'Normal'
                },
                {
                  "name": "Timeout:",
                  "value": interaction.timeout_at&.strftime('%Y-%m-%d %H:%M UTC') || 'No timeout'
                }
              ],
              "text": interaction.message
            }
          ],
          "potentialAction": [
            {
              "@type": "OpenUri",
              "name": "View Pipeline",
              "targets": [
                {
                  "os": "default",
                  "uri": pipeline_url(pipeline)
                }
              ]
            }
          ]
        }
      end

      def build_timeout_card(pipeline, reason)
        {
          "@type": "MessageCard",
          "@context": "https://schema.org/extensions",
          "summary": "Pipeline Timeout",
          "themeColor": "FF0000",
          "title": "⏰ Pipeline Timeout",
          "sections": [
            {
              "activityTitle": "Pipeline #{pipeline.ticket_id}",
              "facts": [
                {
                  "name": "Ticket:",
                  "value": pipeline.ticket_id
                },
                {
                  "name": "Status:",
                  "value": pipeline.status.titleize
                },
                {
                  "name": "Reason:",
                  "value": reason
                }
              ]
            }
          ],
          "potentialAction": [
            {
              "@type": "OpenUri",
              "name": "View Pipeline",
              "targets": [
                {
                  "os": "default",
                  "uri": pipeline_url(pipeline)
                }
              ]
            }
          ]
        }
      end

      def build_state_change_card(pipeline, new_state)
        emoji = state_emoji(new_state)
        color = state_color(new_state)

        {
          "@type": "MessageCard",
          "@context": "https://schema.org/extensions",
          "summary": "Pipeline State Change",
          "themeColor": color,
          "title": "#{emoji} Pipeline State Change",
          "sections": [
            {
              "activityTitle": "Pipeline #{pipeline.ticket_id}",
              "activitySubtitle": "Transitioned to #{new_state.titleize}",
              "facts": [
                {
                  "name": "New State:",
                  "value": new_state.titleize
                },
                {
                  "name": "Ticket:",
                  "value": pipeline.ticket_id
                }
              ]
            }
          ],
          "potentialAction": [
            {
              "@type": "OpenUri",
              "name": "View Details",
              "targets": [
                {
                  "os": "default",
                  "uri": pipeline_url(pipeline)
                }
              ]
            }
          ]
        }
      end

      def send_teams_message(message)
        require 'net/http'
        require 'json'

        uri = URI(@webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = message.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "Teams webhook error: #{response.code} #{response.body}"
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

      def state_color(state)
        case state.to_s
        when 'done', 'prod' then '00FF00'
        when 'failed', 'blocked' then 'FF0000'
        when 'review', 'testing' then 'FFA500'
        else '0078D4'
        end
      end
    end
  end
end
