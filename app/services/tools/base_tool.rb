module Tools
  class BaseTool
    attr_reader :user, :entity, :context

    def initialize(user:, entity:, context: {})
      @user = user
      @entity = entity
      @context = context
    end

    # Each tool must define its metadata
    def self.metadata
      raise NotImplementedError, "Tool must define metadata class method"
    end

    # Tool name from metadata
    def self.tool_name
      metadata[:name]
    end

    # Tool description from metadata
    def self.description
      metadata[:description]
    end

    # Tool input schema from metadata
    def self.input_schema
      metadata[:input_schema]
    end

    # Whether this tool is read-only (doesn't modify state)
    # Tools should override this if they are read-only
    def self.read_only?
      false
    end

    # Each tool must implement execute
    def execute(args)
      raise NotImplementedError, "Tool must implement execute method"
    end

    # Helper method for consistent error responses
    def error_response(message, details = {})
      {
        success: false,
        error: message,
        **details
      }
    end

    # Helper method for consistent success responses
    def success_response(data = {}, message = nil)
      response = { success: true }
      response[:message] = message if message
      response.merge(data)
    end

    # Log tool execution
    def log_execution(args)
      Rails.logger.info "🔧 Executing #{self.class.tool_name} with args: #{args.inspect}"
    end

    # Validate required arguments
    def validate_required_args(args, required_fields)
      missing = required_fields.select { |field| args[field].blank? && args[field.to_s].blank? }

      if missing.any?
        error_response("Missing required fields: #{missing.join(', ')}")
      else
        nil # No error
      end
    end

    # Get argument with symbol/string flexibility
    def get_arg(args, key, default = nil)
      args[key] || args[key.to_s] || default
    end
  end
end
