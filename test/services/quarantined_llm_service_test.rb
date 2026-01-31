# frozen_string_literal: true

require "test_helper"

class QuarantinedLlmServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:one)
  end

  test "enabled? returns false by default" do
    service = QuarantinedLlmService.new(entity: @entity)
    assert_not service.enabled?
  end

  test "enabled? returns true when entity has feature enabled" do
    # Enable Q-LLM for this entity (if column exists)
    if @entity.respond_to?(:quarantine_llm_enabled=)
      @entity.update!(quarantine_llm_enabled: true)
      service = QuarantinedLlmService.new(entity: @entity)
      assert service.enabled?
      
      # Clean up
      @entity.update!(quarantine_llm_enabled: false)
    else
      skip "Entity doesn't have quarantine_llm_enabled column (run migration first)"
    end
  end

  test "extract returns skipped result when disabled" do
    service = QuarantinedLlmService.new(entity: @entity)
    
    result = service.extract(
      content: "Test email content",
      instruction: "Extract sender email"
    )
    
    assert result[:success]
    assert result[:skipped]
    assert_equal "Q-LLM disabled for entity", result[:reason]
  end

  test "retrieve returns nil for invalid reference" do
    service = QuarantinedLlmService.new(entity: @entity)
    
    assert_nil service.retrieve("invalid")
    assert_nil service.retrieve("$extracted_nonexistent")
  end

  test "retrieve returns stored extraction" do
    # Use a memory store for this test
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    
    # Manually store an extraction
    reference_id = SecureRandom.hex(8)
    cache_key = "qllm_extraction:#{@entity.id}:#{reference_id}"
    
    tagged_data = {
      _tagged: true,
      value: { email: "test@example.com" },
      source: :extracted,
      trust_level: :derived
    }
    
    Rails.cache.write(cache_key, tagged_data, expires_in: 1.hour)
    
    service = QuarantinedLlmService.new(entity: @entity)
    result = service.retrieve("$extracted_#{reference_id}")
    
    assert_equal tagged_data, result
  ensure
    Rails.cache = original_cache
  end

  # Integration test - requires Bedrock to be available
  # Skip this in CI environments without AWS access
  test "extract performs LLM extraction when enabled" do
    skip "Requires Q-LLM enabled and Bedrock access" unless can_test_llm?
    
    @entity.update!(quarantine_llm_enabled: true)
    service = QuarantinedLlmService.new(entity: @entity, user: @user)
    
    email_content = <<~EMAIL
      From: alice@example.com
      To: bob@example.com
      Subject: Meeting Tomorrow
      
      Hi Bob,
      
      Let's meet tomorrow at 3pm.
      
      Best,
      Alice
    EMAIL
    
    result = service.extract(
      content: email_content,
      instruction: "Extract the sender email address and meeting time",
      schema: { sender_email: :string, meeting_time: :string }
    )
    
    assert result[:success]
    assert result[:reference].start_with?("$extracted_")
    assert result[:tagged].present?
    assert_equal :derived, result[:tagged][:trust_level]
    
    @entity.update!(quarantine_llm_enabled: false)
  end

  private

  def can_test_llm?
    return false unless @entity.respond_to?(:quarantine_llm_enabled=)
    
    # Check if we have AWS credentials
    ENV['AWS_ACCESS_KEY_ID'].present? || ENV['AWS_PROFILE'].present?
  rescue
    false
  end
end
