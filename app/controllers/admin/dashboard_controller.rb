class Admin::DashboardController < Admin::BaseController
  def index
    @stats = {
      # User stats
      total_users: User.count,
      active_users_today: User.where("current_sign_in_at > ?", 24.hours.ago).count,
      new_users_this_week: User.where(created_at: 1.week.ago..).count,

      # Integration stats
      total_integrations: Integration.count,
      active_connections: Connection.active.count,
      failed_connections: Connection.failing.count,

      # API activity
      api_calls_today: integration_logs_today.count,
      api_errors_today: integration_logs_today.where("response_status >= 400").count,

      # AI usage stats
      ai_tokens_today: calculate_ai_tokens_today,
      ai_cost_today: calculate_ai_cost_today,

      # Campaign stats
      campaigns_sent_today: Campaign.where(status: "sent").where(created_at: 24.hours.ago..).count,
      total_campaigns: Campaign.count,
      total_contacts: Contact.count
    }

    # Recent activity
    @recent_api_calls = IntegrationLog.includes(:connection)
                                      .order(created_at: :desc)
                                      .limit(10)

    @recent_admin_activity = AdminActivity.includes(:admin_user)
                                          .order(created_at: :desc)
                                          .limit(10) rescue []

    # Failing connections
    @failing_connections = Connection.where.not(status: "connected").includes(:integration).limit(10)

    # Chart data
    @api_usage_chart_data = generate_api_usage_chart_data
    @error_rate_chart_data = generate_error_rate_chart_data
  end

  def services
    # Initialize all service checks
    @services = {}

    # Database
    @services[:database] = check_database

    # Redis
    @services[:redis] = check_redis

    # Pinecone
    @services[:pinecone] = check_pinecone

    # OpenAI
    @services[:openai] = check_openai

    # AWS Bedrock
    @services[:bedrock] = check_bedrock

    # RAG System
    @services[:rag] = check_rag_system

    # SolidQueue
    @services[:solid_queue] = check_solid_queue

    # Storage
    @services[:storage] = check_storage

    # Overall health
    @overall_status = calculate_overall_status(@services)
  end

  private

  def integration_logs_today
    @integration_logs_today ||= IntegrationLog.where(created_at: 24.hours.ago..)
  end

  def calculate_ai_tokens_today
    # Aggregate real token usage from ObservabilityEvent
    ai_responses = ObservabilityEvent
                     .where(event_type: "ai_response")
                     .where("created_at > ?", 24.hours.ago)

    ai_responses.sum do |event|
      metadata = event.metadata || {}
      (metadata["input_tokens"] || 0) + (metadata["output_tokens"] || 0)
    end
  rescue => e
    Rails.logger.error "Error calculating AI tokens: #{e.message}"
    0
  end

  def calculate_ai_cost_today
    # Calculate real cost based on token usage and model rates
    total_cost = 0.0

    ai_responses = ObservabilityEvent
                     .where(event_type: "ai_response")
                     .where("created_at > ?", 24.hours.ago)

    ai_responses.each do |event|
      metadata = event.metadata || {}
      input_tokens = metadata["input_tokens"] || 0
      output_tokens = metadata["output_tokens"] || 0
      model = metadata["model"] || "claude-sonnet-4.5"

      # Model pricing (per 1M tokens)
      pricing = get_model_pricing(model)

      total_cost += (input_tokens / 1_000_000.0 * pricing[:input]) +
                    (output_tokens / 1_000_000.0 * pricing[:output])
    end

    total_cost.round(2)
  rescue => e
    Rails.logger.error "Error calculating AI cost: #{e.message}"
    0.0
  end

  def get_model_pricing(model)
    # Pricing per 1M tokens (as of 2025)
    case model
    when /claude-3-opus/
      { input: 15.00, output: 75.00 }
    when /claude-3-sonnet/, /claude-sonnet/
      { input: 3.00, output: 15.00 }
    when /claude-haiku-4-5/, /claude-3-haiku/, /claude-haiku/
      { input: 0.25, output: 1.25 }
    when /claude-sonnet-4/
      { input: 3.00, output: 15.00 }
    when /gpt-4/
      { input: 30.00, output: 60.00 }
    when /gpt-3.5/
      { input: 0.50, output: 1.50 }
    else
      { input: 3.00, output: 15.00 } # Default to Claude Sonnet pricing
    end
  end

  def generate_api_usage_chart_data
    # Group by hour for the last 24 hours
    hours = (0..23).map { |h| h.hours.ago.beginning_of_hour }

    data = IntegrationLog.where(created_at: 24.hours.ago..)
                         .group_by_hour(:created_at)
                         .count

    {
      labels: hours.map { |h| h.strftime("%-l %p") },
      datasets: [ {
        label: "API Calls",
        data: hours.map { |h| data[h] || 0 },
        borderColor: "rgb(59, 130, 246)",
        backgroundColor: "rgba(59, 130, 246, 0.1)"
      } ]
    }
  end

  def generate_error_rate_chart_data
    # Calculate error rate by hour
    hours = (0..23).map { |h| h.hours.ago.beginning_of_hour }

    total_by_hour = IntegrationLog.where(created_at: 24.hours.ago..)
                                  .group_by_hour(:created_at)
                                  .count

    errors_by_hour = IntegrationLog.where(created_at: 24.hours.ago..)
                                   .where("response_status >= 400")
                                   .group_by_hour(:created_at)
                                   .count

    {
      labels: hours.map { |h| h.strftime("%-l %p") },
      datasets: [ {
        label: "Error Rate %",
        data: hours.map do |h|
          total = total_by_hour[h] || 0
          errors = errors_by_hour[h] || 0
          total > 0 ? ((errors.to_f / total) * 100).round(2) : 0
        end,
        borderColor: "rgb(239, 68, 68)",
        backgroundColor: "rgba(239, 68, 68, 0.1)"
      } ]
    }
  end

  # Service health check methods
  def check_database
    status = { name: "PostgreSQL Database", status: :unknown, details: {} }

    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      status[:status] = :healthy
      status[:details] = {
        adapter: ActiveRecord::Base.connection.adapter_name,
        version: ActiveRecord::Base.connection.select_value("SELECT version()").split.first(2).join(" "),
        pool_size: ActiveRecord::Base.connection_pool.size,
        active_connections: ActiveRecord::Base.connection_pool.connections.count
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_redis
    status = { name: "Redis Cache", status: :unknown, details: {} }

    begin
      Redis.new.ping
      status[:status] = :healthy
      redis_info = Redis.new.info
      status[:details] = {
        version: redis_info["redis_version"],
        connected_clients: redis_info["connected_clients"],
        used_memory: redis_info["used_memory_human"],
        uptime_days: (redis_info["uptime_in_seconds"].to_i / 86400.0).round(1)
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_pinecone
    status = { name: "Pinecone Vector DB", status: :unknown, details: {} }

    begin
      if ENV["PINECONE_API_KEY"].blank? || ENV["PINECONE_ENVIRONMENT"].blank?
        status[:status] = :warning
        status[:error] = "API key or environment not configured"
        return status
      end

      client = Pinecone::Client.new
      indexes = client.list_indexes

      status[:status] = :healthy
      status[:details] = {
        environment: ENV["PINECONE_ENVIRONMENT"],
        indexes_count: indexes.is_a?(Array) ? indexes.count : 0
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_openai
    status = { name: "OpenAI API", status: :unknown, details: {} }

    begin
      if ENV["OPENAI_API_KEY"].blank?
        status[:status] = :warning
        status[:error] = "API key not configured"
        return status
      end

      status[:status] = :healthy
      status[:details] = {
        model: ENV["OPENAI_EMBEDDING_MODEL"] || "text-embedding-ada-002",
        configured: true
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_bedrock
    status = { name: "AWS Bedrock (Claude)", status: :unknown, details: {} }

    begin
      if ENV["AWS_ACCESS_KEY_ID"].blank? || ENV["AWS_SECRET_ACCESS_KEY"].blank?
        status[:status] = :warning
        status[:error] = "AWS credentials not configured"
        return status
      end

      # Try to initialize Bedrock client
      bedrock_service = BedrockService.new(user: current_user, entity: current_entity)

      status[:status] = :healthy
      status[:details] = {
        region: ENV["AWS_REGION"] || "us-east-1",
        model: "claude-sonnet-4.5",
        configured: true
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_rag_system
    status = { name: "RAG System", status: :unknown, details: {} }

    begin
      total_stores = RagStore.count
      active_stores = RagStore.where(status: 'active').count
      system_stores = RagStore.where(store_type: 'system').count
      entity_stores = RagStore.where(store_type: 'entity').count

      # Check if RAG service can initialize
      rag_service = RagStoreService.new
      cache_stats = rag_service.cache_stats

      status[:status] = :healthy
      status[:details] = {
        total_stores: total_stores,
        active_stores: active_stores,
        system_stores: system_stores,
        entity_stores: entity_stores,
        cache_enabled: cache_stats[:enabled],
        cache_hit_rate: cache_stats[:hit_rate] ? "#{cache_stats[:hit_rate]}%" : "N/A",
        docling_available: DoclingBridgeService.available?
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_solid_queue
    status = { name: "SolidQueue (Background Jobs)", status: :unknown, details: {} }

    begin
      # Check if SolidQueue tables exist
      if ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
        # Count jobs in different states
        total_jobs = SolidQueue::Job.count
        pending_jobs = SolidQueue::Job.where(finished_at: nil).count
        completed_jobs = SolidQueue::Job.where.not(finished_at: nil).count

        # Count failed executions from the failed_executions table
        failed_jobs = ActiveRecord::Base.connection.table_exists?('solid_queue_failed_executions') ?
                        ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM solid_queue_failed_executions").first['count'].to_i : 0

        # Count scheduled jobs
        scheduled_jobs = ActiveRecord::Base.connection.table_exists?('solid_queue_scheduled_executions') ?
                          ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM solid_queue_scheduled_executions").first['count'].to_i : 0

        status[:status] = :healthy
        status[:details] = {
          total_jobs: total_jobs,
          pending_jobs: pending_jobs,
          completed_jobs: completed_jobs,
          failed_jobs: failed_jobs,
          scheduled_jobs: scheduled_jobs,
          configured: true
        }
      else
        status[:status] = :warning
        status[:error] = "SolidQueue tables not found"
      end
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def check_storage
    status = { name: "File Storage", status: :unknown, details: {} }

    begin
      storage_service = Rails.application.config.active_storage.service

      status[:status] = :healthy
      status[:details] = {
        service: storage_service.to_s,
        configured: true
      }
    rescue => e
      status[:status] = :unhealthy
      status[:error] = e.message
    end

    status
  end

  def calculate_overall_status(services)
    unhealthy_count = services.values.count { |s| s[:status] == :unhealthy }
    warning_count = services.values.count { |s| s[:status] == :warning }

    if unhealthy_count > 0
      :unhealthy
    elsif warning_count > 2
      :warning
    else
      :healthy
    end
  end
end
