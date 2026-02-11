# frozen_string_literal: true

require "test_helper"

class QuarantinedLlmServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:one)
  end

  test "enabled? is always true — CAMEL is a security layer not a user feature" do
    service = QuarantinedLlmService.new(entity: @entity)
    assert service.enabled?
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
  test "extract performs LLM extraction" do
    skip "Requires Bedrock access" unless can_test_llm?
    
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
  end

  private

  def can_test_llm?
    # Check if we have AWS credentials
    ENV['AWS_ACCESS_KEY_ID'].present? || ENV['AWS_PROFILE'].present?
  rescue
    false
  end
end
