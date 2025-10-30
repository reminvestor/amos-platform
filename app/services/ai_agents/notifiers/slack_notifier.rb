require 'faraday'

module AiAgents::Notifiers
  class SlackNotifier
    # Slack Web API endpoint
    SLACK_API_URL = 'https://slack.com/api'

    # Channel routing based on notification type
    CHANNELS = {
      clarification: ENV['SLACK_CLARIFICATIONS_CHANNEL'] || '#ai-clarifications',
      status: ENV['SLACK_STATUS_CHANNEL'] || '#ai-pipeline-status',
      alert: ENV['SLACK_ALERTS_CHANNEL'] || '#ai-pipeline-alerts',
      approval: ENV['SLACK_APPROVALS_CHANNEL'] || '#ai-pipeline-approvals'
    }.freeze

    def initialize
      @api_token = ENV['SLACK_API_TOKEN']
      @rate_limit_cache = {} # Track rate limits per minute
    end

    # Send interaction notification (clarifications, approvals)
    def send_interaction_notification(pipeline_interaction)
      return false unless slack_configured?

      pipeline = pipeline_interaction.pipeline_execution
      channel = determine_channel(pipeline_interaction.interaction_type)

      blocks = build_interaction_blocks(pipeline_interaction)

      result = post_message(
        channel: channel,
        text: "🤖 AI Pipeline Interaction Required: #{pipeline.ticket_id}",
        blocks: blocks,
        thread_ts: pipeline.slack_thread_ts # Reply in existing thread
      )

      # Store thread timestamp for future replies
      if result[:success] && result[:ts]
        pipeline.update(slack_thread_ts: result[:ts]) unless pipeline.slack_thread_ts
      end

      result[:success]
    rescue => e
      Rails.logger.error "Slack notification failed: #{e.message}"
      false
    end

    # Send state change notification
    def send_state_change_notification(pipeline_execution, new_state)
      return false unless slack_configured?

      channel = CHANNELS[:status]
      blocks = build_state_change_blocks(pipeline_execution, new_state)

      result = post_message(
        channel: channel,
        text: "🤖 Pipeline #{pipeline_execution.ticket_id} → #{new_state.upcase}",
        blocks: blocks,
        thread_ts: pipeline_execution.slack_thread_ts # Reply in thread
      )

      # Store thread timestamp on first message
      if result[:success] && result[:ts] && !pipeline_execution.slack_thread_ts
        pipeline_execution.update(slack_thread_ts: result[:ts])
      end

      result[:success]
    rescue => e
      Rails.logger.error "Slack state change notification failed: #{e.message}"
      false
    end

    # Send failure alert
    def send_failure_alert(pipeline_execution, error_message)
      return false unless slack_configured?

      channel = CHANNELS[:alert]
      blocks = build_failure_blocks(pipeline_execution, error_message)

      result = post_message(
        channel: channel,
        text: "🚨 AI Pipeline Failed: #{pipeline_execution.ticket_id}",
        blocks: blocks,
        thread_ts: pipeline_execution.slack_thread_ts
      )

      result[:success]
    rescue => e
      Rails.logger.error "Slack failure alert failed: #{e.message}"
      false
    end

    # Send approval request
    def send_approval_request(pipeline_execution)
      return false unless slack_configured?

      channel = CHANNELS[:approval]
      blocks = build_approval_blocks(pipeline_execution)

      result = post_message(
        channel: channel,
        text: "✋ Production Approval Required: #{pipeline_execution.ticket_id}",
        blocks: blocks,
        thread_ts: pipeline_execution.slack_thread_ts
      )

      result[:success]
    rescue => e
      Rails.logger.error "Slack approval request failed: #{e.message}"
      false
    end

    private

    def slack_configured?
      @api_token.present?
    end

    # Post message to Slack using Web API
    def post_message(channel:, text:, blocks: nil, thread_ts: nil)
      # Rate limiting check
      return { success: false, error: 'Rate limited' } if rate_limited?

      response = http_client.post('/chat.postMessage') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Authorization'] = "Bearer #{@api_token}"
        req.body = {
          channel: channel,
          text: text,
          blocks: blocks,
          thread_ts: thread_ts
        }.compact.to_json
      end

      if response.success?
        data = JSON.parse(response.body)
        if data['ok']
          { success: true, ts: data['ts'], channel: data['channel'] }
        else
          { success: false, error: data['error'] }
        end
      else
        { success: false, error: "HTTP #{response.status}" }
      end
    rescue => e
      { success: false, error: e.message }
    end

    # Build Slack blocks for interaction notification
    def build_interaction_blocks(interaction)
      pipeline = interaction.pipeline_execution

      blocks = [
        {
          type: 'header',
          text: {
            type: 'plain_text',
            text: "🤖 #{interaction.interaction_type.titleize} Required"
          }
        },
        {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: "*Ticket:*\n<#{pipeline.ticket_url}|#{pipeline.ticket_id}>"
            },
            {
              type: 'mrkdwn',
              text: "*Status:*\n#{pipeline.status.upcase}"
            },
            {
              type: 'mrkdwn',
              text: "*Title:*\n#{pipeline.ticket_title}"
            },
            {
              type: 'mrkdwn',
              text: "*Timeout:*\n#{interaction.timeout_at&.strftime('%H:%M %Z') || 'N/A'}"
            }
          ]
        },
        {
          type: 'divider'
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Question:*\n#{interaction.question}"
          }
        }
      ]

      # Add action buttons
      blocks << {
        type: 'actions',
        elements: [
          {
            type: 'button',
            text: {
              type: 'plain_text',
              text: 'View in Admin UI'
            },
            url: "#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}",
            style: 'primary'
          },
          {
            type: 'button',
            text: {
              type: 'plain_text',
              text: 'View Ticket'
            },
            url: pipeline.ticket_url
          }
        ]
      }

      blocks
    end

    # Build Slack blocks for state change
    def build_state_change_blocks(pipeline, new_state)
      latest_agent = pipeline.agent_executions.order(created_at: :desc).first

      blocks = [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Pipeline Update:* <#{pipeline.ticket_url}|#{pipeline.ticket_id}>\n*#{pipeline.ticket_title}*"
          }
        },
        {
          type: 'context',
          elements: [
            {
              type: 'mrkdwn',
              text: "Status: `#{pipeline.status_was&.upcase}` → `#{new_state.upcase}`"
            }
          ]
        }
      ]

      # Add agent info if available
      if latest_agent
        blocks << {
          type: 'context',
          elements: [
            {
              type: 'mrkdwn',
              text: "#{latest_agent.agent_id} completed in #{latest_agent.duration_human} | Cost: $#{latest_agent.cost&.round(2) || 0}"
            }
          ]
        }
      end

      # Add PR link if available
      if pipeline.pr_url.present?
        blocks << {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "📝 <#{pipeline.pr_url}|View Pull Request>"
          }
        }
      end

      blocks
    end

    # Build Slack blocks for failure alert
    def build_failure_blocks(pipeline, error_message)
      [
        {
          type: 'header',
          text: {
            type: 'plain_text',
            text: '🚨 AI Pipeline Failed'
          }
        },
        {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: "*Ticket:*\n<#{pipeline.ticket_url}|#{pipeline.ticket_id}>"
            },
            {
              type: 'mrkdwn',
              text: "*Status:*\n#{pipeline.status.upcase}"
            },
            {
              type: 'mrkdwn',
              text: "*Duration:*\n#{pipeline.duration_human}"
            },
            {
              type: 'mrkdwn',
              text: "*Cost:*\n#{pipeline.cost_dollars}"
            }
          ]
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Error:*\n```#{error_message[0..500]}```"
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
              url: "#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}",
              style: 'danger'
            }
          ]
        }
      ]
    end

    # Build Slack blocks for production approval
    def build_approval_blocks(pipeline)
      [
        {
          type: 'header',
          text: {
            type: 'plain_text',
            text: '✋ Production Approval Required'
          }
        },
        {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: "*Ticket:*\n<#{pipeline.ticket_url}|#{pipeline.ticket_id}>"
            },
            {
              type: 'mrkdwn',
              text: "*PR:*\n<#{pipeline.pr_url}|View Pull Request>"
            },
            {
              type: 'mrkdwn',
              text: "*Title:*\n#{pipeline.ticket_title}"
            },
            {
              type: 'mrkdwn',
              text: "*Branch:*\n#{pipeline.branch_name}"
            }
          ]
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "*Summary:*\nStaging tests passed. Ready for production deployment."
          }
        },
        {
          type: 'actions',
          elements: [
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: '✅ Approve'
              },
              url: "#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}/approve",
              style: 'primary'
            },
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: '❌ Reject'
              },
              url: "#{ENV['APP_URL']}/admin/pipeline/executions/#{pipeline.id}/reject",
              style: 'danger'
            }
          ]
        }
      ]
    end

    # Determine channel based on interaction type
    def determine_channel(interaction_type)
      case interaction_type
      when 'clarification'
        CHANNELS[:clarification]
      when 'approval'
        CHANNELS[:approval]
      else
        CHANNELS[:status]
      end
    end

    # HTTP client for Slack API
    def http_client
      @http_client ||= Faraday.new(url: SLACK_API_URL) do |f|
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end

    # Simple rate limiting (10 messages per minute)
    def rate_limited?
      current_minute = Time.current.to_i / 60
      @rate_limit_cache[current_minute] ||= 0

      if @rate_limit_cache[current_minute] >= 10
        return true
      end

      @rate_limit_cache[current_minute] += 1

      # Cleanup old entries
      @rate_limit_cache.delete_if { |k, _| k < current_minute - 5 }

      false
    end
  end
end
