# frozen_string_literal: true

# TokenClaim represents a request to withdraw tokens from platform to Solana wallet
#
# Flow:
# 1. User requests claim (pending)
# 2. System validates sufficient balance (validated)
# 3. Background job sends Solana transaction (processing)
# 4. Transaction confirmed on-chain (completed)
#
# States: pending -> validated -> processing -> completed/failed
class TokenClaim < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true

  # Status workflow
  STATUSES = %w[pending validated processing completed failed cancelled].freeze
  
  # Minimum claim amount (in tokens)
  MINIMUM_CLAIM = 100
  
  # Platform fee percentage (burned)
  PLATFORM_FEE_RATE = 0.01  # 1%

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :wallet_address, presence: true, format: { 
    with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/, 
    message: 'must be a valid Solana address' 
  }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :transaction_signature, uniqueness: true, allow_nil: true

  scope :pending, -> { where(status: 'pending') }
  scope :processing, -> { where(status: 'processing') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }
  scope :retryable, -> { failed.where('retry_count < 3') }

  before_validation :set_entity_from_user, on: :create
  before_validation :calculate_fees, on: :create

  # State machine methods
  def validate_claim!
    raise "Invalid state: #{status}" unless status == 'pending'
    
    # Check user has sufficient claimable balance
    claimable = user_claimable_balance
    if amount > claimable
      update!(status: 'failed', error_message: "Insufficient balance. Claimable: #{claimable}, Requested: #{amount}")
      return false
    end
    
    if amount < MINIMUM_CLAIM
      update!(status: 'failed', error_message: "Minimum claim is #{MINIMUM_CLAIM} tokens")
      return false
    end
    
    update!(status: 'validated')
    true
  end

  def start_processing!
    raise "Invalid state: #{status}" unless status == 'validated'
    update!(status: 'processing')
  end

  def complete!(transaction_signature:, blockhash: nil, slot: nil)
    raise "Invalid state: #{status}" unless status == 'processing'
    
    update!(
      status: 'completed',
      transaction_signature: transaction_signature,
      blockhash: blockhash,
      slot: slot,
      confirmed_at: Time.current
    )
    
    # Deduct from internal balance
    deduct_from_internal_balance!
    
    # Record transaction
    record_claim_transaction!
  end

  def fail!(error_message)
    update!(
      status: 'failed',
      error_message: error_message,
      retry_count: retry_count + 1,
      last_retry_at: Time.current
    )
  end

  def cancel!
    raise "Cannot cancel completed claim" if status == 'completed'
    update!(status: 'cancelled')
  end

  def retryable?
    status == 'failed' && retry_count < 3
  end

  def retry!
    raise "Claim not retryable" unless retryable?
    update!(status: 'pending', error_message: nil)
    validate_claim!
  end

  # Amount after fees
  def net_amount
    amount - total_fees
  end

  def total_fees
    (platform_fee || 0) + (network_fee || 0)
  end

  private

  def set_entity_from_user
    self.entity ||= user&.entity
  end

  def calculate_fees
    self.platform_fee = (amount * PLATFORM_FEE_RATE).round(9)
    self.network_fee ||= 0.000005  # ~5000 lamports, typical Solana tx fee
  end

  def user_claimable_balance
    # Sum of all active stakes minus pending/processing claims
    active_stakes = TokenStake.for_user(user).active.sum(:current_amount)
    pending_claims = TokenClaim.for_user(user).where(status: %w[pending validated processing]).sum(:amount)
    [active_stakes - pending_claims, 0].max
  end

  def deduct_from_internal_balance!
    # Deduct from oldest stakes first (FIFO)
    remaining_to_deduct = amount
    
    TokenStake.for_user(user).active.order(earned_at: :asc).each do |stake|
      break if remaining_to_deduct <= 0
      
      deduction = [stake.current_amount, remaining_to_deduct].min
      stake.update!(current_amount: stake.current_amount - deduction)
      remaining_to_deduct -= deduction
    end
  end

  def record_claim_transaction!
    # Find affected stakes and record transaction
    TokenStakeTransaction.create!(
      token_stake: user.token_stakes.active.first, # Associate with first active stake
      user: user,
      transaction_type: 'withdrawal',
      amount: -amount,
      balance_before: user.token_stakes.sum(:current_amount) + amount,
      balance_after: user.token_stakes.sum(:current_amount),
      description: "Claimed #{amount} tokens to Solana wallet #{wallet_address[0..8]}...",
      metadata: {
        claim_id: id,
        wallet_address: wallet_address,
        transaction_signature: transaction_signature,
        platform_fee: platform_fee,
        network_fee: network_fee
      }
    )
  end
end
