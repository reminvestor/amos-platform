module Admin
  class SystemSettingsController < Admin::BaseController
    before_action -> { authorize_admin!(:super_admin) }

    def index
      @settings_by_category = SystemSetting.all.group_by(&:category)
      @categories = SystemSetting::CATEGORIES
    end

    def update
      setting = SystemSetting.find(params[:id])

      if setting.update(setting_params.merge(last_updated_by: current_admin.id))
        flash[:notice] = "Setting '#{setting.key}' updated successfully"
      else
        flash[:alert] = "Failed to update setting: #{setting.errors.full_messages.join(', ')}"
      end

      redirect_to admin_system_settings_path
    end

    def update_all
      errors = []

      params[:settings]&.each do |id, new_value|
        setting = SystemSetting.find(id)

        # Skip if value hasn't changed
        next if new_value == setting.effective_value

        unless setting.update(value: new_value, last_updated_by: current_admin.id)
          errors << "#{setting.key}: #{setting.errors.full_messages.join(', ')}"
        end
      end

      if errors.empty?
        flash[:notice] = "System settings updated successfully"
      else
        flash[:alert] = "Some settings failed to update: #{errors.join('; ')}"
      end

      redirect_to admin_system_settings_path
    end

    def reset_defaults
      SystemSetting.seed_defaults!
      flash[:notice] = "System settings reset to defaults from environment variables"
      redirect_to admin_system_settings_path
    end

    def test_key
      setting = SystemSetting.find(params[:id])
      result = test_api_key(setting)

      render json: result
    end

    private

    def setting_params
      params.require(:system_setting).permit(:value)
    end

    def test_api_key(setting)
      case setting.key
      when "OPENAI_API_KEY"
        test_openai(setting.effective_value)
      when "DEEPGRAM_API_KEY"
        test_deepgram(setting.effective_value)
      when "GITHUB_TOKEN"
        test_github(setting.effective_value)
      else
        { success: false, message: "No test available for #{setting.key}" }
      end
    rescue => e
      { success: false, message: "Test failed: #{e.message}" }
    end

    def test_openai(api_key)
      return { success: false, message: "API key is blank" } if api_key.blank?

      response = HTTParty.get("https://api.openai.com/v1/models",
        headers: { "Authorization" => "Bearer #{api_key}" })

      if response.success?
        { success: true, message: "✓ OpenAI API key is valid" }
      else
        { success: false, message: "✗ Invalid API key: #{response.code}" }
      end
    end

    def test_deepgram(api_key)
      return { success: false, message: "API key is blank" } if api_key.blank?

      response = HTTParty.get("https://api.deepgram.com/v1/projects",
        headers: { "Authorization" => "Token #{api_key}" })

      if response.success?
        { success: true, message: "✓ Deepgram API key is valid" }
      else
        { success: false, message: "✗ Invalid API key: #{response.code}" }
      end
    end

    def test_github(token)
      return { success: false, message: "Token is blank" } if token.blank?

      response = HTTParty.get("https://api.github.com/user",
        headers: { "Authorization" => "token #{token}" })

      if response.success?
        { success: true, message: "✓ GitHub token is valid" }
      else
        { success: false, message: "✗ Invalid token: #{response.code}" }
      end
    end
  end
end
