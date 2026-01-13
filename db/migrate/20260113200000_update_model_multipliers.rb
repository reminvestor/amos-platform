# frozen_string_literal: true

# Update model multipliers to reflect accurate AWS Bedrock pricing (Jan 2026)
# Using Qwen 3 32B as 1.0x baseline since it's our default model
#
# Pricing per 1M tokens:
# - Nemotron Nano 2: $0.06 in, $0.23 out → avg $0.145 → 0.4x
# - Qwen 3 32B: $0.15 in, $0.60 out → avg $0.375 → 1.0x (baseline)
# - Mistral Large 3: $0.50 in, $1.50 out → avg $1.00 → 2.7x
# - DeepSeek V3.1: $0.58 in, $1.68 out → avg $1.13 → 3.0x
# - DeepSeek R1: $1.35 in, $5.40 out → avg $3.375 → 9.0x
# - Claude Haiku 4.5: $1.00 in, $5.00 out → avg $3.00 → 8.0x
# - Claude Opus 4.5: $5.00 in, $25.00 out → avg $15.00 → 40.0x
# - Claude Sonnet 4.5: $3.00 in, $15.00 out → avg $9.00 → 24.0x
class UpdateModelMultipliers < ActiveRecord::Migration[7.0]
  def up
    new_multipliers = {
      # Our current default and tool-use model
      'qwen-3-32b' => 1.0,
      
      # Ultra-cheap classification model
      'nemotron-nano-2' => 0.4,
      
      # Previous default, still used for some tool tasks
      'mistral-large-3' => 2.7,
      
      # DeepSeek models
      'deepseek-v3' => 3.0,
      'deepseek-r1' => 9.0,
      
      # Claude models (for reference)
      'claude-haiku-4-5' => 8.0,
      'claude-sonnet-4-5' => 24.0,
      'claude-opus-4-5' => 40.0,
      
      # Legacy Claude models (keep for backwards compatibility)
      'claude-3-5-haiku' => 2.0,
      'claude-3-5-sonnet' => 24.0,
      'claude-3-haiku' => 0.5,
      'claude-3-opus' => 40.0,
      
      # GPT models (for reference if ever used)
      'gpt-4' => 30.0,
      'gpt-4o' => 15.0
    }

    BillingConfiguration.find_each do |config|
      config.update!(model_multipliers: new_multipliers)
    end
  end

  def down
    # Restore previous multipliers
    old_multipliers = {
      'gpt-4' => 2.0,
      'gpt-4o' => 0.8,
      'claude-3-opus' => 3.0,
      'claude-3-haiku' => 0.1,
      'claude-3-5-haiku' => 0.15,
      'claude-3-5-sonnet' => 1.0,
      'claude-4-5-sonnet' => 1.0,
      'claude-sonnet-4-5' => 1.0
    }

    BillingConfiguration.find_each do |config|
      config.update!(model_multipliers: old_multipliers)
    end
  end
end

