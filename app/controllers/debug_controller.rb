class DebugController < ApplicationController
  before_action :require_development_or_admin!

  def index
    # Simple debug page
  end

  def test_sse
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    # Enable streaming
    sse = SSE.new(response.stream, retry: 300, event: "debug")

    begin
      Rails.logger.info "🧪 Starting SSE debug test"

      # Send test messages
      (1..5).each do |i|
        message = "Debug message #{i} at #{Time.current}"
        sse.write({ test: message, timestamp: Time.current.iso8601 })
        Rails.logger.info "📡 Sent debug message #{i}: #{message}"
        sleep(1)
      end

      Rails.logger.info "✅ SSE debug test completed"

    rescue IOError => e
      Rails.logger.error "❌ SSE debug test failed: #{e.message}"
    ensure
      sse.close
    end
  end

  def status
    render json: {
      success: true,
      user_id: current_user.id,
      onboarded: current_user.onboarded?,
      has_entity: current_user.entity.present?,
      has_business_profile: current_user.business_profile.present?,
      timestamp: Time.current.iso8601
    }
  end

  private

  def require_development_or_admin!
    unless Rails.env.development? || Rails.env.test? || current_user&.admin?
      render json: { error: "Not found" }, status: :not_found
    end
  end

  def current_entity
    @current_entity ||= current_user&.entity_users&.first&.entity
  end
end
