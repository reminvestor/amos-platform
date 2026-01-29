# frozen_string_literal: true

require "test_helper"

class JupiterSwapServiceTest < ActiveSupport::TestCase
  setup do
    ENV['SOLANA_TOKEN_MINT'] = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU'
  end

  test "has correct token mint addresses" do
    assert_equal 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', 
                 JupiterSwapService::TOKEN_MINTS[:usdc]
    assert_equal 'So11111111111111111111111111111111111111112', 
                 JupiterSwapService::TOKEN_MINTS[:sol]
    assert_equal '3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh', 
                 JupiterSwapService::TOKEN_MINTS[:wbtc]
  end

  test "returns amos mint from environment" do
    assert_equal '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
                 JupiterSwapService.amos_mint
  end

  test "supported_output_tokens returns all token symbols" do
    tokens = JupiterSwapService.supported_output_tokens
    
    assert_includes tokens, :sol
    assert_includes tokens, :usdc
    assert_includes tokens, :usdt
    assert_includes tokens, :wbtc
    assert_includes tokens, :bonk
  end

  test "mint_for returns correct address" do
    assert_equal JupiterSwapService::TOKEN_MINTS[:usdc],
                 JupiterSwapService.mint_for(:usdc)
    assert_equal JupiterSwapService::TOKEN_MINTS[:sol],
                 JupiterSwapService.mint_for('sol')
  end

  test "mint_for raises for unknown token" do
    assert_raises ArgumentError do
      JupiterSwapService.mint_for(:fake_token)
    end
  end

  # Integration tests (require network)
  test "gets quote from Jupiter API" do
    skip "Integration test - requires network" unless ENV['RUN_INTEGRATION_TESTS']
    
    quote = JupiterSwapService.get_quote(
      input_mint: JupiterSwapService::TOKEN_MINTS[:sol],
      output_mint: JupiterSwapService::TOKEN_MINTS[:usdc],
      amount: 1_000_000_000 # 1 SOL
    )

    assert quote[:input_amount] > 0
    assert quote[:output_amount] > 0
    assert quote[:price_impact_pct].is_a?(Float)
  end

  test "quote_amos_to_usdc returns human-readable amounts" do
    skip "Integration test - requires network and AMOS liquidity" unless ENV['RUN_INTEGRATION_TESTS']
    
    quote = JupiterSwapService.quote_amos_to_usdc(1000)
    
    assert_equal 1000, quote[:input_amount_human]
    assert quote[:output_amount_human].is_a?(Float)
    assert quote[:rate].is_a?(Float)
  end

  test "raises InsufficientLiquidityError for no liquidity" do
    skip "Integration test - requires network" unless ENV['RUN_INTEGRATION_TESTS']
    
    # Try to swap a fake token that has no liquidity
    assert_raises JupiterSwapService::InsufficientLiquidityError do
      JupiterSwapService.get_quote(
        input_mint: 'FakeTokenMint11111111111111111111111111111111',
        output_mint: JupiterSwapService::TOKEN_MINTS[:usdc],
        amount: 1_000_000
      )
    end
  end
end
