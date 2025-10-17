# frozen_string_literal: true

# Service to create affiliate commissions based on Stripe events
# Handles first payment and recurring commissions
class AffiliateCommissionService
  # High commission threshold - requires manual approval
  HIGH_COMMISSION_THRESHOLD = 500.00

  class << self
    # Create commission for first payment
    #
    # @param entity [Entity] The entity making the payment
    # @param amount [Float] The payment amount in dollars
    # @param stripe_event_id [String, nil] Optional Stripe event ID for tracking
    # @return [Commission, nil] The created commission or nil if no referral exists
    def create_for_first_payment(entity, amount, stripe_event_id: nil)
      # Find pending referral for this entity
      referral = Referral.find_by(referred_entity: entity, status: :pending)
      unless referral
        Rails.logger.info "No pending referral found for entity #{entity.id}"
        return nil
      end

      # Check if first payment commission already exists
      existing_commission = Commission.find_by(
        referral: referral,
        commission_type: 'first_payment'
      )
      if existing_commission
        Rails.logger.warn "First payment commission already exists for referral #{referral.id}"
        return existing_commission
      end

      # Calculate commission amount
      commission_amount = amount * referral.affiliate.commission_rate

      # Auto-approve small commissions, require review for large ones
      status = commission_amount >= HIGH_COMMISSION_THRESHOLD ? :pending : :approved
      approved_at = status == :approved ? Time.current : nil

      # Create the commission
      commission = Commission.create!(
        affiliate: referral.affiliate,
        referral: referral,
        entity: entity,
        commission_type: 'first_payment',
        amount: commission_amount,
        currency: 'USD',
        status: status,
        earned_at: Time.current,
        approved_at: approved_at
      )

      # Mark referral as converted
      referral.update!(status: :converted, converted_at: Time.current)

      Rails.logger.info "✅ Created first payment commission: affiliate=#{referral.affiliate_id}, amount=$#{commission_amount}, status=#{status}"

      # Send notifications
      send_commission_notifications(commission, referral.affiliate)

      commission
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create first payment commission: #{e.message}"
      nil
    end

    # Create commission for recurring payment (first 12 months only)
    #
    # @param entity [Entity] The entity making the payment
    # @param amount [Float] The payment amount in dollars
    # @param stripe_event_id [String, nil] Optional Stripe event ID for tracking
    # @return [Commission, nil] The created commission or nil if not eligible
    def create_for_recurring_payment(entity, amount, stripe_event_id: nil)
      # Find converted referral for this entity
      referral = Referral.find_by(referred_entity: entity, status: :converted)
      unless referral
        Rails.logger.debug "No converted referral found for entity #{entity.id}"
        return nil
      end

      # Only pay recurring commissions for first 12 months
      if referral.converted_at <= 12.months.ago
        Rails.logger.debug "Referral #{referral.id} is older than 12 months, skipping commission"
        return nil
      end

      # Calculate commission amount
      commission_amount = amount * referral.affiliate.commission_rate

      # Auto-approve small commissions, require review for large ones
      status = commission_amount >= HIGH_COMMISSION_THRESHOLD ? :pending : :approved
      approved_at = status == :approved ? Time.current : nil

      # Create the commission
      commission = Commission.create!(
        affiliate: referral.affiliate,
        referral: referral,
        entity: entity,
        commission_type: 'recurring',
        amount: commission_amount,
        currency: 'USD',
        status: status,
        earned_at: Time.current,
        approved_at: approved_at
      )

      Rails.logger.info "✅ Created recurring commission: affiliate=#{referral.affiliate_id}, amount=$#{commission_amount}, status=#{status}"

      # Send notifications
      send_commission_notifications(commission, referral.affiliate)

      commission
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create recurring commission: #{e.message}"
      nil
    end

    private

    # Send notifications about commission creation
    def send_commission_notifications(commission, affiliate)
      # Notify affiliate about earned commission
      if commission.approved?
        AffiliateMailer.commission_earned(affiliate, commission).deliver_later
        Rails.logger.info "📧 Sent commission earned email to affiliate #{affiliate.id}"
      end

      # Notify admins about high-value commissions requiring review
      if commission.pending? && commission.amount > HIGH_COMMISSION_THRESHOLD
        AdminMailer.high_value_commission_review(commission).deliver_later
        Rails.logger.info "📧 Sent high-value commission review email to admins"
      end
    rescue => e
      Rails.logger.error "Failed to send commission notifications: #{e.message}"
    end
  end
end
