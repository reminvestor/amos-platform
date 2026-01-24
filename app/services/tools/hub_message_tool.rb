# frozen_string_literal: true

module Tools
  # HubMessageTool
  #
  # Allows agents to send messages through the Collaborative Intelligence Hub.
  # This is the agent's interface to the Hub communication system.
  #
  class HubMessageTool < BaseTool
    # DEPRECATED: Hub messaging is no longer used. Amos communicates directly with users.
    
    def self.metadata
      {
        name: "hub_message",
        description: "DEPRECATED - DO NOT USE. Amos communicates directly with users in chat.",
        category: "deprecated",
        input_schema: {
          type: "object",
          properties: {
            recipient_type: {
              type: "string",
              enum: ["user", "channel", "thread"],
              description: "Who to send the message to: 'user' for DM, 'channel' for team channel, 'thread' for existing thread"
            },
            recipient_id: {
              type: "integer",
              description: "ID of the recipient (user_id, channel_id, or thread_id depending on recipient_type)"
            },
            message: {
              type: "string",
              description: "The message content to send"
            },
            message_type: {
              type: "string",
              enum: ["text", "status_update", "question"],
              default: "text",
              description: "Type of message: 'text' for normal, 'status_update' for progress, 'question' if you need a response"
            },
            needs_response: {
              type: "boolean",
              default: false,
              description: "Set to true if you need the recipient to respond before continuing"
            }
          },
          required: ["recipient_type", "recipient_id", "message"]
        }
      }
    end

    def execute(args)
      agent = context[:agent_plugin] || context[:execution]&.agent_plugin
      return error_response("No agent context available") unless agent

      recipient_type = args["recipient_type"]
      recipient_id = args["recipient_id"]
      message_content = args["message"]
      message_type = args["message_type"] || "text"
      needs_response = args["needs_response"] || false

      case recipient_type
      when "user"
        send_to_user(agent, recipient_id, message_content, message_type, needs_response)
      when "channel"
        send_to_channel(agent, recipient_id, message_content, message_type)
      when "thread"
        send_to_thread(agent, recipient_id, message_content, message_type, needs_response)
      else
        error_response("Invalid recipient_type: #{recipient_type}")
      end
    end

    private

    def send_to_user(agent, user_id, content, message_type, needs_response)
      user_to_message = User.find_by(id: user_id)
      return error_response("User not found") unless user_to_message

      context_service = Hub::AgentContextService.new(agent: agent, entity: entity)
      
      thread = context_service.start_thread_with(user_to_message)
      
      result = context_service.send_message(
        thread_id: thread.id,
        content: content,
        message_type: message_type,
        needs_response: needs_response
      )

      if result[:success]
        if needs_response
          # This is like ask_user - we need to wait for response
          {
            success: true,
            message: "Message sent to #{user_to_message.name}. Waiting for their response.",
            thread_id: thread.id,
            awaiting_response: true
          }
        else
          {
            success: true,
            message: "Message sent to #{user_to_message.name}.",
            thread_id: thread.id
          }
        end
      else
        error_response(result[:error])
      end
    end

    def send_to_channel(agent, channel_id, content, message_type)
      channel = entity.team_channels.find_by(id: channel_id)
      return error_response("Channel not found") unless channel

      # Make sure agent is in the channel
      unless channel.has_agent?(agent)
        channel.add_agent(agent)
      end

      thread = channel.main_thread
      
      # Verify agent can access this thread
      unless thread.participant?(agent)
        thread.add_participant(agent, role: 'member')
      end

      message = thread.add_message(
        sender: agent,
        content: content,
        message_type: message_type
      )

      {
        success: true,
        message: "Message posted to ##{channel.name}",
        message_id: message.id,
        thread_id: thread.id
      }
    end

    def send_to_thread(agent, thread_id, content, message_type, needs_response)
      context_service = Hub::AgentContextService.new(agent: agent, entity: entity)
      
      unless context_service.can_access_thread?(thread_id)
        return error_response("Not authorized to access this thread")
      end

      result = context_service.send_message(
        thread_id: thread_id,
        content: content,
        message_type: message_type,
        needs_response: needs_response
      )

      if result[:success]
        {
          success: true,
          message: "Message sent to thread",
          message_id: result[:message_id],
          awaiting_response: needs_response
        }
      else
        error_response(result[:error])
      end
    end

    def error_response(message)
      { success: false, error: message }
    end
  end
end
