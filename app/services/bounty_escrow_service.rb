# frozen_string_literal: true

# BountyEscrowService - Manages token escrow for user-funded bounties
#
# When a user creates a bounty funded from their AMOS token balance:
# 1. ESCROW: Tokens are deducted from user's stake and held
# 2. RELEASE: If approved, tokens go to the claimant as a new stake
# 3. REFUND: If cancelled/rejected/expired, tokens return to funder
#
# This ensures users can't spend tokens they've committed to bounties.
#
class BountyEscrowService
  class EscrowError < StandardError; end
  class InsufficientBalanceError < EscrowError; end
  class InvalidStateError < EscrowError; end

  class << self
    # Escrow tokens when bounty is created
    # Deducts from user's active stakes
    def escrow!(bounty:, user:, amount:)
      Rails.logger.info "[ESCROW] Escrowing #{amount} tokens for bounty #{bounty.id} from user #{user.id}"

      # Verify sufficient balance
      available_balance = TokenStake.for_user(user).active.sum(:current_amount)
      if available_balance < amount
        raise InsufficientBalanceError, "Insufficient AMOS balance (have: #{available_balance.round(2)}, need: #{amount})"
      end

      transaction_id = "escrow_bounty_#{bounty.id}_#{Time.current.to_i}"

      ActiveRecord::Base.transaction do
        # Deduct from user's stakes (proportionally from active stakes)
        remaining = amount
        TokenStake.for_user(user).active.order(current_amount: :desc).each do |stake|
          break if remaining <= 0
          
          deduct = [stake.current_amount, remaining].min
          stake.update!(current_amount: stake.current_amount - deduct)
          
          # Record transaction
          TokenStakeTransaction.create!(
            token_stake: stake,
            user: user,
            transaction_type: 'escrow',
            amount: -deduct,
            balance_before: stake.current_amount + deduct,
            balance_after: stake.current_amount,
            description: "Escrowed for bounty: #{bounty.title}",
            metadata: {
              bounty_id: bounty.id,
              escrow_transaction_id: transaction_id
            }
          )
          
          remaining -= deduct
        end

        # Update bounty with escrow info
        bounty.update!(
          escrow_status: 'escrowed',
          escrow_transaction_id: transaction_id
        )
      end

      Rails.logger.info "[ESCROW] Successfully escrowed #{amount} tokens (txn: #{transaction_id})"
      transaction_id
    end

    # Release escrowed tokens to the claimant
    # Creates a new stake for the recipient
    def release!(bounty:, recipient:, amount:)
      Rails.logger.info "[ESCROW] Releasing #{amount} tokens from bounty #{bounty.id} to user #{recipient.id}"

      unless bounty.escrow_status == 'escrowed'
        raise InvalidStateError, "Bounty escrow is not in 'escrowed' state (current: #{bounty.escrow_status})"
      end

      ActiveRecord::Base.transaction do
        # Create a new stake for the recipient
        stake = TokenStake.create!(
          user: recipient,
          entity: bounty.entity,
          stake_type: 'contribution',
          initial_amount: amount,
          current_amount: amount,
          category: 'bounty_reward',
          source: bounty,
          metadata: {
            bounty_id: bounty.id,
            bounty_title: bounty.title,
            funded_by: bounty.funded_by_id
          }
        )

        # Record earn transaction
        TokenStakeTransaction.create!(
          token_stake: stake,
          user: recipient,
          transaction_type: 'earn',
          amount: amount,
          balance_before: 0,
          balance_after: amount,
          description: "Earned from user-funded bounty: #{bounty.title}",
          metadata: {
            bounty_id: bounty.id,
            source: 'user_funded_bounty',
            funded_by: bounty.funded_by_id
          }
        )

        bounty.update!(escrow_status: 'released')
      end

      Rails.logger.info "[ESCROW] Released #{amount} tokens to #{recipient.email}"
      true
    end

    # Refund escrowed tokens to the original funder
    # Returns tokens to funder's stakes
    def refund!(bounty:, user:, amount:)
      Rails.logger.info "[ESCROW] Refunding #{amount} tokens from bounty #{bounty.id} to user #{user.id}"

      unless bounty.escrow_status == 'escrowed'
        raise InvalidStateError, "Bounty escrow is not in 'escrowed' state (current: #{bounty.escrow_status})"
      end

      ActiveRecord::Base.transaction do
        # Create a new stake for the refund (or add to existing)
        stake = TokenStake.for_user(user).active.first || TokenStake.create!(
          user: user,
          entity: bounty.entity,
          stake_type: 'contribution',
          initial_amount: 0,
          current_amount: 0,
          category: 'refund'
        )

        stake.update!(
          current_amount: stake.current_amount + amount,
          initial_amount: stake.initial_amount + amount
        )

        # Record refund transaction
        TokenStakeTransaction.create!(
          token_stake: stake,
          user: user,
          transaction_type: 'refund',
          amount: amount,
          balance_before: stake.current_amount - amount,
          balance_after: stake.current_amount,
          description: "Refunded from cancelled/rejected bounty: #{bounty.title}",
          metadata: {
            bounty_id: bounty.id,
            reason: bounty.status,
            original_escrow_txn: bounty.escrow_transaction_id
          }
        )

        bounty.update!(escrow_status: 'refunded')
      end

      Rails.logger.info "[ESCROW] Refunded #{amount} tokens to #{user.email}"
      true
    end

    # Get escrow balance for a user (tokens locked in bounties)
    def escrowed_balance(user)
      Bounty.where(funded_by: user)
            .where(escrow_status: 'escrowed')
            .sum(:funded_amount)
    end

    # Get available balance (total stake minus escrowed)
    def available_balance(user)
      total_stake = TokenStake.for_user(user).active.sum(:current_amount)
      escrowed = escrowed_balance(user)
      total_stake - escrowed
    end
  end
end
