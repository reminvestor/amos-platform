module AiAgents
  class BaseAgent
    attr_reader :context, :vector_store
    
    def initialize(args = {})
      @name = self.class.name.demodulize
      @instructions = args[:instructions]
      @additional_context = args[:additional_context] || []
      @previous_messages = args[:previous_messages] || []
      @model = args[:model] || 'gpt-4o'
      @max_tokens = args[:max_tokens] || 4096
      @temperature = args[:temperature] || 0.1
      
      # Initialize with the passed context if it's a Hash, otherwise create a new empty Hash
      @context = args.is_a?(Hash) ? args.dup : {}
      @vector_store = VectorStore.instance
      
      Rails.logger.info("AGENT: Initialized #{@name} with model=#{@model}, max_tokens=#{@max_tokens}, temperature=#{@temperature}")
      Rails.logger.debug("AGENT: Context keys: #{@context.keys.join(', ')}") if @context.present?
      Rails.logger.debug("AGENT: Instructions: #{@instructions.to_s.truncate(100)}") if @instructions
      Rails.logger.debug("AGENT: Additional context count: #{@additional_context.size}") if @additional_context
    end
    
    def execute
      Rails.logger.info("AGENT: #{@name} execution started")
      start_time = Time.current
      
      context = build_context
      
      Rails.logger.info("AGENT: #{@name} context built with #{context.size} elements")
      
      response = call_api(context)
      result = process_response(response)
      
      execution_time = Time.current - start_time
      Rails.logger.info("AGENT: #{@name} execution completed in #{execution_time.round(2)}s")
      Rails.logger.debug("AGENT: #{@name} result: #{result.to_s.truncate(300)}")
      
      result
    end
    
    def query_vector_store(query, limit = 5)
      Rails.logger.info("#{self.class.name}: Querying vector store with: '#{query}', limit: #{limit}")
      results = vector_store.search(query, limit)
      Rails.logger.info("#{self.class.name}: Vector store returned #{results.size} results")
      results
    end
    
    def call_openai_api(prompt, model = "gpt-4o", temperature = 0.7, max_tokens = 1500)
      require 'net/http'
      require 'uri'
      require 'json'
      
      Rails.logger.info("#{self.class.name}: Calling OpenAI API with model: #{model}, temperature: #{temperature}")
      Rails.logger.debug("#{self.class.name}: Prompt: #{prompt.truncate(200)}")
      
      uri = URI.parse("https://api.openai.com/v1/chat/completions")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
      
      request.body = JSON.dump({
        "model" => model,
        "messages" => [
          {
            "role" => "system", 
            "content" => "You are an AI assistant that is part of a multi-agent system for creating high-quality landing pages."
          },
          {
            "role" => "user",
            "content" => prompt
          }
        ],
        "temperature" => temperature,
        "max_tokens" => max_tokens
      })
      
      req_options = {
        use_ssl: uri.scheme == "https"
      }
      
      start_time = Time.current
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
      duration = Time.current - start_time
      
      if response.code == "200"
        result = JSON.parse(response.body)
        response_content = result["choices"].first["message"]["content"]
        Rails.logger.info("#{self.class.name}: OpenAI API call successful, took #{duration.round(2)}s")
        Rails.logger.debug("#{self.class.name}: Response content: #{response_content.truncate(200)}")
        return response_content
      else
        Rails.logger.error("#{self.class.name}: OpenAI API error - HTTP #{response.code}: #{response.body}")
        return nil
      end
    rescue => e
      Rails.logger.error("#{self.class.name}: Error calling OpenAI API: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
    
    def update_context(new_context)
      return if new_context.nil? || !new_context.is_a?(Hash)
      
      # Actually merge the new context into the main context
      new_context.each do |key, value|
        @context[key] = value
      end
      
      Rails.logger.info("AGENT: #{@name} context updated with #{new_context.size} new elements")
      Rails.logger.debug("AGENT: #{@name} updated context keys: #{@context.keys.join(', ')}")
    end
    
    def add_to_context(context_item)
      Rails.logger.info("AGENT: #{@name} adding item to context: #{context_item.to_s.truncate(100)}")
      @additional_context << context_item
    end
    
    def log_execution_start
      Rails.logger.info("="*50)
      Rails.logger.info("#{self.class.name}: STARTING EXECUTION")
      Rails.logger.info("="*50)
    end
    
    def log_execution_complete
      Rails.logger.info("="*50)
      Rails.logger.info("#{self.class.name}: EXECUTION COMPLETED")
      Rails.logger.info("="*50)
    end
    
    private
    
    def build_context
      Rails.logger.debug("AGENT: #{@name} building context")
      
      context = []
      
      # Add system message
      system_message = {
        role: 'system',
        content: @instructions || default_instructions
      }
      
      context << system_message
      
      # Add previous messages if they exist
      if @previous_messages.any?
        Rails.logger.debug("AGENT: #{@name} adding #{@previous_messages.size} previous messages to context")
        context.concat(@previous_messages)
      end
      
      # Add any additional context
      if @additional_context.any?
        Rails.logger.debug("AGENT: #{@name} adding #{@additional_context.size} additional context items")
        
        # Make sure each item in additional_context is properly formatted
        @additional_context.each do |item|
          if item.is_a?(Hash) && (item[:role] || item["role"])
            # Already properly formatted
            context << item
          else
            # Format as a system message
            context << {
              role: 'system',
              content: item.to_s
            }
          end
        end
      end
      
      Rails.logger.debug("AGENT: #{@name} context built with #{context.size} items")
      context
    end
    
    def call_api(context)
      Rails.logger.info("AGENT: #{@name} calling OpenAI API with context size: #{context.size}")
      api_start_time = Time.current
      
      begin
        client = OpenAI::Client.new
        response = client.chat(
          parameters: {
            model: @model,
            messages: context,
            max_tokens: @max_tokens,
            temperature: @temperature
          }
        )
        
        api_duration = Time.current - api_start_time
        token_usage = response.dig("usage")
        
        if token_usage
          Rails.logger.info("AGENT: #{@name} API call completed in #{api_duration.round(2)}s with #{token_usage['total_tokens']} total tokens (#{token_usage['prompt_tokens']} prompt + #{token_usage['completion_tokens']} completion)")
        else
          Rails.logger.info("AGENT: #{@name} API call completed in #{api_duration.round(2)}s but token usage information not available")
        end
        
        return response
      rescue => e
        Rails.logger.error("AGENT: #{@name} API call failed: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise
      end
    end
    
    def process_response(response)
      if response.dig("error")
        error_message = response.dig("error", "message")
        Rails.logger.error("AGENT: #{@name} received API error: #{error_message}")
        raise "OpenAI API Error: #{error_message}"
      end
      
      message = response.dig("choices", 0, "message", "content")
      
      if message.nil? || message.empty?
        Rails.logger.error("AGENT: #{@name} received empty response from API")
        raise "Empty response from OpenAI API"
      end
      
      Rails.logger.debug("AGENT: #{@name} received response (#{message.size} chars)")
      message
    end
    
    def default_instructions
      "You are a helpful assistant. Provide a clear and concise response."
    end
  end
end 