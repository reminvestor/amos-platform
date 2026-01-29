# frozen_string_literal: true

# TokenDeposit represents tokens deposited from Solana wallet back to platform
#
# Flow:
# 1. User sends tokens to treasury wallet on Solana
# 2. User submits transaction signature to platform (pending)
# 3. Background job verifies transaction on-chain (verified)
# 4. Internal stake is credited (completed)
#
# States: pending -> verified -> completed/failed
class TokenDeposit < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  belongs_to :token_stake, optional: true  # The stake created from this deposit

  STATUSES = %w[pending verified completed failed].freeze

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :wallet_address, presence: true, format: { 
    with: /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/, 
    message: 'must be a valid Solana address' 
  }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :transaction_signature, presence: true, uniqueness: true

  scope :pending, -> { where(status: 'pending') }
  scope :verified, -> { where(status: 'verified') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }

  before_validation :set_entity_from_user, on: :create

  # Verify the transaction on Solana
  def verify!
    raise "Invalid state: #{status}" unless status == 'pending'
    
    # Verification happens in background job via SolanaTokenService
    # This method is called after successful verification
    update!(
      status: 'verified',
      verified: true,
      verified_at: Time.current
    )
  end

  def complete!
    raise "Invalid state: #{status}" unless status == 'verified'
    
    # Create internal stake for deposited tokens
    stake = create_internal_stake!
    
    update!(
      status: 'completed',
      token_stake: stake,
      confirmed_at: Time.current
    )
    
    stake
  end

  def fail!(error_message)
    update!(
      status: 'failed',
      error_message: error_message
    )
  end

  private

  def set_entity_from_user
    self.entity ||= user&.entity
  end

  def create_internal_stake!
    TokenStake.create!(
      user: user,
      entity: entity,
      stake_type: 'community',  # Deposited tokens are community stakes
      category: 'deposit',
      initial_amount: amount,
      current_amount: amount,
      decay_rate: TokenStake.default_decay_rate_for('community'),
      earned_at: Time.current,
      source: self,
      metadata: {
        deposit_id: id,
        wallet_address: wallet_address,
        transaction_signature: transaction_signature
      }
    )
  end
end
