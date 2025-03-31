module Api
  class BaseController < ApplicationController
    protect_from_forgery with: :null_session
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
    
    private
    
    def handle_standard_error(exception)
      Rails.logger.error("API Error: #{exception.message}\n#{exception.backtrace.join("\n")}")
      render json: {
        success: false,
        error: "Internal server error",
        message: exception.message
      }, status: :internal_server_error
    end
    
    def handle_not_found(exception)
      render json: {
        success: false,
        error: "Not found",
        message: exception.message
      }, status: :not_found
    end
    
    def handle_parameter_missing(exception)
      render json: {
        success: false,
        error: "Missing parameter",
        message: exception.message
      }, status: :bad_request
    end
    
    def current_user
      @current_user
    end
  end
end 