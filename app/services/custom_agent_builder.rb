# Custom Agent Builder - Allows users to create their own agents
class CustomAgentBuilder
  include AgentModusOperandi
  
  attr_reader :agent_definition
  
  def initialize(agent_definition)
    @agent_definition = agent_definition
    validate_definition!
  end
  
  # Build a dynamic agent class from user definition
  def build
    builder = self
    
    Class.new(AgentJobs::EnhancedBaseAgentJob) do
      # Configure the agent based on user definition
      configure_agent do
        name builder.agent_definition[:name]
        description builder.agent_definition[:description]
        capabilities *builder.agent_definition[:capabilities]
        requires *builder.agent_definition[:required_context]
        rag_enabled builder.agent_definition[:use_rag] != false
        interactive builder.agent_definition[:interactive] != false
        max_questions builder.agent_definition[:max_questions] || 5
        question_priority builder.agent_definition[:question_priority] || :smart
      end
      
      # Dynamic information requirements
      define_method :determine_required_information do |context|
        questions = builder.generate_questions_from_definition(context)
        { questions: questions }
      end
      
      # Dynamic task execution
      define_method :perform_task do |context|
        builder.execute_custom_task(context, self)
      end
      
      # Store the definition for reference
      define_singleton_method :agent_definition do
        builder.agent_definition
      end
    end
  end
  
  # Generate questions based on user-defined fields
  def generate_questions_from_definition(context)
    return [] unless @agent_definition[:fields]
    
    @agent_definition[:fields].map do |field|
      {
        field: field[:name].to_sym,
        question: field[:question] || "Please provide #{field[:name].humanize}",
        why: field[:why] || "This information helps create better results",
        critical: field[:required] || false,
        suggestions: field[:examples] || [],
        validation: field[:validation]
      }
    end
  end
  
  # Execute custom task based on definition
  def execute_custom_task(context, agent_instance)
    # Use the defined workflow
    workflow = @agent_definition[:workflow] || default_workflow
    
    case workflow[:type]
    when 'llm_generation'
      execute_llm_generation(context, workflow, agent_instance)
    when 'api_integration'
      execute_api_integration(context, workflow, agent_instance)
    when 'data_processing'
      execute_data_processing(context, workflow, agent_instance)
    when 'custom_script'
      execute_custom_script(context, workflow, agent_instance)
    else
      raise "Unknown workflow type: #{workflow[:type]}"
    end
  end
  
  private
  
  def validate_definition!
    required_fields = [:name, :description, :workflow]
    missing = required_fields - @agent_definition.keys
    
    if missing.any?
      raise ArgumentError, "Missing required fields: #{missing.join(', ')}"
    end
    
    # Validate workflow
    unless @agent_definition[:workflow].is_a?(Hash)
      raise ArgumentError, "Workflow must be a hash"
    end
  end
  
  def default_workflow
    {
      type: 'llm_generation',
      model: 'claude-haiku-4-5-20251001',
      template: 'Generate content based on the provided context'
    }
  end
  
  def execute_llm_generation(context, workflow, agent)
    # Build prompt from template
    prompt = build_prompt_from_template(workflow[:template], context)
    
    # Add system prompt if defined
    system_prompt = workflow[:system_prompt] || build_default_system_prompt(context)
    
    # Call LLM
    begin
      bedrock = BedrockService.new
      response = bedrock.send_message(
        system_prompt,
        [{ role: "user", content: prompt }],
        model: workflow[:model] || 'claude-haiku-4-5-20251001',
        temperature: workflow[:temperature] || 0.7,
        max_tokens: workflow[:max_tokens] || 2000
      )
      
      # Process response based on output format
      process_llm_response(response, workflow[:output_format], agent)
    rescue => e
      agent.fail_job(e)
    end
  end
  
  def execute_api_integration(context, workflow, agent)
    # Execute API calls based on workflow definition
    endpoint = interpolate_template(workflow[:endpoint], context)
    headers = workflow[:headers] || {}
    
    # Add authentication if configured
    if auth = workflow[:authentication]
      headers.merge!(build_auth_headers(auth, context))
    end
    
    # Make API request
    response = HTTParty.send(
      workflow[:method] || :get,
      endpoint,
      headers: headers,
      body: build_request_body(workflow[:body], context)
    )
    
    # Process response
    process_api_response(response, workflow[:response_handler], agent)
  end
  
  def execute_data_processing(context, workflow, agent)
    # Process data based on workflow rules
    data = gather_data_from_context(context, workflow[:data_sources])
    
    # Apply transformations
    workflow[:transformations].each do |transform|
      data = apply_transformation(data, transform)
    end
    
    # Generate output
    generate_output(data, workflow[:output], agent)
  end
  
  def execute_custom_script(context, workflow, agent)
    # Execute custom Ruby code (sandboxed)
    # This would need proper sandboxing for security
    raise "Custom scripts not yet implemented for security reasons"
  end
  
  def build_prompt_from_template(template, context)
    # Replace placeholders with actual values
    interpolate_template(template, flatten_context(context))
  end
  
  def interpolate_template(template, values)
    template.gsub(/\{\{(\w+)\}\}/) do |match|
      key = $1.to_sym
      values[key] || match
    end
  end
  
  def flatten_context(context, prefix = '')
    flattened = {}
    
    context.each do |key, value|
      full_key = prefix.empty? ? key : "#{prefix}_#{key}"
      
      if value.is_a?(Hash)
        flattened.merge!(flatten_context(value, full_key))
      else
        flattened[full_key.to_sym] = value
      end
    end
    
    flattened
  end
  
  def build_default_system_prompt(context)
    <<~PROMPT
      You are #{context[:entity][:name]}'s AI assistant.
      
      Your task is to help with: #{@agent_definition[:description]}
      
      Guidelines:
      - Be specific and actionable
      - Use the provided context to personalize your response
      - Follow the brand voice: #{context[:settings][:brand_voice] || 'professional'}
      
      Remember to incorporate all provided information into your response.
    PROMPT
  end
  
  def process_llm_response(response, format, agent)
    case format
    when 'json'
      JSON.parse(response, symbolize_names: true)
    when 'html'
      { html: response, type: 'generated_content' }
    when 'text'
      { content: response, type: 'text' }
    else
      { raw_response: response }
    end
  end
  
  def process_api_response(response, handler, agent)
    if handler
      # Apply custom response handling logic
      case handler[:type]
      when 'json_extract'
        extract_from_json(response.parsed_response, handler[:path])
      when 'status_check'
        { success: response.success?, data: response.parsed_response }
      else
        response.parsed_response
      end
    else
      response.parsed_response
    end
  end
