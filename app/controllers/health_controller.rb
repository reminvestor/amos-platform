class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  skip_before_action :check_onboarding_status
  
  def index
    render json: { status: 'ok', timestamp: Time.current }, status: :ok
  end
  
  def up
    render plain: 'OK', status: :ok
  end
end