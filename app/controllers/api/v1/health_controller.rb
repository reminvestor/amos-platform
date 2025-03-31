module Api
  module V1
    class HealthController < ApplicationController
      skip_before_action :verify_authenticity_token
      
      def index
        # Return debugging info to help diagnose SSL issues
        render json: {
          status: 'ok',
          timestamp: Time.now.utc.iso8601,
          request_info: {
            protocol: request.protocol,
            ssl: request.ssl?,
            forwarded_proto: request.headers['HTTP_X_FORWARDED_PROTO'],
            headers: request.headers.to_h.select { |k, _| k.start_with?('HTTP_') }
          },
          env_info: {
            rack_env: ENV['RACK_ENV'],
            rails_env: Rails.env,
            ssl_disabled: ENV['DISABLE_SSL'],
            force_ssl: ENV['FORCE_SSL']
          }
        }
      end
    end
  end
end 