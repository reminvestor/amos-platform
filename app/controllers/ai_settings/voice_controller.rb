class AiSettings::VoiceController < ApplicationController
  before_action :authenticate_user!

  layout "customer_admin"

  def show
    redirect_to chat_mode_path, status: :moved_permanently
  end

  def update
    # Voice settings are saved via API, this just handles form fallback
    if current_user.update(tts_preferences: voice_params)
      redirect_to chat_mode_path, notice: "Voice settings updated successfully."
    else
      redirect_to chat_mode_path, alert: "Failed to update voice settings."
    end
  end

  private

  def voice_params
    params.require(:voice_settings).permit(
      :enabled,
      :provider,
      :voice_id,
      :eleven_labs_voice_id,
      :engine,
      :speed,
      :volume
    ).to_h
  end
end

