module Admin
  class VoiceSettingsController < Admin::BaseController
    before_action -> { authorize_admin!(:super_admin) }

    def index
      @deepgram_settings = VoiceAssistantSetting.where("key LIKE ?", "deepgram.%").order(:key)
      @polly_settings = VoiceAssistantSetting.where("key LIKE ?", "polly.%").order(:key)
      @eleven_labs_settings = VoiceAssistantSetting.where("key LIKE ?", "eleven_labs.%").order(:key)
      @audio_settings = VoiceAssistantSetting.where("key LIKE ?", "audio.%").order(:key)
    end

    def update
      setting = VoiceAssistantSetting.find(params[:id])

      if setting.update(setting_params)
        flash[:notice] = "Setting '#{setting.key}' updated successfully"
      else
        flash[:alert] = "Failed to update setting: #{setting.errors.full_messages.join(', ')}"
      end

      redirect_to admin_voice_settings_path
    end

    def update_all
      params[:settings]&.each do |id, value|
        setting = VoiceAssistantSetting.find(id)
        setting.update(value: value)
      end

      flash[:notice] = "Voice assistant settings updated successfully"
      redirect_to admin_voice_settings_path
    end

    def reset_defaults
      VoiceAssistantSetting.seed_defaults!
      flash[:notice] = "Voice assistant settings reset to defaults"
      redirect_to admin_voice_settings_path
    end

    private

    def setting_params
      params.require(:voice_assistant_setting).permit(:value)
    end
  end
end
