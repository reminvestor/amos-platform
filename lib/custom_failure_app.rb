# frozen_string_literal: true

# Custom Warden failure app that returns JSON for API/CORS requests
# instead of redirecting to login page
class CustomFailureApp < Devise::FailureApp
  def respond
    if api_request? || cors_request?
      json_failure_response
    else
      super
    end
  end

  private

  def json_failure_response
    self.status = 401
    self.content_type = "application/json"

    # Add CORS headers for cross-origin requests
    origin = request.headers["HTTP_ORIGIN"]
    if origin && origin =~ %r{\Ahttps?://(localhost|127\.0\.0\.1)(:\d+)?\z}
      headers["Access-Control-Allow-Origin"] = origin
      headers["Access-Control-Allow-Credentials"] = "true"
    end

    self.response_body = {
      error: "unauthorized",
      message: i18n_message(:unauthenticated),
      redirect_url: new_user_session_url
    }.to_json
  end

  def api_request?
    # Check for API paths or Bearer token
    request.path.start_with?("/api/") ||
      request.headers["Authorization"]&.start_with?("Bearer ") ||
      request.content_type&.include?("application/json")
  end

  def cors_request?
    # Check if this is a cross-origin request
    origin = request.headers["HTTP_ORIGIN"]
    origin.present? && origin != request.base_url
  end
end
