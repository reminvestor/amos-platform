class Entity::PrivacyController < ApplicationController
  before_action :authenticate_user!
  before_action :require_entity_admin
  
  def show
    # Privacy settings stored in entity settings
    @privacy_settings = current_entity.settings['privacy'] || default_privacy_settings
  end
  
  def update
    privacy_settings = params[:privacy].permit(
      :share_business_profile,
      :share_contact_data,
      :share_campaign_metrics,
      :share_file_contents,
      :mask_pii,
      :mask_emails,
      :mask_phone_numbers,
      :mask_addresses,
      :allow_data_export,
      data_retention_days: [],
      excluded_fields: []
    ).to_h
    
    current_entity.settings['privacy'] = privacy_settings
    current_entity.save!
    
    redirect_to entity_privacy_path, notice: 'Privacy settings updated successfully.'
  end
  
  private
  
  def require_entity_admin
    unless current_user.entity_admin?
      redirect_to root_path, alert: 'You must be an entity admin to manage privacy settings.'
    end
  end
  
  def default_privacy_settings
    {
      'share_business_profile' => true,
      'share_contact_data' => false,
      'share_campaign_metrics' => true,
      'share_file_contents' => true,
      'mask_pii' => true,
      'mask_emails' => true,
      'mask_phone_numbers' => true,
      'mask_addresses' => true,
      'allow_data_export' => false,
      'data_retention_days' => 90,
      'excluded_fields' => []
    }
  end
end

