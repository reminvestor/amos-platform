# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  layout 'application', only: [:edit, :update]
  layout 'devise', only: [:new, :create]
  
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  # Override build_resource to parse full_name before user creation
  def build_resource(hash = {})
    # Parse full name and add first_name/last_name to the hash
    # Only do this when form is being submitted (params[:user] exists)
    if params[:user]&.dig(:full_name).present?
      full_name = params[:user][:full_name].strip
      name_parts = full_name.split(/\s+/)
      
      if name_parts.length >= 2
        hash[:first_name] = name_parts.first
        hash[:last_name] = name_parts[1..-1].join(' ')
      else
        hash[:first_name] = name_parts.first
        hash[:last_name] = 'Unknown'
      end
    end
    
    super(hash)
  end

  # Override create to handle entity creation
  def create
    super do |resource|
      if resource.persisted?
        # Create business entity for the user (always create one)
        create_business_entity(resource)
      end
    end
  end

  protected

  # If you have extra params to permit, append them to the sanitizer.
  def configure_sign_up_params
    # Note: full_name and business_name are handled manually in the create method
    # We only permit parameters that actually exist on the User model
    devise_parameter_sanitizer.permit(:sign_up, keys: [:role])
  end

  # If you have extra params to permit, append them to the sanitizer.
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :role])
  end

  # Override the after_sign_up_path_for method to redirect to onboarding
  def after_sign_up_path_for(resource)
    onboarding_path
  end

  def after_inactive_sign_up_path_for(resource)
    onboarding_path
  end
  
  private
  
  def create_business_entity(user)
    business_name = params[:user][:business_name]&.strip
    
    # If no business name provided, create default using user's name
    if business_name.blank?
      business_name = "#{user.full_name} Inc"
    end
    
    begin
      # Create the entity
      entity = Entity.create!(
        name: business_name,
        subdomain: generate_subdomain(business_name),
        status: 'active'
      )
      
      # Associate user as owner
      EntityUser.create!(
        entity: entity,
        user: user,
        role: 'owner'
      )
      
      # Set the entity in session for immediate use
      session[:entity_id] = entity.id
      
      Rails.logger.info "✅ Created entity '#{business_name}' for user #{user.email}"
    rescue => e
      Rails.logger.error "❌ Failed to create entity for user #{user.email}: #{e.message}"
      # Don't prevent user creation if entity creation fails
      # User will be directed to create entity during onboarding
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
end 