# Custom exception classes for AMOS platform
# Provides detailed error context and actionable guidance for users

module AmosErrors
  # Base error class for all AMOS errors
  class BaseError < StandardError
    attr_reader :context, :user_message, :retry_after

    def initialize(message, user_message: nil, retry_after: nil, context: {})
      super(message)
      @user_message = user_message || message
      @retry_after = retry_after
      @context = context
    end

    def to_h
      {
        error: self.class.name.demodulize,
        message: user_message,
        retry_after: retry_after,
        context: context
      }.compact
    end
  end

  # AWS Bedrock / AI Service Errors
  class BedrockError < BaseError
    def initialize(message, retry_after: 60, context: {})
      super(
        message,
        user_message: "AI service error: #{message}",
        retry_after: retry_after,
        context: context
      )
    end
  end

  class BedrockThrottlingError < BedrockError
    def initialize(context: {})
      super(
        "AI service is currently busy. Please try again in a moment.",
        retry_after: 60,
        context: context
      )
    end
  end

  class BedrockTimeoutError < BedrockError
    def initialize(context: {})
      super(
        "AI service request timed out. This usually happens with complex requests. Please try again or simplify your request.",
        retry_after: 30,
        context: context
      )
    end
  end

  class BedrockUnavailableError < BedrockError
    def initialize(context: {})
      super(
        "AI service is temporarily unavailable. Our team has been notified. Please try again in a few minutes.",
        retry_after: 120,
        context: context
      )
    end
  end

  # Integration Errors (Stripe, HubSpot, Mailgun, etc.)
  class IntegrationError < BaseError
    attr_reader :integration_name, :operation

    def initialize(message, integration:, operation: nil, context: {})
      @integration_name = integration
      @operation = operation

      user_msg = "#{integration} integration error: #{message}"
      user_msg += " (Operation: #{operation})" if operation

      super(
        message,
        user_message: user_msg,
        context: context.merge(integration: integration, operation: operation)
      )
    end
  end

  class IntegrationAuthError < IntegrationError
    def initialize(integration:, context: {})
      super(
        "Authentication failed. Please reconnect your #{integration} account in Settings > Integrations.",
        integration: integration,
        context: context
      )
    end
  end

  class IntegrationRateLimitError < IntegrationError
    def initialize(integration:, retry_after: 300, context: {})
      super(
        "Rate limit exceeded for #{integration}. Please try again later.",
        integration: integration,
        context: context
      )
      @retry_after = retry_after
    end
  end

  # Workflow Errors
  class WorkflowError < BaseError
    attr_reader :phase, :execution_id, :workflow_name

    def initialize(message, phase: nil, execution_id: nil, workflow_name: nil, context: {})
      @phase = phase
      @execution_id = execution_id
      @workflow_name = workflow_name

      user_msg = "Workflow error"
      user_msg += " in #{workflow_name}" if workflow_name
      user_msg += " (#{phase} phase)" if phase
      user_msg += ": #{message}"

      super(
        message,
        user_message: user_msg,
        context: context.merge(phase: phase, execution_id: execution_id, workflow_name: workflow_name).compact
      )
    end
  end

  class WorkflowValidationError < WorkflowError
    def initialize(message, phase: nil, context: {})
      super(
        "Validation failed: #{message}. Please review your input and try again.",
        phase: phase,
        context: context
      )
    end
  end

  class WorkflowTimeoutError < WorkflowError
    def initialize(phase:, timeout_seconds:, context: {})
      super(
        "Workflow phase '#{phase}' exceeded timeout of #{timeout_seconds} seconds. This usually happens with complex operations. Please try again or contact support.",
        phase: phase,
        context: context.merge(timeout_seconds: timeout_seconds)
      )
    end
  end

  # Tool Execution Errors
  class ToolError < BaseError
    attr_reader :tool_name

    def initialize(message, tool_name:, context: {})
      @tool_name = tool_name

      super(
        message,
        user_message: "Error executing #{tool_name}: #{message}",
        context: context.merge(tool: tool_name)
      )
    end
  end

  class ToolNotFoundError < ToolError
    def initialize(tool_name:, context: {})
      super(
        "Tool '#{tool_name}' not found. This may indicate a configuration issue. Please contact support.",
        tool_name: tool_name,
        context: context
      )
    end
  end

  class ToolInvalidArgumentError < ToolError
    def initialize(tool_name:, argument:, reason:, context: {})
      super(
        "Invalid argument '#{argument}': #{reason}. Please check your input and try again.",
        tool_name: tool_name,
        context: context.merge(argument: argument, reason: reason)
      )
    end
  end

  # Campaign Errors
  class CampaignError < BaseError
    attr_reader :campaign_id

    def initialize(message, campaign_id: nil, context: {})
      @campaign_id = campaign_id

      super(
        message,
        user_message: "Campaign error: #{message}",
        context: context.merge(campaign_id: campaign_id).compact
      )
    end
  end

  class CampaignDeliveryError < CampaignError
    def initialize(message, campaign_id: nil, failed_count: 0, context: {})
      super(
        "Failed to deliver to #{failed_count} recipients: #{message}",
        campaign_id: campaign_id,
        context: context.merge(failed_count: failed_count)
      )
    end
  end

  # Landing Page Errors
  class LandingPageError < BaseError
    attr_reader :landing_page_id

    def initialize(message, landing_page_id: nil, context: {})
      @landing_page_id = landing_page_id

      super(
        message,
        user_message: "Landing page error: #{message}",
        context: context.merge(landing_page_id: landing_page_id).compact
      )
    end
  end

  class LandingPageGenerationError < LandingPageError
    def initialize(message, context: {})
      super(
        "Failed to generate landing page: #{message}. Please try again or simplify your requirements.",
        context: context
      )
    end
  end

  # File Upload Errors
  class FileUploadError < BaseError
    attr_reader :filename, :file_type

    def initialize(message, filename: nil, file_type: nil, context: {})
      @filename = filename
      @file_type = file_type

      super(
        message,
        user_message: "File upload error: #{message}",
        context: context.merge(filename: filename, file_type: file_type).compact
      )
    end
  end

  class FileTooBigError < FileUploadError
    def initialize(filename:, size:, max_size:, context: {})
      super(
        "File '#{filename}' (#{size} MB) exceeds maximum size of #{max_size} MB. Please upload a smaller file.",
        filename: filename,
        context: context.merge(size: size, max_size: max_size)
      )
    end
  end

  class UnsupportedFileTypeError < FileUploadError
    def initialize(filename:, file_type:, supported_types:, context: {})
      super(
        "File type '#{file_type}' is not supported. Supported types: #{supported_types.join(', ')}",
        filename: filename,
        file_type: file_type,
        context: context.merge(supported_types: supported_types)
      )
    end
  end

  # Rate Limiting Errors
  class RateLimitError < BaseError
    def initialize(limit:, period:, retry_after:, context: {})
      super(
        "Rate limit of #{limit} requests per #{period} exceeded. Please try again in #{retry_after} seconds.",
        retry_after: retry_after,
        context: context.merge(limit: limit, period: period)
      )
    end
  end

  # Configuration Errors
  class ConfigurationError < BaseError
    def initialize(message, context: {})
      super(
        message,
        user_message: "Configuration error: #{message}. Please contact your administrator.",
        context: context
      )
    end
  end

  class MissingCredentialsError < ConfigurationError
    def initialize(service:, credentials:, context: {})
      super(
        "Missing credentials for #{service}: #{credentials.join(', ')}. Please configure in Settings.",
        context: context.merge(service: service, missing_credentials: credentials)
      )
    end
  end
end
