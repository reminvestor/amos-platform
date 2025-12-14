# frozen_string_literal: true

module Hub
  # Job to generate an agent response in a Hub thread
  # This is triggered when a user sends a message to an agent DM
  class AgentResponseJob < ApplicationJob
    queue_as :default
    
    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    
    def perform(thread_id:, message_id:, agent_id:, entity_id:)
      @thread = HubThread.find(thread_id)
      @message = HubMessage.find(message_id)
      @agent = AgentPlugin.find(agent_id)
      @entity = Entity.find(entity_id)
      
      Rails.logger.info "[Hub::AgentResponseJob] Processing response for #{@agent.name} in thread #{thread_id}"
      
      # Update agent presence to "thinking"
      update_agent_presence('thinking')
      
      # Generate and send the response
      generate_response
      
      # Update agent presence back to "available"
      update_agent_presence('available')
      
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "[Hub::AgentResponseJob] Record not found: #{e.message}"
    rescue => e
      Rails.logger.error "[Hub::AgentResponseJob] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      update_agent_presence('available')
      raise
    end
    
    private
    
    def update_agent_presence(status)
      presence = HubPresence.find_or_create_by(
        participant: @agent,
        entity_id: @entity.id
      )
      presence.update!(
        status: status,
        last_seen_at: Time.current
      )
      
      # Broadcast presence update
      HubChannel.broadcast_presence(@entity.id, {
        participant_id: @agent.id,
        participant_type: 'AgentPlugin',
        participant_name: @agent.name,
        status: status
      })
    rescue => e
      Rails.logger.warn "[Hub::AgentResponseJob] Could not update presence: #{e.message}"
    end
    
    def generate_response
      # Get conversation context (last 10 messages)
      recent_messages = @thread.hub_messages
                               .where(deleted: false)
                               .order(created_at: :desc)
                               .limit(10)
                               .reverse
      
      # Format conversation for the agent
      conversation = recent_messages.map do |msg|
        role = msg.sender == @agent ? 'assistant' : 'user'
        { role: role, content: msg.content }
      end
      
      # Build agent prompt
      system_prompt = build_system_prompt
      
      # Call the LLM to generate response
      response_content = call_agent_llm(system_prompt, conversation)
      
      if response_content.present?
        # Add agent's response to the thread
        @thread.add_message(
          sender: @agent,
          content: response_content,
          message_type: 'text'
        )
        
        Rails.logger.info "[Hub::AgentResponseJob] #{@agent.name} responded with #{response_content.length} chars"
      else
        Rails.logger.warn "[Hub::AgentResponseJob] No response generated"
      end
    end
    
    def build_system_prompt
      <<~PROMPT
        You are #{@agent.name}, an AI agent with the following capabilities:
        #{@agent.description}

        You are having a direct message conversation with a user.
        Respond helpfully and concisely. Be conversational and friendly.
        
        If the user asks you to do something outside your capabilities, let them know 
        and suggest how they might accomplish their goal (e.g., "I can help you analyze 
        that data, but for creating the report you'd want to work with Amos, the main assistant").
        
        Keep responses focused and actionable.
      PROMPT
    end
    
    def call_agent_llm(system_prompt, conversation)
      # Use the existing Bedrock client
      client = Aws::BedrockRuntime::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
      
      # Use claude-sonnet for agent responses (faster and cheaper)
      model_id = 'anthropic.claude-sonnet-4-20250514-v1:0'
      
      messages = conversation.map do |msg|
        {
          role: msg[:role],
          content: [{ text: msg[:content] }]
        }
      end
      
      # Ensure messages start with user if first is assistant
      if messages.first&.dig(:role) == 'assistant'
        messages.unshift({ role: 'user', content: [{ text: '[Conversation started]' }] })
      end
      
      response = client.converse(
        model_id: model_id,
        messages: messages,
        system: [{ text: system_prompt }],
        inference_config: {
          max_tokens: 1000,
          temperature: 0.7
        }
      )
      
      # Extract text from response
      response.output.message.content.first.text
      
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "[Hub::AgentResponseJob] Bedrock error: #{e.message}"
      "I apologize, but I'm having trouble processing your request right now. Please try again in a moment."
    rescue => e
      Rails.logger.error "[Hub::AgentResponseJob] LLM error: #{e.message}"
      nil
    end
  end
end
