class Entity::PrivacyController < Entity::BaseController

  def show
    redirect_to chat_mode_path, status: :moved_permanently
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

    current_entity.settings["privacy"] = privacy_settings
    current_entity.save!

    respond_to do |format|
      format.json { render json: { success: true, message: "Privacy settings updated successfully." } }
      format.html { redirect_to chat_mode_path, notice: "Privacy settings updated successfully." }
    end
  end

  private


  def default_privacy_settings
    {
      "share_business_profile" => true,
      "share_contact_data" => false,
      "share_campaign_metrics" => true,
      "share_file_contents" => true,
      "mask_pii" => true,
      "mask_emails" => true,
      "mask_phone_numbers" => true,
      "mask_addresses" => true,
      "allow_data_export" => false,
      "data_retention_days" => 90,
      "excluded_fields" => []
    }
  end
end
