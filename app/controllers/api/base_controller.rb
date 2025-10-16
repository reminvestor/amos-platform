module Api
  class BaseController < ApplicationController
    protect_from_forgery with: :null_session
    skip_before_action :verify_authenticity_token

    # Skip any Devise authentication
    skip_before_action :authenticate_user!, raise: false

    # Always respond with JSON
    before_action :set_json_format

    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
    rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_token
    rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid

    private

    def set_json_format
      request.format = :json
    end

    def handle_standard_error(exception)
      Rails.logger.error("API Error [#{Time.current.iso8601(3)}]: #{exception.class.name}: #{exception.message}")
      Rails.logger.error(exception.backtrace.join("\n"))

      render json: {
        success: false,
        error: "Internal server error",
        message: exception.message,
        timestamp: Time.current.iso8601
      }, status: :internal_server_error
    end

    def handle_not_found(exception)
      Rails.logger.warn("API NotFound [#{Time.current.iso8601(3)}]: #{exception.message}")

      render json: {
        success: false,
        error: "Not found",
        message: exception.message,
        timestamp: Time.current.iso8601
      }, status: :not_found
    end

    def handle_parameter_missing(exception)
      Rails.logger.warn("API ParameterMissing [#{Time.current.iso8601(3)}]: #{exception.message}")

      render json: {
        success: false,
        error: "Missing parameter",
        message: exception.message,
        timestamp: Time.current.iso8601
      }, status: :bad_request
    end

    def handle_invalid_token(exception)
      Rails.logger.warn("API InvalidToken [#{Time.current.iso8601(3)}]: #{exception.message}")

      render json: {
        success: false,
        error: "Invalid CSRF token",
        message: exception.message,
        timestamp: Time.current.iso8601
      }, status: :unprocessable_entity
    end

    def handle_record_invalid(exception)
      Rails.logger.warn("API RecordInvalid [#{Time.current.iso8601(3)}]: #{exception.message}")

      render json: {
        success: false,
        error: "Validation failed",
        message: exception.message,
        timestamp: Time.current.iso8601
      }, status: :unprocessable_entity
    end

    def current_user
      @current_user
    end
  end
end
