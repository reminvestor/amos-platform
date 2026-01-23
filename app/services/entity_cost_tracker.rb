# app/services/entity_cost_tracker.rb
class EntityCostTracker
  # Comprehensive cost tracking for all services per entity

  # Service categories we track (2025 pricing)
  COST_CATEGORIES = {
    # AI & LLM Services (2025 rates)
    ai_chat: {
      bedrock_claude_3_5_sonnet: { per_1k_input_tokens: 0.003, per_1k_output_tokens: 0.015 },
      bedrock_claude_3_5_haiku: { per_1k_input_tokens: 0.00025, per_1k_output_tokens: 0.00125 },
      bedrock_claude_4_5_haiku: { per_1k_input_tokens: 0.00020, per_1k_output_tokens: 0.00100 },  # Latest Haiku 4.5
      bedrock_claude_3_opus: { per_1k_input_tokens: 0.015, per_1k_output_tokens: 0.075 },
      bedrock_titan_express: { per_1k_input_tokens: 0.0008, per_1k_output_tokens: 0.002 },
      openai_gpt4_turbo: { per_1k_input_tokens: 0.01, per_1k_output_tokens: 0.03 },
      openai_gpt4o: { per_1k_input_tokens: 0.005, per_1k_output_tokens: 0.015 },
      embeddings_titan_v2: { per_1k_tokens: 0.00008 },
      embeddings_ada_v3: { per_1k_tokens: 0.00013 }
    },

    # Communication Services (2025 rates)
    email: {
      aws_ses: { per_email: 0.00009, per_gb_attachment: 0.10 },  # 10% reduction
      mailgun: { per_email: 0.00022, monthly_base: 32.00 },      # Reduced pricing
      sendgrid: { per_email: 0.00018 }                           # Competitive pricing
    },

    sms: {
      aws_sns: { per_sms_us: 0.00581, per_sms_intl: 0.045 },    # 10% reduction
      twilio: { per_sms: 0.0071 },                               # Competitive reduction
      aws_pinpoint: { per_sms: 0.00600 }                         # New option
    },

    voice: {
      aws_polly: { per_1m_chars: 3.60, neural_per_1m_chars: 14.40 },  # 10% reduction
      aws_connect: { per_minute: 0.016 },                              # Reduced
      twilio_voice: { per_minute: 0.013 },                             # Competitive
      aws_transcribe: { per_minute: 0.024 }                            # Speech-to-text
    },

    # Storage & Database (2025 rates)
    storage: {
      s3_standard: { per_gb_month: 0.021, per_1k_requests: 0.00035 },  # Reduced
      s3_intelligent: { per_gb_month: 0.0115 },                        # New lower tier
      s3_glacier_instant: { per_gb_month: 0.004 },                     # Fast archive
      active_storage: { per_gb_month: 0.09 },                          # Rails Active Storage
      database_storage: { per_gb_month: 0.103 }                        # RDS storage (reduced)
    },

    database: {
      rds_compute: { per_hour_t3_small: 0.031, per_hour_t3_medium: 0.061 },  # Reduced
      rds_iops: { per_1k_iops: 0.09 },                                       # 10% reduction
      aurora_serverless_v2: { per_acu_hour: 0.108 },                         # 10% reduction
      dynamodb: { per_million_reads: 0.225, per_million_writes: 1.125 }     # 10% reduction
    },

    # Content Delivery & Networking (2025 rates)
    cdn: {
      cloudfront: { per_gb_transfer: 0.077, per_10k_requests: 0.0068 },     # Reduced
      landing_page_views: { per_1k_views: 0.009 },                          # Optimized
      image_optimization: { per_1k_transforms: 0.85 }                       # New service
    },

    bandwidth: {
      data_transfer_out: { first_10tb_per_gb: 0.081, next_40tb_per_gb: 0.077 },  # Reduced
      data_transfer_between_regions: { per_gb: 0.018 },                          # 10% reduction
      vpc_endpoint: { per_hour: 0.01, per_gb_processed: 0.01 }                   # New
    },

    # Background Processing (2025 rates)
    compute: {
      sidekiq_jobs: { per_1k_jobs: 0.045 },                                # Optimized
      lambda: { per_1m_requests: 0.18, per_gb_second: 0.0000133334 },      # 20% reduction
      ecs_fargate: { per_vcpu_hour: 0.03643, per_gb_hour: 0.004001 },     # 10% reduction
      batch_jobs: { per_vcpu_hour: 0.025 }                                  # AWS Batch
    },

    # Third-party Integrations (2025 rates)
    integrations: {
      stripe_api: { per_api_call: 0.000009, transaction_fee_percent: 2.7 },  # Updated
      hubspot_api: { monthly_base: 45.00, per_1k_contacts: 9.00 },          # Reduced
      google_maps: { per_1k_requests: 6.30 },                               # 10% reduction
      webhook_calls: { per_1k_calls: 0.009 },                               # Optimized
      zapier_tasks: { per_1k_tasks: 20.00 }                                 # New integration
    },

    # Search & Analytics (2025 rates)
    search: {
      elasticsearch: { per_hour_t3_small: 0.032 },                          # Reduced
      opensearch_serverless: { per_ocu_hour: 0.22 },                        # 8.3% reduction
      algolia: { per_1k_searches: 0.45 },                                   # Competitive
      bedrock_kb_retrieval: { per_1k_queries: 0.20 }                        # New RAG option
    },

    analytics: {
      cloudwatch_logs: { per_gb_ingested: 0.45, per_gb_stored_month: 0.028 },  # Reduced
      custom_metrics: { per_metric_month: 0.25 },                              # New tier
      dashboards: { per_dashboard_month: 2.50 },                               # 16.7% reduction
      insights_queries: { per_gb_scanned: 0.0045 },                            # Query costs
      comprehend: {
        detect_entities: { per_100_chars: 0.00008 },
        detect_sentiment: { per_100_chars: 0.00008 },
        detect_key_phrases: { per_100_chars: 0.00008 },
        detect_pii: { per_100_chars: 0.00008 },
        classify_document: { per_100_chars: 0.00008 }
      }
    },

    # Development & Testing (2025 rates)
    development: {
      ci_cd_minutes: { per_minute: 0.007 },                                 # Optimized
      staging_environment: { per_hour: 0.09 },                              # 10% reduction
      load_testing: { per_test_hour: 0.90 },                                # Reduced
      code_scanning: { per_1k_lines: 0.15 }                                 # Security scanning
    },

    # OCR & Document Processing (2025 rates)
    ocr: {
      textract_pages: { per_page_simple: 0.0012, per_page_tables: 0.013 },
      docling_pages: { per_page: 0.001 },                                   # Estimated
      comprehend_analysis: { per_100_chars: 0.00008 }
    }
  }.freeze

  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # Track any service usage
  def track_usage(category:, service:, usage_type:, quantity:, metadata: {})
    # Calculate cost
    rate = COST_CATEGORIES.dig(category, service, usage_type)

    if rate.nil?
      Rails.logger.warn "Unknown cost configuration: #{category}/#{service}/#{usage_type}"
      return
    end

    cost = calculate_cost(rate, quantity, metadata)

    # Create usage record
    EntityUsageMetric.create!(
      entity: entity,
      category: category.to_s,
      service: service.to_s,
      usage_type: usage_type.to_s,
      quantity: quantity,
      rate: rate,
      calculated_cost_usd: cost,
      metadata: metadata,
      tracked_at: Time.current
    )

    # Update daily/monthly aggregates
    update_cost_aggregates(category, service, cost)

    # Check thresholds
    check_cost_thresholds(category, cost)

    cost
  end

  # Track Scout chat conversation costs
  def track_scout_conversation(message_count:, input_tokens:, output_tokens:, model: 'qwen3-next-80b')
    model_rates = case model
    when 'claude-3-5-sonnet', 'claude-sonnet-3-5'
      { input: 0.003, output: 0.015 }
    when 'claude-3-5-haiku', 'claude-haiku-3-5'
      { input: 0.00025, output: 0.00125 }  # New Claude 3.5 Haiku pricing
    when 'claude-3-opus', 'claude-opus-3'
      { input: 0.015, output: 0.075 }
    when 'claude-4-5-haiku'  # Claude 4.5 Haiku (latest version)
      { input: 0.00020, output: 0.00100 }  # Even more optimized pricing
    when 'qwen3-next-80b', 'qwen3-235b'  # Qwen3-Next via Fireworks AI (much cheaper)
      { input: 0.00020, output: 0.00080 }  # ~15x cheaper than Claude Sonnet
    else
      { input: 0.003, output: 0.015 }  # Default to Sonnet pricing
    end

    input_cost = (input_tokens / 1000.0) * model_rates[:input]
    output_cost = (output_tokens / 1000.0) * model_rates[:output]
    total_cost = input_cost + output_cost

    track_usage(
      category: :ai_chat,
      service: :bedrock_claude,
      usage_type: :conversation,
      quantity: message_count,
      metadata: {
        model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        input_cost: input_cost.round(6),
        output_cost: output_cost.round(6),
        total_cost: total_cost.round(6)
      }
    )
  end

  # Track email sending costs
  def track_email_sent(recipient_count:, provider: :aws_ses, attachment_size_mb: 0)
    base_cost = COST_CATEGORIES[:email][provider][:per_email] * recipient_count
    attachment_cost = 0

    if attachment_size_mb > 0 && provider == :aws_ses
      attachment_cost = (attachment_size_mb / 1024.0) * COST_CATEGORIES[:email][provider][:per_gb_attachment]
    end

    track_usage(
      category: :email,
      service: provider,
      usage_type: :send,
      quantity: recipient_count,
      metadata: {
        attachment_size_mb: attachment_size_mb,
        base_cost: base_cost,
        attachment_cost: attachment_cost,
        total_cost: base_cost + attachment_cost
      }
    )
  end

  # Track landing page views/CDN costs
  def track_landing_page_view(page_id:, bandwidth_mb:)
    # CDN request cost
    request_cost = COST_CATEGORIES[:cdn][:landing_page_views][:per_1k_views] / 1000.0

    # Bandwidth cost
    bandwidth_gb = bandwidth_mb / 1024.0
    bandwidth_cost = bandwidth_gb * COST_CATEGORIES[:cdn][:cloudfront][:per_gb_transfer]

    track_usage(
      category: :cdn,
      service: :cloudfront,
      usage_type: :landing_page_view,
      quantity: 1,
      metadata: {
        landing_page_id: page_id,
        bandwidth_mb: bandwidth_mb,
        request_cost: request_cost,
        bandwidth_cost: bandwidth_cost,
        total_cost: request_cost + bandwidth_cost
      }
    )
  end

  # Track background job processing
  def track_job_execution(job_class:, duration_seconds:, memory_mb:)
    # Estimate compute cost based on duration and memory
    compute_units = (duration_seconds / 3600.0) * (memory_mb / 1024.0)
    cost = compute_units * 0.05 # Rough estimate

    track_usage(
      category: :compute,
      service: :sidekiq_jobs,
      usage_type: :execution,
      quantity: 1,
      metadata: {
        job_class: job_class,
        duration_seconds: duration_seconds,
        memory_mb: memory_mb,
        compute_units: compute_units,
        estimated_cost: cost
      }
    )
  end

  # Track third-party API calls
  def track_integration_api_call(integration:, endpoint:, response_time_ms:)
    cost = case integration
    when :stripe
      COST_CATEGORIES[:integrations][:stripe_api][:per_api_call]
    when :hubspot
      0.00001 # Estimated per-call cost based on monthly plan
    else
      0.00001 # Default cost per API call
    end

    track_usage(
      category: :integrations,
      service: integration,
      usage_type: :api_call,
      quantity: 1,
      metadata: {
        endpoint: endpoint,
        response_time_ms: response_time_ms,
        cost: cost
      }
    )
  end

  # Get entity's current month costs
  def current_month_summary
    start_date = Time.current.beginning_of_month

    EntityUsageMetric
      .where(entity: entity, tracked_at: start_date..Time.current)
      .group(:category, :service)
      .sum(:calculated_cost_usd)
      .transform_values { |v| v.round(2) }
  end

  # Get detailed breakdown for reporting
  def detailed_cost_breakdown(start_date: 30.days.ago, end_date: Time.current)
    metrics = EntityUsageMetric.where(
      entity: entity,
      tracked_at: start_date..end_date
    )

    {
      total_cost: metrics.sum(:calculated_cost_usd).round(2),
      by_category: metrics.group(:category).sum(:calculated_cost_usd),
      by_service: metrics.group(:category, :service).sum(:calculated_cost_usd),
      by_day: metrics.group_by_day(:tracked_at).sum(:calculated_cost_usd),
      top_costs: top_cost_items(metrics),
      usage_trends: calculate_trends(metrics)
    }
  end

  # Find most expensive operations
  def top_cost_items(metrics = nil)
    metrics ||= EntityUsageMetric.where(entity: entity, tracked_at: 30.days.ago..Time.current)

    metrics
      .select('category, service, usage_type, SUM(calculated_cost_usd) as total_cost, COUNT(*) as usage_count')
      .group(:category, :service, :usage_type)
      .order('total_cost DESC')
      .limit(10)
      .map do |item|
        {
          category: item.category,
          service: item.service,
          usage_type: item.usage_type,
          total_cost: item.total_cost.round(2),
          usage_count: item.usage_count,
          avg_cost: (item.total_cost / item.usage_count).round(4)
        }
      end
  end

  # Compare entity costs to average
  def benchmark_against_peers
    entity_size = entity.contacts.count

    # Find similar-sized entities (within 20% of contact count)
    peer_entities = Entity.joins(:contacts)
                          .group('entities.id')
                          .having('COUNT(contacts.id) BETWEEN ? AND ?',
                                  entity_size * 0.8, entity_size * 1.2)
                          .where.not(id: entity.id)
                          .limit(20)
                          .pluck(:id)

    return nil if peer_entities.empty?

    # Get average costs for peer group
    peer_avg = EntityUsageMetric
      .where(entity_id: peer_entities, tracked_at: 30.days.ago..Time.current)
      .group(:category)
      .average(:calculated_cost_usd)

    # Get this entity's costs
    entity_costs = EntityUsageMetric
      .where(entity: entity, tracked_at: 30.days.ago..Time.current)
      .group(:category)
      .sum(:calculated_cost_usd)

    # Compare
    comparison = {}
    entity_costs.each do |category, cost|
      avg = peer_avg[category] || 0
      comparison[category] = {
        entity_cost: cost.round(2),
        peer_average: avg.round(2),
        difference: (cost - avg).round(2),
        percent_difference: avg > 0 ? ((cost - avg) / avg * 100).round(1) : 0
      }
    end

    {
      entity_size: entity_size,
      peer_group_size: peer_entities.size,
      comparison: comparison,
      total_vs_average: {
        entity_total: entity_costs.values.sum.round(2),
        peer_average: peer_avg.values.sum.round(2)
      }
    }
  end

  private

  def calculate_cost(rate, quantity, metadata)
    # Handle percentage-based costs (like Stripe fees)
    if rate.is_a?(Hash) && rate[:percent]
      base_amount = metadata[:amount] || 0
      (base_amount * rate[:percent] / 100.0) + (rate[:fixed] || 0)
    # Handle per-unit pricing hashes
    elsif rate.is_a?(Hash)
      # Extract the numeric rate from hash (e.g., { per_100_chars: 0.00008 })
      unit_rate = rate.values.first
      unit_rate * quantity
    else
      rate * quantity
    end
  end

  def update_cost_aggregates(category, service, cost)
    # Update daily aggregate
    today = Date.current
    daily_key = "#{category}:#{service}:#{today}"

    Rails.cache.increment("entity_cost:#{entity.id}:#{daily_key}", cost.to_f)

    # Update monthly aggregate
    monthly_key = "#{category}:#{service}:#{today.strftime('%Y-%m')}"
    Rails.cache.increment("entity_cost:#{entity.id}:monthly:#{monthly_key}", cost.to_f)
  end

  def check_cost_thresholds(category, cost)
    # Check if this category has a threshold
    threshold = entity.cost_thresholds&.dig(category.to_s)
    return unless threshold

    current_month_cost = EntityUsageMetric
      .where(entity: entity, category: category, tracked_at: Time.current.beginning_of_month..Time.current)
      .sum(:calculated_cost_usd)

    if current_month_cost > threshold
      notify_threshold_exceeded(category, current_month_cost, threshold)
    end
  end

  def calculate_trends(metrics)
    # Calculate week-over-week trends
    current_week = metrics.where(tracked_at: 1.week.ago..Time.current).sum(:calculated_cost_usd)
    previous_week = metrics.where(tracked_at: 2.weeks.ago..1.week.ago).sum(:calculated_cost_usd)

    {
      weekly_change: current_week - previous_week,
      weekly_change_percent: previous_week > 0 ? ((current_week - previous_week) / previous_week * 100).round(1) : 0,
      projection_30_days: current_week * 4.3 # Rough monthly projection
    }
  end

  def notify_threshold_exceeded(category, current_cost, threshold)
    Rails.logger.warn "Cost threshold exceeded for #{entity.name}: #{category} = $#{current_cost} (threshold: $#{threshold})"

    # Send notification (implement based on your notification system)
    # EntityMailer.cost_threshold_alert(entity, category, current_cost, threshold).deliver_later
  end
end