class AnalyticsController < ApplicationController
  include ActionController::Live

  before_action :authenticate_user!
  before_action :ensure_entity_exists

  # Main analytics dashboard page
  def index
    @entity = current_entity
    @metrics = Analytics::RealtimeService.current_metrics(current_entity)
  end

  # Server-Sent Events stream for real-time metrics
  def stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no' # Disable nginx buffering

    sse = SSE.new(response.stream, retry: 300, event: "metrics_update")

    begin
      # Send initial metrics immediately
      metrics = Analytics::RealtimeService.current_metrics(current_entity)
      sse.write(metrics)

      # Stream updates every 5 seconds
      loop do
        sleep 5

        # Check if client is still connected
        break if response.stream.closed?

        # Fetch latest metrics
        metrics = Analytics::RealtimeService.current_metrics(current_entity)
        sse.write(metrics)

        Rails.logger.debug "[Analytics] Streamed metrics: #{metrics.slice(:campaigns_active, :emails_sent_today)}"
      end
    rescue IOError, Errno::EPIPE => e
      # Client disconnected
      Rails.logger.info "[Analytics] Client disconnected: #{e.message}"
    rescue => e
      Rails.logger.error "[Analytics] Stream error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      sse.close
    end
  end

  # Get activity feed (recent events)
  def activity_feed
    @activities = Analytics::ActivityService.recent_activities(
      current_entity,
      limit: params[:limit]&.to_i || 20
    )

    render json: @activities
  end

  # Get engagement heatmap data
  def engagement_heatmap
    @heatmap_data = Analytics::HeatmapService.engagement_by_hour(
      current_entity,
      days: params[:days]&.to_i || 7
    )

    render json: @heatmap_data
  end

  # Get top performers (campaigns, emails, landing pages)
  def top_performers
    @performers = Analytics::TopPerformersService.top_performers(
      current_entity,
      metric: params[:metric] || 'open_rate',
      limit: params[:limit]&.to_i || 10
    )

    render json: @performers
  end

  private

  # SSE helper class
  class SSE
    def initialize(io, options = {})
      @io = io
      @options = options
    end

    def write(object, options = {})
      options.each do |k, v|
        @io.write "#{k}: #{v}\n"
      end

      @io.write "data: #{JSON.dump(object)}\n\n"
    end

    def close
      @io.close unless @io.closed?
    end
  end
end
