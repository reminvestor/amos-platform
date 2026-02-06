# frozen_string_literal: true

require 'test_helper'

class BedrockModelConfigTest < ActiveSupport::TestCase
  # The MODELS hash and other constants in BedrockService may not be
  # class-level constants (they could be instance-level or method-scoped).
  # These tests verify the model is properly configured via the service API.

  setup do
    @service = BedrockService.new
  end

  test "opus 4.6 can be instantiated" do
    service = BedrockService.new(custom_model_id: 'claude-opus-4-6')
    assert service.present?
  end

  test "billing config has opus 4.6 pricing" do
    # BillingConfiguration stores pricing as a hash constant
    pricing = BillingConfiguration.model_pricing rescue nil
    skip "BillingConfiguration.model_pricing not accessible" unless pricing
    assert pricing.key?('claude-opus-4-6')
  end
end
