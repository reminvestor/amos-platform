# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  layout 'devise'
  
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  # Override create to handle business name and entity creation
  def create
    super do |resource|
      if resource.persisted?
        # Parse full name into first and last name
        parse_full_name(resource)
        
        # Create business entity for the user
        create_business_entity(resource)
      end
    end
  end

  protected

  # If you have extra params to permit, append them to the sanitizer.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:full_name, :business_name, :role])
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
  
  def parse_full_name(user)
    full_name = params[:user][:full_name]&.strip
    return unless full_name.present?
    
    # Split the full name into parts
    name_parts = full_name.split(/\s+/)
    
    if name_parts.length >= 2
      # Take first part as first name, rest as last name
      user.first_name = name_parts.first
      user.last_name = name_parts[1..-1].join(' ')
    else
      # Only one name provided, use as first name
      user.first_name = name_parts.first
      user.last_name = 'Unknown'
    end
    
    user.save!
  end
  
  def create_business_entity(user)
    business_name = params[:user][:business_name]&.strip
    return unless business_name.present?
    
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