module Api
  module V1
    class HealthController < Api::BaseController
      # No need for skip_before_action as it's defined in the parent controller

      def index
        # Return debugging info to help diagnose SSL issues
        render json: {
          status: "ok",
          timestamp: Time.now.utc.iso8601,
          request_info: {
            protocol: request.protocol,
            ssl: request.ssl?,
            forwarded_proto: request.headers["HTTP_X_FORWARDED_PROTO"],
            headers: request.headers.to_h.select { |k, _| k.start_with?("HTTP_") }
          },
          env_info: {
            rack_env: ENV["RACK_ENV"],
            rails_env: Rails.env,
            ssl_disabled: ENV["DISABLE_SSL"],
            force_ssl: ENV["FORCE_SSL"]
          }
        }
      end

      # RAG system health check endpoint
      # GET /api/v1/health/rag
      def rag
        health_result = Rag::HealthCheckJob.new.perform

        status_code = health_result[:all_healthy] ? 200 : 503

        render json: {
          status: health_result[:all_healthy] ? "healthy" : "unhealthy",
          timestamp: health_result[:timestamp],
          checks: health_result[:checks],
          summary: {
            total_checks: health_result[:checks].length,
            healthy_checks: health_result[:checks].count { |_, c| c[:healthy] },
            unhealthy_checks: health_result[:checks].count { |_, c| !c[:healthy] }
          }
        }, status: status_code
      end
    end
  end
end
