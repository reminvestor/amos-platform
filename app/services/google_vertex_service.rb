require "gemini-ai"

class GoogleVertexService
  include AgentLightningInstrumentable

  AVAILABLE_MODELS = {
    'gemini-1.5-pro' => {
      id: 'gemini-1.5-pro-001',
      name: 'Gemini 1.5 Pro',
      description: 'Best performing model for complex tasks',
      max_tokens: 8192,
      supports_vision: true,
      supports_tools: true
    },
    'gemini-1.5-flash' => {
      id: 'gemini-1.5-flash-001',
      name: 'Gemini 1.5 Flash',
      description: 'Fast and cost-effective',
      max_tokens: 8192,
      supports_vision: true,
      supports_tools: true
    }
  }.freeze

  def initialize(custom_model_id: nil, user: nil, entity: nil, context: {}, execution: nil)
    @project_id = ENV["GOOGLE_CLOUD_PROJECT"]
    @location = ENV["GOOGLE_CLOUD_LOCATION"] || "us-central1"
    
    # Initialize Gemini client
    # We use 'vertex-ai-api' service for Vertex AI access
    @client = Gemini.new(
      credentials: {
        service: 'vertex-ai-api',
        region: @location,
        project_id: @project_id
      },
      options: { server_sent_events: true }
    )
    
    @user = user
    @entity = entity
    @context = context
    @execution = execution
  end

  def send_message_converse(system_prompt, messages, model: "gemini-1.5-pro", max_tokens: 8192, temperature: 0.7, tools: [])
    model_config = AVAILABLE_MODELS[model] || AVAILABLE_MODELS['gemini-1.5-pro']
    model_id = model_config[:id]

    # Convert messages to Gemini format
    gemini_messages = format_messages_for_gemini(messages)
    
    # Add system prompt if present
    system_instruction = nil
    if system_prompt.present?
      system_instruction = { parts: [{ text: system_prompt }] }
    end

    # Configure tools if present
    tool_declarations = []
    if tools.any?
      tool_declarations = tools.map { |t| format_tool_for_gemini(t) }
    end

    Rails.logger.info "Sending request to Gemini (#{model_id})"

    begin
      payload = {
        contents: gemini_messages,
        system_instruction: system_instruction,
        generation_config: {
          max_output_tokens: max_tokens,
          temperature: temperature
        }
      }
      
      if tool_declarations.any?
        payload[:tools] = [{ function_declarations: tool_declarations }]
      end

      response = @client.generate_content(
        payload,
        options: { model: model_id }
      )
      
      # Extract text content
      # Note: Response format depends on gem version, assuming hash access
      content = response.dig('candidates', 0, 'content', 'parts', 0, 'text')
      
      # TODO: Handle tool calls (functionCall) loop here
      # For MVP we just return text. If tool call, content might be nil.
      
      return content || ""
    rescue => e
      Rails.logger.error "Gemini API Error: #{e.message}"
      raise AmosErrors::LlmError.new("Gemini Error: #{e.message}")
    end
  end

  private

  def format_messages_for_gemini(messages)
    messages.map do |msg|
      {
        role: msg[:role] == 'assistant' ? 'model' : 'user',
        parts: [{ text: msg[:content] }]
      }
    end
  end

  def format_tool_for_gemini(tool)
    {
      name: tool[:name],
      description: tool[:description],
      parameters: tool[:parameters]
    }
  end
end

