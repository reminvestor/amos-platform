# frozen_string_literal: true

# Service to create affiliate referrals when users sign up
# Links affiliate -> new user -> new entity
class AffiliateReferralService
  class << self
    # Create a referral record when user signs up with affiliate cookie
    #
    # @param referral_code [String] The affiliate code from cookie
    # @param user [User] The newly created user
    # @param entity [Entity] The entity associated with the user
    # @param cookie_data [Hash] Metadata about the referral (IP, user agent, etc.)
    # @return [Referral, nil] The created referral or nil if creation failed
    def create_referral(referral_code:, user:, entity:, cookie_data: {})
      # Find active affiliate by code
      affiliate = Affiliate.find_by(affiliate_code: referral_code, status: :active)
      unless affiliate
        Rails.logger.warn "Affiliate not found or inactive: #{referral_code}"
        return nil
      end

      # Check if this entity already has a referral (prevent duplicate referrals)
      existing_referral = Referral.find_by(referred_entity: entity)
      if existing_referral
        Rails.logger.warn "Referral already exists for entity #{entity.id}"
        return existing_referral
      end

      # Create the referral
      referral = Referral.create!(
        affiliate: affiliate,
        referred_user: user,
        referred_entity: entity,
        referral_code_used: referral_code,
        status: :pending,
        cookie_data: cookie_data.merge(
          created_at: Time.current.iso8601
        )
      )

      Rails.logger.info "✅ Created referral: affiliate=#{affiliate.id}, user=#{user&.id || 'nil'}, entity=#{entity&.id || 'nil'}"

      # Send notification to affiliate about new signup
      send_affiliate_notification(affiliate, user, referral)

      referral
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create referral: #{e.message}"
      nil
    end

    private

    # Send notification to affiliate about new signup
    def send_affiliate_notification(affiliate, user, referral)
      return unless affiliate.user&.email.present?

      # Queue background job to send email
      AffiliateMailer.new_referral_signup(affiliate, user).deliver_later
      Rails.logger.info "📧 Sent new signup notification to affiliate #{affiliate.id}"
    rescue => e
      Rails.logger.error "Failed to send affiliate notification: #{e.message}"
    end
  end
end
