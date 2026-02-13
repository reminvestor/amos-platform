# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  include AffiliateTracking

  layout "application", only: [ :edit, :update ]
  layout "devise", only: [ :new, :create ]

  # Skip CSRF verification for sign-up. Same reasoning as sessions: :null_session
  # silently discards session writes, preventing the user from being logged in after
  # registration. Devise handles authentication security independently of CSRF.
  skip_forgery_protection only: [:create]

  before_action :configure_sign_up_params, only: [ :create ]
  before_action :configure_account_update_params, only: [ :update ]
  before_action :redirect_to_profile, only: [ :edit ]

  # Override build_resource to parse full_name and create entity before user creation
  def build_resource(hash = {})
    # Parse full name and add first_name/last_name to the hash
    # Only do this when form is being submitted (params[:user] exists)
    if params[:user]&.dig(:full_name).present?
      full_name = params[:user][:full_name].strip
      name_parts = full_name.split(/\s+/)

      if name_parts.length >= 2
        hash[:first_name] = name_parts.first
        hash[:last_name] = name_parts[1..-1].join(" ")
      else
        hash[:first_name] = name_parts.first
        hash[:last_name] = "Unknown"
      end
    end

    # Create entity BEFORE user so we can set entity_id
    if params[:user]&.dig(:business_name).present? || hash[:first_name].present?
      business_name = params[:user]&.dig(:business_name)&.strip
      first_name = hash[:first_name] || "User"
      last_name = hash[:last_name] || ""
      entity = create_entity_for_signup(business_name, first_name, last_name)
      hash[:entity_id] = entity.id if entity
    end

    super(hash)
  end

  # Override create to associate user with entity after creation
  def create
    super do |resource|
      if resource.persisted? && resource.entity_id
        # Create the EntityUser association
        EntityUser.find_or_create_by!(
          entity_id: resource.entity_id,
          user: resource
        ) do |eu|
          eu.role = "owner"
        end

        # Set the entity in session for immediate use
        session[:entity_id] = resource.entity_id

        Rails.logger.info "✅ User #{resource.email} associated with entity #{resource.entity_id}"

        # Track affiliate referral if cookie present
        if affiliate_referral_code.present?
          begin
            AffiliateReferralService.create_referral(
              referral_code: affiliate_referral_code,
              user: resource,
              entity: resource.entity,
              cookie_data: {
                ip: request.remote_ip,
                user_agent: request.user_agent,
                referrer: request.referrer
              }
            )

            # Clear the cookie after conversion
            cookies.delete(:affiliate_ref)
            Rails.logger.info "✅ Affiliate referral tracked for user #{resource.email}"
          rescue => e
            # Don't fail registration if affiliate tracking fails
            Rails.logger.error "❌ Failed to track affiliate referral: #{e.message}"
          end
        end
      end
    end
  end

  protected

  # If you have extra params to permit, append them to the sanitizer.
  def configure_sign_up_params
    # Note: full_name and business_name are handled manually in the create method
    # We only permit parameters that actually exist on the User model
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :role ])
  end

  # If you have extra params to permit, append them to the sanitizer.
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name, :role ])
  end

  # Override the after_sign_up_path_for method to redirect to billing setup
  def after_sign_up_path_for(resource)
    # New users get free tokens and can set up payment method
    # They don't need to pay upfront - redirect to billing setup
    setup_payment_billing_path
  end

  def after_inactive_sign_up_path_for(resource)
    setup_payment_billing_path
  end

  private

  def create_entity_for_signup(business_name, first_name, last_name)
    # If no business name provided, create default using user's name
    if business_name.blank?
      business_name = "#{first_name} #{last_name} Business"
    end

    begin
      # Create the entity
      entity = Entity.create!(
        name: business_name,
        subdomain: generate_subdomain(business_name),
        status: "active"
      )

      Rails.logger.info "✅ Created entity '#{business_name}' (ID: #{entity.id})"
      entity
    rescue => e
      Rails.logger.error "❌ Failed to create entity: #{e.message}"
      nil
    end
  end

  def generate_subdomain(business_name)
    # Generate a subdomain from business name
    base_subdomain = business_name.parameterize
    subdomain = base_subdomain

    # Ensure uniqueness
    counter = 1
    while Entity.where(subdomain: subdomain).exists?
      subdomain = "#{base_subdomain}-#{counter}"
      counter += 1
    end

    subdomain
  end

  def redirect_to_profile
    redirect_to user_path(current_user), notice: "Manage all your account settings here"
  end
end
