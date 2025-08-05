class DebugController < ApplicationController
  # Skip all authentication and redirect checks for debugging
  skip_before_action :authenticate_user!, only: [:status]
  skip_before_action :check_onboarding_status, only: [:status]
  
  def index
    # Simple debug page
  end

  def test_sse
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    
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
    if user_signed_in?
      render json: {
        success: true,
        user_id: current_user.id,
        user_email: current_user.email,
        onboarded: current_user.onboarded?,
        entities_count: current_user.entities.count,
        entity_names: current_user.entities.pluck(:name),
        current_entity_id: session[:entity_id],
        current_entity_name: current_entity&.name,
        has_business_profile: current_user.business_profile.present?,
        subdomain: request.subdomain,
        domain: request.domain,
        path: request.path,
        referer: request.referer,
        timestamp: Time.current.iso8601
      }
    else
      render json: {
        success: false,
        message: "User not signed in",
        subdomain: request.subdomain,
        domain: request.domain,
        path: request.path,
        timestamp: Time.current.iso8601
      }
    end
  end
  
  private
  
  def current_entity
    @current_entity ||= current_user&.entity_users&.first&.entity
  end
end 