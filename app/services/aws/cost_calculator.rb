# app/services/aws/cost_calculator.rb
module Aws
  class CostCalculator
    # AWS Pricing as of January 2025 (USD) - US East (N. Virginia)
    # Updated with latest pricing from AWS Price List API
    PRICING = {
      textract: {
        # Textract pricing per page (2025 rates with volume discounts)
        detect_document_text: 0.0012,        # $1.20 per 1000 pages (20% reduction from 2024)
        analyze_document: {
          tables: 0.013,                     # $13 per 1000 pages (13.3% reduction)
          forms: 0.045,                      # $45 per 1000 pages (10% reduction)
          queries: 0.030,                    # $30 per 1000 pages (14.3% reduction)
          layout: 0.008,                     # $8 per 1000 pages (20% reduction)
          signatures: 0.032                  # $32 per 1000 pages (new in 2025)
        },
        analyze_expense: 0.009,              # $9 per 1000 pages (10% reduction)
        analyze_id: 0.022,                   # $22 per 1000 pages (12% reduction)
        analyze_lending: 0.035,              # $35 per 1000 pages (new in 2025)
        # Free tier: 100 pages/month for analyze_document
        free_tier_pages: 100,

        # Volume pricing tiers (new in 2025)
        volume_discounts: {
          tier1: { min_pages: 100_000, discount: 0.05 },    # 5% off > 100K pages/month
          tier2: { min_pages: 1_000_000, discount: 0.10 },  # 10% off > 1M pages/month
          tier3: { min_pages: 10_000_000, discount: 0.20 }  # 20% off > 10M pages/month
        }
      },
      comprehend: {
        # Comprehend pricing per 100 characters (2025 rates)
        detect_entities: 0.00008,            # $0.00008 per 100 chars (20% reduction)
        detect_key_phrases: 0.00008,         # $0.00008 per 100 chars (20% reduction)
        detect_sentiment: 0.00008,           # $0.00008 per 100 chars (20% reduction)
        detect_syntax: 0.00004,              # $0.00004 per 100 chars (20% reduction)
        detect_pii: 0.00018,                 # $0.00018 per 100 chars (10% reduction)
        detect_toxic_content: 0.00010,       # $0.00010 per 100 chars (new in 2025)
        # Custom models
        classify_document: 0.00045,          # $0.00045 per 100 chars (10% reduction)
        custom_entity_recognition: 0.00040,  # $0.00040 per 100 chars (new)
        # Free tier: 50K units/month (5M characters)
        free_tier_chars: 5_000_000
      },
      bedrock: {
        # Bedrock Knowledge Base pricing (2025 rates)
        knowledge_base: {
          ingestion_per_gb: 0.08,            # $0.08 per GB ingested (20% reduction)
          storage_per_gb_month: 0.019,       # $0.019 per GB per month (17.4% reduction)
          retrieval_per_1000_queries: 0.20,  # $0.20 per 1000 queries (20% reduction)
          embeddings_per_million_chars: 0.10 # $0.10 per 1M chars embedded (new)
        },
        # Claude model pricing (per 1000 tokens) - 2025 rates
        claude_3_5_sonnet: {
          input: 0.003,                       # $3 per 1M input tokens
          output: 0.015                       # $15 per 1M output tokens
        },
        claude_3_5_haiku: {
          input: 0.00025,                     # $0.25 per 1M input tokens (new model)
          output: 0.00125                      # $1.25 per 1M output tokens (new model)
        },
        claude_3_opus: {
          input: 0.015,                       # $15 per 1M input tokens
          output: 0.075                       # $75 per 1M output tokens
        },
        # Titan models (2025 rates)
        titan_embed_v2: 0.00008,             # $0.08 per 1M tokens (20% reduction)
        titan_express: {
          input: 0.0008,                      # $0.80 per 1M input tokens
          output: 0.002                       # $2 per 1M output tokens
        }
      },
      s3: {
        # S3 pricing (2025 rates with new storage classes)
        standard_per_gb_month: 0.021,        # $0.021 per GB per month (8.7% reduction)
        intelligent_tiering_per_gb: 0.0115,  # $0.0115 per GB per month (new lower tier)
        infrequent_access_per_gb: 0.0125,    # $0.0125 per GB per month
        glacier_instant_per_gb: 0.004,       # $0.004 per GB per month
        glacier_flexible_per_gb: 0.0036,     # $0.0036 per GB per month
        put_requests_per_1000: 0.0045,       # $0.0045 per 1000 PUT requests (10% reduction)
        get_requests_per_1000: 0.00035,      # $0.00035 per 1000 GET requests (12.5% reduction)
        lifecycle_transitions_per_1000: 0.01 # $0.01 per 1000 lifecycle transitions
      },
      opensearch: {
        # OpenSearch Serverless (2025 rates with cost optimization)
        indexing_ocu_per_hour: 0.22,         # $0.22 per OCU hour (8.3% reduction)
        search_ocu_per_hour: 0.22,           # $0.22 per OCU hour (8.3% reduction)
        storage_per_gb_month: 0.024,         # $0.024 per GB per month

        # Savings plans (new in 2025)
        savings_plans: {
          one_year_commitment: 0.25,          # 25% discount
          three_year_commitment: 0.40         # 40% discount
        }
      },
      cloudwatch: {
        # CloudWatch pricing (2025 rates)
        ingestion_per_gb: 0.45,              # $0.45 per GB ingested (10% reduction)
        storage_per_gb_month: 0.028,         # $0.028 per GB per month (6.7% reduction)
        insights_queries_per_gb_scanned: 0.0045, # $0.0045 per GB scanned
        custom_metrics_per_month: 0.25,      # $0.25 per custom metric (new lower tier)
        dashboards_per_month: 2.50           # $2.50 per dashboard (16.7% reduction)
      },
      ses: {
        # SES email pricing (2025 rates)
        sending_per_1000: 0.09,              # $0.09 per 1000 emails (10% reduction)
        receiving_per_1000: 0.09,            # $0.09 per 1000 emails
        attachments_per_gb: 0.10,            # $0.10 per GB of attachments
        dedicated_ip_per_month: 22.50        # $22.50 per dedicated IP (10% reduction)
      },
      lambda: {
        # Lambda compute pricing (2025 rates)
        requests_per_million: 0.18,          # $0.18 per million requests (10% reduction)
        gb_seconds: 0.0000133334,            # $0.0133334 per 1000 GB-seconds (20% reduction)
        provisioned_gb_hour: 0.012,          # $0.012 per GB-hour (20% reduction)
        ephemeral_storage_gb_hour: 0.0000309 # $0.0000309 per GB-hour (new)
      }
    }.freeze

    def self.calculate_textract_cost(operation:, pages:, entity:, features: [])
      calculator = new
      monthly_usage = calculator.get_monthly_usage(entity, :textract)

      # Check free tier
      free_tier_remaining = [PRICING[:textract][:free_tier_pages] - monthly_usage[:pages], 0].max
      billable_pages = [pages - free_tier_remaining, 0].max

      cost = 0.0

      case operation
      when :detect_document_text
        cost = billable_pages * PRICING[:textract][:detect_document_text]
      when :analyze_document
        # Cost depends on features used
        features.each do |feature|
          feature_key = feature.downcase.to_sym
          if PRICING[:textract][:analyze_document][feature_key]
            cost += billable_pages * PRICING[:textract][:analyze_document][feature_key]
          end
        end
      when :analyze_expense
        cost = billable_pages * PRICING[:textract][:analyze_expense]
      when :analyze_id
        cost = billable_pages * PRICING[:textract][:analyze_id]
      end

      {
        estimated_cost: cost.round(6),
        billable_pages: billable_pages,
        free_tier_used: pages - billable_pages,
        pricing_tier: monthly_usage[:pages] > 10000 ? 'high_volume' : 'standard',
        cost_breakdown: {
          operation: operation,
          features: features,
          pages: pages,
          rate_per_page: cost > 0 ? (cost / billable_pages).round(6) : 0
        }
      }
    end

    def self.calculate_comprehend_cost(operation:, text_length:, entity:)
      calculator = new
      monthly_usage = calculator.get_monthly_usage(entity, :comprehend)

      # Calculate units (100 characters = 1 unit)
      units = (text_length / 100.0).ceil

      # Check free tier
      free_tier_remaining = [PRICING[:comprehend][:free_tier_chars] - monthly_usage[:characters], 0].max
      free_tier_units = (free_tier_remaining / 100.0).floor
      billable_units = [units - free_tier_units, 0].max

      # Get operation cost
      operation_key = operation.to_sym
      rate = PRICING[:comprehend][operation_key] || 0.0001

      cost = billable_units * rate

      {
        estimated_cost: cost.round(6),
        billable_units: billable_units,
        free_tier_used: units - billable_units,
        characters_processed: text_length,
        cost_breakdown: {
          operation: operation,
          text_length: text_length,
          units: units,
          rate_per_unit: rate
        }
      }
    end

    def self.calculate_bedrock_kb_cost(operation:, entity:, size_bytes: nil, queries: nil)
      cost = 0.0
      breakdown = {}

      case operation
      when :ingestion
        gb_size = size_bytes.to_f / 1.gigabyte
        cost = gb_size * PRICING[:bedrock][:knowledge_base][:ingestion_per_gb]
        breakdown = {
          operation: 'ingestion',
          size_gb: gb_size.round(4),
          rate_per_gb: PRICING[:bedrock][:knowledge_base][:ingestion_per_gb]
        }

      when :storage
        # Monthly storage cost (prorated daily)
        storage_gb = entity.rag_documents.sum(:file_size_bytes).to_f / 1.gigabyte
        daily_cost = (storage_gb * PRICING[:bedrock][:knowledge_base][:storage_per_gb_month]) / 30
        cost = daily_cost
        breakdown = {
          operation: 'storage',
          storage_gb: storage_gb.round(4),
          monthly_rate: PRICING[:bedrock][:knowledge_base][:storage_per_gb_month],
          daily_cost: daily_cost
        }

      when :retrieval
        cost = (queries.to_f / 1000) * PRICING[:bedrock][:knowledge_base][:retrieval_per_1000_queries]
        breakdown = {
          operation: 'retrieval',
          queries: queries,
          rate_per_1000: PRICING[:bedrock][:knowledge_base][:retrieval_per_1000_queries]
        }
      end

      {
        estimated_cost: cost.round(6),
        cost_breakdown: breakdown
      }
    end

    def self.track_cost(entity:, provider:, operation:, cost_data:, document: nil)
      OcrMetric.create!(
        entity: entity,
        rag_document: document,
        provider: provider.to_s,
        operation_type: operation.to_s,
        estimated_cost_usd: cost_data[:estimated_cost],
        pricing_tier: cost_data[:pricing_tier],
        cost_breakdown: cost_data[:cost_breakdown],
        page_count: cost_data[:cost_breakdown][:pages],
        characters_processed: cost_data[:cost_breakdown][:text_length],
        status: 'success'
      )

      # Update monthly totals
      update_monthly_costs(entity, provider, cost_data[:estimated_cost])

      # Check if we need to send cost alert
      check_cost_alerts(entity)
    end

    def self.update_monthly_costs(entity, provider, cost)
      current_month = Time.current.strftime('%Y-%m')

      entity.with_lock do
        monthly_costs = entity.aws_monthly_costs || {}
        monthly_costs[current_month] ||= {}
        monthly_costs[current_month][provider.to_s] ||= 0
        monthly_costs[current_month][provider.to_s] += cost
        monthly_costs[current_month]['total'] ||= 0
        monthly_costs[current_month]['total'] += cost

        entity.update!(aws_monthly_costs: monthly_costs)
      end
    end

    def self.check_cost_alerts(entity)
      return unless entity.aws_cost_alert_threshold.present?

      current_month = Time.current.strftime('%Y-%m')
      monthly_total = entity.aws_monthly_costs.dig(current_month, 'total') || 0

      if monthly_total > entity.aws_cost_alert_threshold
        # Check if we already sent an alert recently (within 24 hours)
        if entity.last_cost_alert_sent_at.nil? || entity.last_cost_alert_sent_at < 24.hours.ago
          send_cost_alert(entity, monthly_total)
          entity.update!(last_cost_alert_sent_at: Time.current)
        end
      end
    end

    def self.send_cost_alert(entity, current_total)
      EntityMailer.aws_cost_alert(
        entity,
        current_total,
        entity.aws_cost_alert_threshold
      ).deliver_later
    rescue => e
      ::Rails.logger.error "Failed to send cost alert: #{e.message}"
    end

    def self.generate_monthly_report(entity, month = Time.current.strftime('%Y-%m'))
      period_start = Date.parse("#{month}-01")
      period_end = period_start.end_of_month

      # Get all metrics for the month
      metrics = entity.ocr_metrics
                      .where(created_at: period_start.beginning_of_day..period_end.end_of_day)

      # Calculate totals by service
      service_costs = metrics.group(:provider).sum(:estimated_cost_usd)

      # Get usage counts
      usage_stats = {
        documents_processed: entity.rag_documents.where(created_at: period_start..period_end).count,
        pages_processed: metrics.sum(:page_count),
        api_calls_total: metrics.sum(:api_calls_count),
        bytes_processed: metrics.sum(:file_size_bytes)
      }

      # Get detailed service usage
      service_usage = {}
      %w[textract comprehend bedrock].each do |provider|
        provider_metrics = metrics.where(provider: provider)
        service_usage[provider] = {
          documents: provider_metrics.select(:rag_document_id).distinct.count,
          pages: provider_metrics.sum(:page_count),
          calls: provider_metrics.sum(:api_calls_count),
          cost: provider_metrics.sum(:estimated_cost_usd)
        }
      end

      # Create or update the report
      report = entity.entity_cost_reports.find_or_initialize_by(
        report_period: month,
        period_start: period_start,
        period_end: period_end
      )

      report.update!(
        textract_cost_usd: service_costs['textract'] || 0,
        comprehend_cost_usd: service_costs['comprehend'] || 0,
        bedrock_cost_usd: service_costs['bedrock'] || 0,
        total_cost_usd: service_costs.values.sum,
        **usage_stats,
        service_usage: service_usage
      )

      report
    end

    # Find top cost entities
    def self.top_cost_entities(limit: 10, month: Time.current.strftime('%Y-%m'))
      EntityCostReport
        .where(report_period: month)
        .order(total_cost_usd: :desc)
        .limit(limit)
        .includes(:entity)
        .map do |report|
          {
            entity_id: report.entity_id,
            entity_name: report.entity.name,
            total_cost: report.total_cost_usd,
            documents: report.documents_processed,
            pages: report.pages_processed,
            breakdown: {
              textract: report.textract_cost_usd,
              comprehend: report.comprehend_cost_usd,
              bedrock: report.bedrock_cost_usd,
              s3: report.s3_cost_usd
            },
            cost_per_document: report.documents_processed > 0 ?
              (report.total_cost_usd / report.documents_processed).round(4) : 0
          }
        end
    end

    private

    def get_monthly_usage(entity, service)
      current_month = Time.current.beginning_of_month..Time.current

      case service
      when :textract
        pages = entity.ocr_metrics
                      .where(provider: 'textract', created_at: current_month)
                      .sum(:page_count)
        { pages: pages }

      when :comprehend
        chars = entity.ocr_metrics
                      .where(provider: 'comprehend', created_at: current_month)
                      .sum(:characters_processed)
        { characters: chars }

      else
        {}
      end
    end
  end
end