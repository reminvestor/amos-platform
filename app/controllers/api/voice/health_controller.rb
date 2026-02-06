module Api
  module Voice
    # VoiceHealthController - Monitor STT provider health and system status
    #
    # Endpoints:
    # - GET /api/voice/health/status - Overall voice system health
    # - GET /api/voice/health/providers - Individual provider status
    # - GET /api/voice/health/metrics - Usage metrics and analytics
    # - GET /api/voice/health/optimization - Optimization recommendations
    class HealthController < ApplicationController
      before_action :authenticate_user!, except: [:status]  # Public health check for monitoring/status pages
      before_action :authorize_admin_or_staff, only: [:metrics, :optimization]

      # GET /api/voice/health/status
      # Public health check — intentionally unauthenticated for status pages
      def status
        service = VoiceProviderHealthService.new

        render json: {
          timestamp: Time.current,
          status: "ok",
          voice_system: service.get_health_summary,
          endpoints: {
            eleven_labs: service.check_provider_health("eleven_labs"),
            deepgram: service.check_provider_health("deepgram")
          }
        }
      rescue => e
        Rails.logger.error "Health check error: #{e.message}"
        render json: {
          timestamp: Time.current,
          status: "error",
          error: "Health check failed"
        }, status: :internal_server_error
      end

      # GET /api/voice/health/providers
      # Individual provider detailed status
      def providers
        service = VoiceProviderHealthService.new

        render json: {
          timestamp: Time.current,
          providers: {
            eleven_labs: {
              health: service.check_provider_health("eleven_labs"),
              metrics: service.get_provider_metrics("eleven_labs")
            },
            deepgram: {
              health: service.check_provider_health("deepgram"),
              metrics: service.get_provider_metrics("deepgram")
            }
          }
        }
      rescue => e
        render json: { error: "Failed to get provider status: #{e.message}" },
               status: :internal_server_error
      end

      # GET /api/voice/health/metrics
      # Usage and performance metrics
      def metrics
        service = VoiceMetricsService.new
        period = params[:days]&.to_i || 7

        render json: {
          timestamp: Time.current,
          period_days: period,
          providers: {
            eleven_labs: service.get_provider_statistics("eleven_labs", days: period),
            deepgram: service.get_provider_statistics("deepgram", days: period)
          },
          comparison: service.compare_providers("eleven_labs", "deepgram", days: period),
          health_status: service.check_voice_system_health,
          recent_sessions: service.get_recent_sessions(limit: 10)
        }
      rescue => e
        render json: { error: "Failed to get metrics: #{e.message}" },
               status: :internal_server_error
      end

      # GET /api/voice/health/optimization
      # Performance optimization recommendations
      def optimization
        optimizer = VoiceConnectionOptimizer.new

        metrics = optimizer.get_optimization_metrics
        cache_stats = optimizer.get_cache_statistics
        pool_status = {
          eleven_labs: optimizer.get_connection_pool_status("eleven_labs"),
          deepgram: optimizer.get_connection_pool_status("deepgram")
        }

        render json: {
          timestamp: Time.current,
          optimization_metrics: metrics,
          cache_statistics: cache_stats,
          connection_pools: pool_status,
          recommendations: generate_optimization_recommendations(metrics, cache_stats)
        }
      rescue => e
        render json: { error: "Failed to get optimization data: #{e.message}" },
               status: :internal_server_error
      end

      # POST /api/voice/health/prewarm
      # Manually trigger connection pre-warming
      def prewarm
        optimizer = VoiceConnectionOptimizer.new
        result = optimizer.prewarm_connections

        render json: {
          timestamp: Time.current,
          prewarm_result: result,
          message: "Connection pre-warming completed"
        }
      rescue => e
        render json: { error: "Pre-warming failed: #{e.message}" },
               status: :internal_server_error
      end

      private

      def authorize_admin_or_staff
        unless current_user&.admin? || is_monitoring_user?
          render json: { error: "Unauthorized" }, status: :forbidden
        end
      end

      def is_monitoring_user?
        # You can add additional authorization logic here
        # e.g., check for monitoring service account
        false
      end

      def generate_optimization_recommendations(metrics, cache_stats)
        recommendations = []

        # Cache recommendations
        if cache_stats[:total_cached] < 2
          recommendations << {
            category: "caching",
            priority: "high",
            recommendation: "Enable credential caching to reduce API calls and improve performance",
            expected_benefit: "10-20ms faster credential retrieval"
          }
        end

        # Provider-specific recommendations
        metrics[:recommendations]&.each do |rec|
          recommendations << {
            category: rec[:type],
            priority: rec[:severity],
            recommendation: rec[:message]
          }
        end

        # Connection pool recommendations
        if cache_stats[:total_cached] < 1
          recommendations << {
            category: "pooling",
            priority: "medium",
            recommendation: "Implement connection pooling to handle concurrent voice sessions",
            expected_benefit: "Better resource utilization and faster session creation"
          }
        end

        recommendations
      end
    end
  end
end
