# frozen_string_literal: true

# Concern to add work token tracking to services
# Include this in any service that should track usage for billing
module WorkTokenTrackable
  extend ActiveSupport::Concern

  included do
    attr_accessor :work_token_service
  end

  # Track AI token usage for billing
  def track_ai_work_tokens(input_tokens:, output_tokens:, model:, source: nil, metadata: {})
    return unless should_track_work_tokens?
    
    service = get_work_token_service
    return unless service
    
    result = service.track_ai_usage(
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model: model,
      source: source,
      metadata: metadata
    )
    
    if result[:success]
      Rails.logger.debug "💰 Work tokens charged: #{result[:tokens_charged]} for AI usage (#{model})"
    else
      Rails.logger.warn "⚠️ Work token charge failed: #{result[:message]}"
      # Don't block the request, but log the failure
    end
    
    result
  rescue => e
    Rails.logger.error "Error tracking work tokens: #{e.message}"
    { success: false, error: e.message }
  end

  # Track email sending for billing
  def track_email_work_tokens(email_count:, source: nil, metadata: {})
    return unless should_track_work_tokens?
    
    service = get_work_token_service
    return unless service
    
    result = service.track_email_usage(
      email_count: email_count,
      source: source,
      metadata: metadata
    )
    
    if result[:success]
      Rails.logger.debug "💰 Work tokens charged: #{result[:tokens_charged]} for #{email_count} email(s)"
    end
    
    result
  rescue => e
    Rails.logger.error "Error tracking work tokens for email: #{e.message}"
    { success: false, error: e.message }
  end

  # Track other AWS compute for billing
  def track_compute_work_tokens(cost_cents:, service_type:, description: nil, source: nil, metadata: {})
    return unless should_track_work_tokens?
    
    service = get_work_token_service
    return unless service
    
    result = service.track_other_compute(
      cost_cents: cost_cents,
      service_type: service_type,
      description: description,
      source: source,
      metadata: metadata
    )
    
    if result[:success]
      Rails.logger.debug "💰 Work tokens charged: #{result[:tokens_charged]} for #{service_type}"
    end
    
    result
  rescue => e
    Rails.logger.error "Error tracking work tokens for compute: #{e.message}"
    { success: false, error: e.message }
  end

  # Check if user has sufficient balance before expensive operations
  def check_work_token_balance(estimated_tokens = 1000)
    return true unless should_track_work_tokens?
    
    service = get_work_token_service
    return true unless service
    
    service.has_balance?(estimated_tokens)
  end

  private

  def should_track_work_tokens?
    # Only track if we have a user (entity is optional)
    @user.present?
  end

  def get_work_token_service
    return @work_token_service if @work_token_service
    return nil unless @user
    
    @work_token_service = WorkTokenService.new(user: @user, entity: @entity)
  end
end