end

# Example usage for user-created agents:
# 
# agent_definition = {
#   name: "Blog Post Generator",
#   description: "Creates SEO-optimized blog posts",
#   capabilities: ["content_generation", "seo_optimization"],
#   required_context: ["topic", "keywords"],
#   use_rag: true,
#   interactive: true,
#   max_questions: 3,
#   
#   fields: [
#     {
#       name: "topic",
#       question: "What topic would you like to write about?",
#       required: true,
#       why: "This helps me create focused, relevant content"
#     },
#     {
#       name: "keywords",
#       question: "What keywords should I optimize for?",
#       required: false,
#       examples: ["AI automation", "machine learning"],
#       why: "SEO optimization"
#     },
#     {
#       name: "tone",
#       question: "What tone should the blog post have?",
#       examples: ["professional", "casual", "technical"],
#       required: false
#     }
#   ],
#   
#   workflow: {
#     type: "llm_generation",
#     model: "claude-sonnet-4-6",
#     system_prompt: "You are an expert blog writer...",
#     template: <<~TEMPLATE
#       Write a blog post about {{gathered_topic}} for {{entity_name}}.
#       
#       Target audience: {{business_target_audience}}
#       Keywords to include: {{gathered_keywords}}
#       Tone: {{gathered_tone}}
#       
#       Additional context from our knowledge base:
#       {{rag_content}}
#     TEMPLATE
#     output_format: "html",
#     max_tokens: 4000
#   }
# }
# 
# # Create and run the custom agent
# builder = CustomAgentBuilder.new(agent_definition)
# CustomBlogAgent = builder.build
# CustomBlogAgent.perform_later(
#   job_id: SecureRandom.uuid,
#   task: "Create a blog post about AI",
#   context: context,
#   callback_url: callback_url
# )
