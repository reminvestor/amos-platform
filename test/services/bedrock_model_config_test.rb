# frozen_string_literal: true

require 'test_helper'

class BedrockModelConfigTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════════════
  # OPUS 4.6 CONFIGURATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "opus 4.6 model config exists" do
    config = BedrockService::MODELS['claude-opus-4-6']
    assert config.present?, "claude-opus-4-6 should be in MODELS"
  end

  test "opus 4.6 has correct model ID" do
    config = BedrockService::MODELS['claude-opus-4-6']
    assert_equal 'anthropic.claude-opus-4-6-v1', config[:id]
  end

  test "opus 4.6 has same pricing as opus 4.5" do
    opus_45 = BedrockService::MODELS['claude-opus-4-5']
    opus_46 = BedrockService::MODELS['claude-opus-4-6']

    assert_equal opus_45[:cost_per_1m_input], opus_46[:cost_per_1m_input], "Input cost should match Opus 4.5"
    assert_equal opus_45[:cost_per_1m_output], opus_46[:cost_per_1m_output], "Output cost should match Opus 4.5"
  end

  test "opus 4.6 supports vision" do
    config = BedrockService::MODELS['claude-opus-4-6']
    assert config[:supports_vision], "Opus 4.6 should support vision"
  end

  test "opus 4.6 supports tools" do
    config = BedrockService::MODELS['claude-opus-4-6']
    assert config[:supports_tools], "Opus 4.6 should support tools"
  end

  test "opus 4.6 has 30000 max tokens" do
    config = BedrockService::MODELS['claude-opus-4-6']
    assert_equal 30000, config[:max_tokens]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FALLBACK CHAIN
  # ═══════════════════════════════════════════════════════════════════════════

  test "fallback chain includes opus 4.6 as last resort" do
    chain = BedrockService::FALLBACK_CHAIN
    assert_includes chain, 'claude-opus-4-6'
    assert_equal 'claude-opus-4-6', chain.last, "Opus 4.6 should be the last fallback"
  end

  test "fallback chain has opus 4.5 before 4.6" do
    chain = BedrockService::FALLBACK_CHAIN
    idx_45 = chain.index('claude-opus-4-5')
    idx_46 = chain.index('claude-opus-4-6')
    assert idx_45 < idx_46, "Opus 4.5 should come before 4.6 in fallback chain"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTEXT WINDOW
  # ═══════════════════════════════════════════════════════════════════════════

  test "opus 4.6 has 200K context window" do
    entry = BedrockService::CONTEXT_WINDOW_MODELS.find { |m| m[:key] == 'claude-opus-4-6' }
    assert entry.present?, "Opus 4.6 should be in CONTEXT_WINDOW_MODELS"
    assert_equal 200_000, entry[:context]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # BILLING CONFIGURATION
  # ═══════════════════════════════════════════════════════════════════════════

  test "billing config has opus 4.6 pricing" do
    pricing = BillingConfiguration::MODEL_PRICING_PER_MILLION
    assert pricing.key?('claude-opus-4-6'), "BillingConfiguration should have opus 4.6 pricing"
    assert_equal 5.00, pricing['claude-opus-4-6'][:input]
    assert_equal 25.00, pricing['claude-opus-4-6'][:output]
  end

  test "billing config has opus 4.6 by bedrock model ID" do
    pricing = BillingConfiguration::MODEL_PRICING_PER_MILLION
    assert pricing.key?('anthropic.claude-opus-4-6-v1'), "Should have pricing by Bedrock model ID"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ALL MODELS HAVE REQUIRED FIELDS
  # ═══════════════════════════════════════════════════════════════════════════

  test "all models have required configuration fields" do
    required_fields = [:id, :name, :max_tokens, :supports_tools]

    BedrockService::MODELS.each do |key, config|
      required_fields.each do |field|
        assert config.key?(field), "Model '#{key}' missing required field: #{field}"
      end
    end
  end

  test "all models have cost fields" do
    BedrockService::MODELS.each do |key, config|
      assert config.key?(:cost_per_1m_input), "Model '#{key}' missing cost_per_1m_input"
      assert config.key?(:cost_per_1m_output), "Model '#{key}' missing cost_per_1m_output"
    end
  end
end
