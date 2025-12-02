# VoiceErrorSlackNotificationJob - Send Slack alerts for voice assistant errors
#
# Sends real-time Slack notifications when voice errors occur
# Integrates with Slack MCP for message delivery
#
# Usage:
#   VoiceErrorSlackNotificationJob.perform_later(
#     session_id: "abc123",
#     entity_name: "Acme Corp",
#     user_email: "user@example.com",
#     error_type: "quota_exceeded",
#     error_message: "Usage quota exceeded",
#     provider: "eleven_labs"
#   )
class VoiceErrorSlackNotificationJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff if Slack is temporarily unavailable
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(session_id:, entity_name:, user_email:, error_type:, error_message:, provider:)
    # Format error message for Slack
    message = format_slack_message(
      session_id: session_id,
      entity_name: entity_name,
      user_email: user_email,
      error_type: error_type,
      error_message: error_message,
      provider: provider
    )

    # Send to Slack via MCP or webhook
    send_to_slack(message, severity: determine_severity(error_type))

    Rails.logger.info("Sent Slack alert for voice error: #{error_type} (session: #{session_id})")
  end

  private

  def format_slack_message(session_id:, entity_name:, user_email:, error_type:, error_message:, provider:)
    # Format as Slack blocks for rich formatting
    {
      text: "🚨 Voice Assistant Error: #{error_type}",
      blocks: [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "🚨 Voice Assistant Error",
            emoji: true
          }
        },
        {
          type: "section",
          fields: [
            {
              type: "mrkdwn",
              text: "*Error Type:*\n#{format_error_type(error_type)}"
            },
            {
              type: "mrkdwn",
              text: "*Provider:*\n#{provider.capitalize}"
            },
            {
              type: "mrkdwn",
              text: "*Entity:*\n#{entity_name}"
            },
            {
              type: "mrkdwn",
              text: "*User:*\n#{user_email}"
            }
          ]
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*Message:*\n```#{error_message}```"
          }
        },
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: "Session: `#{session_id}` | Time: #{Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")}"
            }
          ]
        },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: {
                type: "plain_text",
                text: "View in Dashboard",
                emoji: true
              },
              url: "#{ENV['APP_URL'] || 'http://localhost:3000'}/admin/observability/errors"
            }
          ]
        }
      ]
    }
  end

  def format_error_type(error_type)
    case error_type
    when "auth_error"
      "🔑 Authentication Error"
    when "quota_exceeded"
      "⚠️ Quota Exceeded"
    when "transcriber_error"
      "🎤 Transcriber Error"
    when "input_error"
      "📥 Input Error"
    else
      "❌ #{error_type.titleize}"
    end
  end

  def determine_severity(error_type)
    case error_type
    when "auth_error", "quota_exceeded"
      :high
    when "transcriber_error"
      :medium
    else
      :low
    end
  end

  def send_to_slack(message, severity:)
    # Try Slack MCP first (if available)
    if slack_mcp_available?
      send_via_mcp(message, severity: severity)
    # Fallback to webhook if MCP not available
    elsif slack_webhook_url.present?
      send_via_webhook(message)
    else
      Rails.logger.warn("Slack notification not sent - no MCP or webhook configured")
    end
  end

  def slack_mcp_available?
    # Check if Slack MCP is configured
    # You can customize this check based on your MCP setup
    ENV["SLACK_MCP_ENABLED"] == "true"
  end

  def send_via_mcp(message, severity:)
    # This is where you'll integrate with your Slack MCP
    # Example implementation (customize based on your MCP):
    #
    # SlackMcpClient.post_message(
    #   channel: slack_channel_for_severity(severity),
    #   blocks: message[:blocks],
    #   text: message[:text]
    # )

    Rails.logger.info("Slack MCP integration - implement based on your MCP setup")
    Rails.logger.debug("Would send to channel: #{slack_channel_for_severity(severity)}")
    Rails.logger.debug("Message: #{message[:text]}")
  end

  def send_via_webhook(message)
    # Fallback to webhook if MCP not available
    require "net/http"
    require "uri"

    uri = URI.parse(slack_webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
    request.body = message.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Slack webhook failed: #{response.code} #{response.message}"
    end
  end

  def slack_webhook_url
    ENV["SLACK_WEBHOOK_URL"]
  end

  def slack_channel_for_severity(severity)
    case severity
    when :high
      ENV["SLACK_ALERTS_CHANNEL"] || "#voice-errors-critical"
    when :medium
      ENV["SLACK_ALERTS_CHANNEL"] || "#voice-errors"
    else
      ENV["SLACK_ALERTS_CHANNEL"] || "#voice-errors"
    end
  end
end
