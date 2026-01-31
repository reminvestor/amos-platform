# frozen_string_literal: true

require "test_helper"

class TokenClaimTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
    
    # Create some stakes for the user
    @stake = TokenStake.create!(
      user: @user,
      entity: @entity,
      stake_type: 'distribution',
      category: 'affiliate_sale',
      initial_amount: 10000,
      current_amount: 10000,
      decay_rate: 0.40,
      earned_at: Time.current
    )
  end

  test "creates claim with valid attributes" do
    claim = TokenClaim.new(
      user: @user,
      amount: 1000,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert claim.valid?, "Claim should be valid: #{claim.errors.full_messages.join(', ')}"
    assert_equal 'pending', claim.status
  end

  test "validates wallet address format" do
    claim = TokenClaim.new(
      user: @user,
      amount: 1000,
      wallet_address: 'invalid-address'
    )
    
    assert_not claim.valid?
    assert_includes claim.errors[:wallet_address], 'must be a valid Solana address'
  end

  test "validates amount is positive" do
    claim = TokenClaim.new(
      user: @user,
      amount: -100,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert_not claim.valid?
    assert claim.errors[:amount].any?
  end

  test "calculates fees correctly" do
    claim = TokenClaim.create!(
      user: @user,
      amount: 1000,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert_equal 10.0, claim.platform_fee # 1% of 1000
    assert claim.network_fee > 0
    assert_equal 1000 - 10.0 - claim.network_fee, claim.net_amount
  end

  test "validate_claim! succeeds with sufficient balance" do
    claim = TokenClaim.create!(
      user: @user,
      amount: 5000,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert claim.validate_claim!
    assert_equal 'validated', claim.status
  end

  test "validate_claim! fails with insufficient balance" do
    claim = TokenClaim.create!(
      user: @user,
      amount: 50000, # More than stake
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert_not claim.validate_claim!
    assert_equal 'failed', claim.status
    assert claim.error_message.include?('Insufficient balance')
  end

  test "validate_claim! fails below minimum" do
    claim = TokenClaim.create!(
      user: @user,
      amount: 50, # Below minimum
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert_not claim.validate_claim!
    assert_equal 'failed', claim.status
    assert claim.error_message.include?('Minimum claim')
  end

  test "complete! deducts from internal balance" do
    claim = TokenClaim.create!(
      user: @user,
      amount: 1000,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    claim.validate_claim!
    claim.start_processing!
    
    initial_balance = @stake.current_amount
    
    claim.complete!(
      transaction_signature: 'test_sig_123',
      blockhash: 'test_blockhash',
      slot: 12345
    )
    
    @stake.reload
    assert_equal initial_balance - 1000, @stake.current_amount
    assert_equal 'completed', claim.status
    assert_not_nil claim.confirmed_at
  end

  test "retryable? returns correct status" do
    claim = TokenClaim.create!(
      user: @user,
      amount: 1000,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert_not claim.retryable?
    
    claim.update!(status: 'failed', retry_count: 1)
    assert claim.retryable?
    
    claim.update!(retry_count: 3)
    assert_not claim.retryable?
  end

  test "pending claims reduce claimable balance" do
    # First claim
    claim1 = TokenClaim.create!(
      user: @user,
      amount: 3000,
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK',
      status: 'processing'
    )
    
    # Second claim should fail if it would exceed available
    claim2 = TokenClaim.create!(
      user: @user,
      amount: 8000, # 3000 pending + 8000 > 10000
      wallet_address: 'DYw8jCTfwHNRJhhmFcbXvVDTqWMEVFBX6ZKUmG5CNSKK'
    )
    
    assert_not claim2.validate_claim!
    assert_equal 'failed', claim2.status
  end
end
