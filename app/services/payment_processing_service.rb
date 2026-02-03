# frozen_string_literal: true

# PaymentProcessingService
#
# Handles all payment methods for the AMOS platform:
# - Stripe (credit card) → USD → Circle → USDC → On-chain treasury
# - USDC direct (Solana wallet) → On-chain treasury
# - AMOS direct (Solana wallet) → 50% burn, rest to treasury
#
# The key insight: NO MATTER HOW THE USER PAYS, money flows to the
# on-chain treasury with the same immutable split.
#
# Payment discounts:
# - Credit card: 0% (base price)
# - USDC direct: 5% discount (skip Stripe fees)
# - AMOS direct: 15% discount (creates buy pressure + burn)
#
class PaymentProcessingService
  # Discount percentages for crypto payments
  USDC_DISCOUNT_PERCENT = 5
  AMOS_DISCOUNT_PERCENT = 15

  # Minimum amounts for crypto payments
  MIN_USDC_PAYMENT = 10
  MIN_AMOS_PAYMENT = 100

  class << self
    # Process a credit card payment (default flow)
    # @param user [User] The user making the payment
    # @param amount_usd [Numeric] Amount in USD
    # @param stripe_payment_intent [String] Stripe payment intent ID
    # @return [Hash] Payment result
    def process_card_payment(user:, amount_usd:, stripe_payment_intent:)
      # Calculate revenue (20% markup is assumed already included in amount)
      revenue_amount = amount_usd * 0.20 / 1.20 # Extract markup from total

      # Convert to USDC via Circle
      circle_result = convert_to_usdc(amount_usd: revenue_amount)
      return { success: false, error: circle_result[:error] } unless circle_result[:success]

      # Send to on-chain treasury
      treasury_result = send_to_treasury(
        amount_usdc: circle_result[:usdc_amount],
        payment_reference: "stripe:#{stripe_payment_intent}",
        payment_type: :usdc
      )

      record_payment(
        user: user,
        amount_usd: amount_usd,
        payment_method: 'card',
        payment_reference: stripe_payment_intent,
        treasury_result: treasury_result
      )

      {
        success: true,
        payment_method: 'card',
        amount_usd: amount_usd,
        revenue_portion: revenue_amount,
        on_chain_tx: treasury_result[:tx_signature]
      }
    end

    # Process a USDC direct payment (5% discount)
    # @param user [User] The user making the payment
    # @param amount_usdc [Numeric] Amount in USDC
    # @param tx_signature [String] Solana transaction signature
    # @return [Hash] Payment result
    def process_usdc_payment(user:, amount_usdc:, tx_signature:)
      return { success: false, error: 'Amount below minimum' } if amount_usdc < MIN_USDC_PAYMENT

      # Verify the on-chain transaction
      verified = verify_usdc_deposit(tx_signature: tx_signature, expected_amount: amount_usdc)
      return { success: false, error: 'Transaction verification failed' } unless verified

      # Calculate the equivalent USD value (with discount applied)
      # If they paid 95 USDC, that's equivalent to $100 of service
      equivalent_usd = amount_usdc / (1 - USDC_DISCOUNT_PERCENT / 100.0)

      # Send to on-chain treasury
      treasury_result = send_to_treasury(
        amount_usdc: amount_usdc,
        payment_reference: "usdc:#{tx_signature}",
        payment_type: :usdc
      )

      record_payment(
        user: user,
        amount_usd: equivalent_usd,
        payment_method: 'usdc',
        payment_reference: tx_signature,
        treasury_result: treasury_result
      )

      {
        success: true,
        payment_method: 'usdc',
        amount_usdc: amount_usdc,
        equivalent_usd: equivalent_usd,
        discount_applied: "#{USDC_DISCOUNT_PERCENT}%",
        on_chain_tx: treasury_result[:tx_signature]
      }
    end

    # Process an AMOS direct payment (15% discount)
    # @param user [User] The user making the payment
    # @param amount_amos [Numeric] Amount in AMOS tokens
    # @param tx_signature [String] Solana transaction signature
    # @return [Hash] Payment result
    def process_amos_payment(user:, amount_amos:, tx_signature:)
      return { success: false, error: 'Amount below minimum' } if amount_amos < MIN_AMOS_PAYMENT

      # Verify the on-chain transaction
      verified = verify_amos_deposit(tx_signature: tx_signature, expected_amount: amount_amos)
      return { success: false, error: 'Transaction verification failed' } unless verified

      # Calculate the equivalent USD value
      token_price = ContributionRewardCalculator.current_token_price
      equivalent_usd = (amount_amos * token_price) / (1 - AMOS_DISCOUNT_PERCENT / 100.0)

      # AMOS payments go through the special AMOS handler which BURNS 50%
      treasury_result = send_amos_to_treasury(
        amount_amos: amount_amos,
        payment_reference: "amos:#{tx_signature}"
      )

      record_payment(
        user: user,
        amount_usd: equivalent_usd,
        payment_method: 'amos',
        payment_reference: tx_signature,
        treasury_result: treasury_result
      )

      {
        success: true,
        payment_method: 'amos',
        amount_amos: amount_amos,
        tokens_burned: amount_amos * 0.5,
        equivalent_usd: equivalent_usd,
        discount_applied: "#{AMOS_DISCOUNT_PERCENT}%",
        on_chain_tx: treasury_result[:tx_signature]
      }
    end

    # Calculate price for each payment method
    # @param base_price_usd [Numeric] The base USD price
    # @return [Hash] Prices for each payment method
    def calculate_prices(base_price_usd:)
      token_price = ContributionRewardCalculator.current_token_price

      usdc_price = base_price_usd * (1 - USDC_DISCOUNT_PERCENT / 100.0)
      amos_usd_equivalent = base_price_usd * (1 - AMOS_DISCOUNT_PERCENT / 100.0)
      amos_price = amos_usd_equivalent / token_price

      {
        usd: {
          amount: base_price_usd.round(2),
          currency: 'USD',
          discount: 0,
          note: 'Pay with credit card'
        },
        usdc: {
          amount: usdc_price.round(2),
          currency: 'USDC',
          discount: USDC_DISCOUNT_PERCENT,
          note: 'Pay with USDC from Solana wallet'
        },
        amos: {
          amount: amos_price.round(0),
          currency: 'AMOS',
          discount: AMOS_DISCOUNT_PERCENT,
          note: '50% of payment is burned - deflationary!'
        }
      }
    end

    private

    # Convert USD to USDC via Circle
    def convert_to_usdc(amount_usd:)
      # In production, this would call Circle's API
      # Circle::PayoutService.create_payout(
      #   amount: amount_usd,
      #   destination: SOLANA_TREASURY_ADDRESS,
      #   currency: 'USDC'
      # )

      Rails.logger.info "[Payment] Converting $#{amount_usd} USD to USDC via Circle"

      # Placeholder - actual implementation calls Circle API
      {
        success: true,
        usdc_amount: amount_usd, # 1:1 for USDC
        circle_transfer_id: "circle_#{SecureRandom.hex(8)}"
      }
    end

    # Send USDC to the on-chain treasury
    def send_to_treasury(amount_usdc:, payment_reference:, payment_type:)
      Rails.logger.info "[Payment] Sending #{amount_usdc} USDC to treasury (ref: #{payment_reference})"

      # In production, this would call the Solana program
      # SolanaTreasuryService.receive_revenue(
      #   amount: amount_usdc,
      #   payment_reference: payment_reference
      # )

      # Revenue split: 50% holders, 40% R&D, 5% treasury, 5% ops
      {
        success: true,
        tx_signature: "tx_#{SecureRandom.hex(32)}",
        holder_share: amount_usdc * 0.50,
        rnd_share: amount_usdc * 0.40,
        treasury_share: amount_usdc * 0.05,
        ops_share: amount_usdc * 0.05
      }
    end

    # Send AMOS to the on-chain treasury (with 50% burn)
    # AMOS payments: 50% burned, 50% to holder pool
    # Note: R&D/Ops need USDC, so AMOS payments don't fund them directly
    # The burn benefits ALL holders by reducing supply
    def send_amos_to_treasury(amount_amos:, payment_reference:)
      Rails.logger.info "[Payment] Sending #{amount_amos} AMOS to treasury - 50% will be BURNED"

      burn_amount = amount_amos * 0.50
      holder_share = amount_amos * 0.50

      {
        success: true,
        tx_signature: "tx_#{SecureRandom.hex(32)}",
        tokens_burned: burn_amount,
        holder_share: holder_share
      }
    end

    # Verify a USDC deposit on-chain
    def verify_usdc_deposit(tx_signature:, expected_amount:)
      # In production, verify the transaction on Solana
      # SolanaService.verify_transfer(
      #   tx: tx_signature,
      #   token: USDC_MINT,
      #   destination: TREASURY_ADDRESS,
      #   min_amount: expected_amount
      # )

      Rails.logger.info "[Payment] Verifying USDC deposit: #{tx_signature}"
      true # Placeholder
    end

    # Verify an AMOS deposit on-chain
    def verify_amos_deposit(tx_signature:, expected_amount:)
      Rails.logger.info "[Payment] Verifying AMOS deposit: #{tx_signature}"
      true # Placeholder
    end

    # Record payment in database
    def record_payment(user:, amount_usd:, payment_method:, payment_reference:, treasury_result:)
      # Record for audit trail
      if defined?(PaymentRecord) && PaymentRecord.respond_to?(:create!)
        PaymentRecord.create!(
          user: user,
          amount_usd: amount_usd,
          payment_method: payment_method,
          payment_reference: payment_reference,
          on_chain_tx: treasury_result[:tx_signature],
          holder_share: treasury_result[:holder_share],
          metadata: treasury_result
        )
      end

      Rails.logger.info "[Payment] Recorded payment for user #{user.id}: $#{amount_usd} via #{payment_method}"
    end
  end
end
