# frozen_string_literal: true

require "test_helper"

class SolanaTokenServiceTest < ActiveSupport::TestCase
  # Valid Solana addresses for testing (real devnet addresses)
  VALID_ADDRESS = 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
  TREASURY_ADDRESS = '11111111111111111111111111111111' # System program (32 1s)
  TOKEN_MINT = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU'

  setup do
    ENV['SOLANA_RPC_URL'] = 'https://api.devnet.solana.com'
    ENV['SOLANA_TREASURY_ADDRESS'] = TREASURY_ADDRESS
    ENV['SOLANA_TOKEN_MINT'] = TOKEN_MINT
  end

  # === ADDRESS VALIDATION ===

  test "validates correct Solana addresses" do
    assert SolanaTokenService.valid_address?(VALID_ADDRESS)
    assert SolanaTokenService.valid_address?('11111111111111111111111111111111')
  end

  test "rejects invalid Solana addresses" do
    assert_not SolanaTokenService.valid_address?('invalid')
    assert_not SolanaTokenService.valid_address?('0x123') # Ethereum style
    assert_not SolanaTokenService.valid_address?('')
    assert_not SolanaTokenService.valid_address?(nil)
    assert_not SolanaTokenService.valid_address?('O0Il') # Contains invalid chars
  end

  test "validate_address! raises for invalid address" do
    assert_raises SolanaTokenService::InvalidAddressError do
      SolanaTokenService.validate_address!('invalid')
    end
  end

  # === CONFIGURATION ===

  test "returns correct RPC URL" do
    assert_equal 'https://api.devnet.solana.com', SolanaTokenService.rpc_url
  end

  test "detects devnet correctly" do
    assert SolanaTokenService.devnet?
    assert_not SolanaTokenService.mainnet?
  end

  test "detects mainnet correctly" do
    ENV['SOLANA_RPC_URL'] = 'https://api.mainnet-beta.solana.com'
    assert SolanaTokenService.mainnet?
    assert_not SolanaTokenService.devnet?
  end

  # === VERIFICATION MESSAGE ===

  test "generates verification message with user ID" do
    result = SolanaTokenService.generate_verification_message(123)
    
    assert result[:message].include?('User ID: 123')
    assert result[:message].include?('Verify AMOS wallet ownership')
    assert result[:nonce].present?
    assert result[:timestamp].present?
  end

  test "generates unique nonce each time" do
    result1 = SolanaTokenService.generate_verification_message(123)
    result2 = SolanaTokenService.generate_verification_message(123)
    
    assert_not_equal result1[:nonce], result2[:nonce]
  end

  # === PUBLIC STATS ===

  test "returns public stats" do
    skip "Integration test - requires network" unless ENV['RUN_INTEGRATION_TESTS']
    
    stats = SolanaTokenService.public_stats
    
    assert_equal 'devnet', stats[:network]
    assert stats.key?(:treasury_address)
    assert stats.key?(:token_mint)
    assert stats.key?(:total_claimed)
    assert stats.key?(:total_deposited)
    assert stats.key?(:pending_claims)
  end

  # === TRANSACTION SIMULATION (Devnet) ===

  test "simulates transfer on devnet" do
    skip "Integration test - requires network" unless ENV['RUN_INTEGRATION_TESTS']
    
    signature = SolanaTokenService.send_tokens(
      to_address: VALID_ADDRESS,
      amount: 100,
      claim_id: 1
    )
    
    assert signature.present?
    assert signature.start_with?('sim_') # Simulated on devnet
  end

  # === ERROR HANDLING ===

  test "raises InsufficientFundsError for negative amount" do
    assert_raises SolanaTokenService::InsufficientFundsError do
      SolanaTokenService.send_tokens(
        to_address: VALID_ADDRESS,
        amount: -100
      )
    end
  end

  test "raises InvalidAddressError for bad address in send_tokens" do
    assert_raises SolanaTokenService::InvalidAddressError do
      SolanaTokenService.send_tokens(
        to_address: 'invalid',
        amount: 100
      )
    end
  end

  # === DEPOSIT VERIFICATION ===

  test "raises VerificationFailedError for non-existent transaction" do
    skip "Integration test - requires network" unless ENV['RUN_INTEGRATION_TESTS']
    
    assert_raises SolanaTokenService::VerificationFailedError do
      SolanaTokenService.verify_deposit(
        transaction_signature: 'nonexistent_sig',
        expected_amount: 100,
        expected_from: VALID_ADDRESS
      )
    end
  end
end
