module AiAgents
  module Notifiers
    class SlackNotifier
      # Slack webhook notification service for AI Pipeline
      # Sends clarification requests, approvals, and timeout alerts

      def initialize
        @webhook_url = ENV['SLACK_WEBHOOK_URL']
        @api_token = ENV['SLACK_API_TOKEN']
        @channel = ENV['SLACK_PIPELINE_CHANNEL'] || '#ai-pipeline'
      end

      # Send interaction notification (clarification or approval request)
      def send_interaction_notification(interaction)
        return unless configured?

        message = build_interaction_message(interaction)
        send_slack_message(message)

        Rails.logger.info "Sent Slack interaction notification for #{interaction.id}"
      rescue => e
        Rails.logger.error "Failed to send Slack interaction notification: #{e.message}"
      end

      # Send timeout notification
      def send_timeout_notification(pipeline, reason)
        return unless configured?

        message = build_timeout_message(pipeline, reason)
        send_slack_message(message)

        Rails.logger.info "Sent Slack timeout notification for pipeline #{pipeline.id}"
      rescue => e
        Rails.logger.error "Failed to send Slack timeout notification: #{e.message}"
      end

      # Send general state change notification
      def send_state_change_notification(pipeline, new_state)
        return unless configured?

        message = build_state_change_message(pipeline, new_state)
        send_slack_message(message)

        Rails.logger.info "Sent Slack state change notification for pipeline #{pipeline.id}"
      rescue => e
        Rails.logger.error "Failed to send Slack state change notification: #{e.message}"
      end

      private

      def configured?
        @webhook_url.present? || @api_token.present?
      end

      def build_interaction_message(interaction)
        pipeline = interaction.pipeline_execution
        emoji = interaction.interaction_type == 'clarification' ? '❓' : '🚀'
        title = interaction.interaction_type == 'clarification' ? 'Clarification Needed' : 'Approval Required'

        {
          channel: @channel,
          username: 'AMOS AI Pipeline',
          icon_emoji: ':robot_face:',
          blocks: [
            {
              type: 'header',
              text: {
                type: 'plain_text',
                text: "#{emoji} #{title}",
                emoji: true
              }
            },
            {
              type: 'section',
              fields: [
                {
                  type: 'mrkdwn',
                  text: "*Ticket:*\n#{pipeline.ticket_id}"
                },
                {
                  type: 'mrkdwn',
                  text: "*Status:*\n#{pipeline.status.titleize}"
                },
                {
                  type: 'mrkdwn',
                  text: "*Type:*\n#{interaction.interaction_type.titleize}"
                },
                {
                  type: 'mrkdwn',
                  text: "*Priority:*\n#{interaction.priority&.titleize || 'Normal'}"
                }
              ]
            },
            {
              type: 'section',
              text: {
                type: 'mrkdwn',
                text: "*Message:*\n#{interaction.message}"
              }
            },
            {
              type: 'context',
              elements: [
                {
                  type: 'mrkdwn',
                  text: "Timeout: #{interaction.timeout_at&.strftime('%Y-%m-%d %H:%M UTC') || 'No timeout'}"
                }
              ]
            },
            {
              type: 'actions',
              elements: [
                {
                  type: 'button',
                  text: {
                    type: 'plain_text',
                    text: 'View Pipeline',
                    emoji: true
                  },
                  url: pipeline_url(pipeline),
                  style: 'primary'
                }
              ]
            }
          ]
        }
      end

      def build_timeout_message(pipeline, reason)
        {
          channel: @channel,
          username: 'AMOS AI Pipeline',
          icon_emoji: ':warning:',
          blocks: [
            {
              type: 'header',
              text: {
                type: 'plain_text',
                text: '⏰ Pipeline Timeout',
                emoji: true
              }
            },
            {
              type: 'section',
              fields: [
                {
                  type: 'mrkdwn',
                  text: "*Ticket:*\n#{pipeline.ticket_id}"
                },
                {
                  type: 'mrkdwn',
                  text: "*Status:*\n#{pipeline.status.titleize}"
                }
              ]
            },
            {
              type: 'section',
              text: {
                type: 'mrkdwn',
                text: "*Reason:*\n#{reason}"
              }
            },
            {
              type: 'actions',
              elements: [
                {
                  type: 'button',
                  text: {
                    type: 'plain_text',
                    text: 'View Pipeline',
                    emoji: true
                  },
                  url: pipeline_url(pipeline),
                  style: 'danger'
                }
              ]
            }
          ]
        }
      end

      def build_state_change_message(pipeline, new_state)
        emoji = state_emoji(new_state)
        color = state_color(new_state)

        {
          channel: @channel,
          username: 'AMOS AI Pipeline',
          icon_emoji: ':robot_face:',
          attachments: [
            {
              color: color,
              blocks: [
                {
                  type: 'section',
                  text: {
                    type: 'mrkdwn',
                    text: "#{emoji} *Pipeline #{pipeline.ticket_id}* transitioned to *#{new_state.titleize}*"
                  }
                },
                {
                  type: 'actions',
                  elements: [
                    {
                      type: 'button',
                      text: {
                        type: 'plain_text',
                        text: 'View Details'
                      },
                      url: pipeline_url(pipeline)
                    }
                  ]
                }
              ]
            }
          ]
        }
      end

      def send_slack_message(message)
        if @webhook_url.present?
          send_via_webhook(message)
        elsif @api_token.present?
          send_via_api(message)
        else
          Rails.logger.warn "Slack not configured - skipping notification"
        end
      end

      def send_via_webhook(message)
        require 'net/http'
        require 'json'

        uri = URI(@webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = message.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "Slack API error: #{response.code} #{response.body}"
        end
      end

      def send_via_api(message)
        require 'net/http'
        require 'json'

        uri = URI('https://slack.com/api/chat.postMessage')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.path, {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{@api_token}"
        })
        request.body = message.to_json

        response = http.request(response)
        result = JSON.parse(response.body)

        unless result['ok']
          raise "Slack API error: #{result['error']}"
        end
      end

      def pipeline_url(pipeline)
        # Generate URL to pipeline execution page
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
        when 'done', 'prod' then 'good'
        when 'failed', 'blocked' then 'danger'
        when 'review', 'testing' then 'warning'
        else '#439FE0'
        end
      end
    end
  end
end
