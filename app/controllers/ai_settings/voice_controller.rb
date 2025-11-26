class AiSettings::VoiceController < ApplicationController
  before_action :authenticate_user!

  layout "customer_admin"

  def show
    @tts_preferences = current_user.tts_preferences || {}
  end

  def update
    # Voice settings are saved via API, this just handles form fallback
    if current_user.update(tts_preferences: voice_params)
      redirect_to ai_settings_voice_path, notice: "Voice settings updated successfully."
    else
      @tts_preferences = current_user.tts_preferences || {}
      flash.now[:alert] = "Failed to update voice settings."
      render :show, status: :unprocessable_entity
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

