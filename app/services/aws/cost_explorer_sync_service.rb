# frozen_string_literal: true

# AwsCostExplorerSyncService
#
# Syncs real AWS costs from Cost Explorer API to platform economics.
# This bridges the gap between estimated costs and actual AWS bills.
#
# WHAT THIS SOLVES:
# - EntityCostTracker estimates costs at time of usage
# - AWS actually bills slightly differently (reserved capacity, etc.)
# - This service reconciles our estimates with reality
#
# USAGE:
#   Aws::CostExplorerSyncService.sync_daily!
#   Aws::CostExplorerSyncService.sync_monthly!(year: 2026, month: 1)
#
module Aws
  class CostExplorerSyncService
    # AWS Cost Categories we track
    COST_CATEGORIES = {
      'Amazon Bedrock' => :ai_compute,
      'Amazon Simple Email Service' => :email,
      'Amazon EC2 Container Service' => :compute,
      'AWS Lambda' => :compute,
      'Amazon Simple Storage Service' => :storage,
      'Amazon RDS Service' => :database,
      'Amazon CloudWatch' => :monitoring,
      'Amazon OpenSearch Service' => :search,
      'Amazon Textract' => :document_processing,
      'Amazon Comprehend' => :document_processing,
      'Amazon CloudFront' => :cdn,
      'AWS Data Transfer' => :network
    }.freeze

    class << self
      # Sync yesterday's costs (run daily via cron)
      def sync_daily!
        yesterday = Date.yesterday
        sync_date_range(
          start_date: yesterday,
          end_date: yesterday,
          granularity: 'DAILY'
        )
      end

      # Sync a full month (for reconciliation)
      def sync_monthly!(year:, month:)
        start_date = Date.new(year, month, 1)
        end_date = start_date.end_of_month
        
        sync_date_range(
          start_date: start_date,
          end_date: end_date,
          granularity: 'MONTHLY'
        )
      end

      # Get current month-to-date costs
      def current_month_costs
        start_date = Date.current.beginning_of_month
        end_date = Date.yesterday # Cost Explorer has 1-day lag
        
        return {} if end_date < start_date
        
        fetch_costs(
          start_date: start_date,
          end_date: end_date,
          granularity: 'MONTHLY'
        )
      end

      # Get cost forecast for current month
      def forecast_monthly_costs
        client = cost_explorer_client
        return nil unless client
        
        begin
          response = client.get_cost_forecast(
            time_period: {
              start: Date.current.to_s,
              end: Date.current.end_of_month.to_s
            },
            metric: 'UNBLENDED_COST',
            granularity: 'MONTHLY'
          )
          
          {
            forecast_amount: response.total.amount.to_f.round(2),
            currency: response.total.unit,
            confidence_level: '80%', # AWS default
            fetched_at: Time.current
          }
        rescue StandardError => e
          Rails.logger.error "[CostExplorerSync] Forecast error: #{e.message}"
          nil
        end
      end

      # Compare our estimates vs actual AWS costs
      def reconciliation_report(start_date:, end_date:)
        # Get our tracked costs
        our_estimates = PlatformCost.where(
          recorded_at: start_date..end_date
        ).group(:category).sum(:amount)
        
        # Get actual AWS costs
        aws_actual = fetch_costs(
          start_date: start_date,
          end_date: end_date,
          granularity: 'MONTHLY'
        )
        
        # Build reconciliation
        reconciliation = {}
        
        COST_CATEGORIES.values.uniq.each do |category|
          cat_str = category.to_s
          estimated = our_estimates[cat_str] || 0
          actual = aws_actual.dig(:by_category, cat_str) || 0
          variance = actual - estimated
          variance_pct = estimated > 0 ? ((variance / estimated) * 100).round(2) : 0
          
          reconciliation[category] = {
            estimated: estimated.round(2),
            actual: actual.round(2),
            variance: variance.round(2),
            variance_percentage: variance_pct,
            status: variance_status(variance_pct)
          }
        end
        
        {
          period: "#{start_date} to #{end_date}",
          total_estimated: our_estimates.values.sum.round(2),
          total_actual: (aws_actual[:total] || 0).round(2),
          by_category: reconciliation,
          generated_at: Time.current
        }
      end

      private

      def sync_date_range(start_date:, end_date:, granularity:)
        costs = fetch_costs(
          start_date: start_date,
          end_date: end_date,
          granularity: granularity
        )
        
        return { success: false, error: 'Failed to fetch costs' } unless costs
        
        # Record to PlatformCost
        costs[:by_service].each do |service, amount|
          category = COST_CATEGORIES[service] || :other
          
          PlatformCost.create!(
            category: category.to_s,
            amount: amount,
            description: "AWS #{service} (synced from Cost Explorer)",
            recorded_at: end_date.to_time,
            period_start: start_date,
            period_end: end_date,
            metadata: {
              source: 'aws_cost_explorer',
              aws_service: service,
              granularity: granularity
            }
          )
        end
        
        # Invalidate economics cache
        Rails.cache.delete("platform_economics:current")
        
        {
          success: true,
          period: "#{start_date} to #{end_date}",
          total_synced: costs[:total],
          services_synced: costs[:by_service].keys.count
        }
      rescue StandardError => e
        Rails.logger.error "[CostExplorerSync] Sync failed: #{e.message}"
        { success: false, error: e.message }
      end

      def fetch_costs(start_date:, end_date:, granularity:)
        client = cost_explorer_client
        return nil unless client
        
        begin
          response = client.get_cost_and_usage(
            time_period: {
              start: start_date.to_s,
              end: (end_date + 1.day).to_s # AWS end is exclusive
            },
            granularity: granularity,
            metrics: ['UnblendedCost'],
            group_by: [
              {
                type: 'DIMENSION',
                key: 'SERVICE'
              }
            ]
          )
          
          parse_cost_response(response)
        rescue StandardError => e
          Rails.logger.error "[CostExplorerSync] Fetch error: #{e.message}"
          nil
        end
      end

      def parse_cost_response(response)
        by_service = {}
        by_category = Hash.new(0)
        total = 0
        
        response.results_by_time.each do |result|
          result.groups.each do |group|
            service_name = group.keys.first
            amount = group.metrics['UnblendedCost'].amount.to_f
            
            by_service[service_name] ||= 0
            by_service[service_name] += amount
            
            category = COST_CATEGORIES[service_name] || :other
            by_category[category.to_s] += amount
            
            total += amount
          end
        end
        
        {
          total: total.round(2),
          by_service: by_service.transform_values { |v| v.round(2) },
          by_category: by_category.transform_values { |v| v.round(2) }
        }
      end

      def cost_explorer_client
        # Check if we have AWS credentials configured
        return nil unless ENV['AWS_ACCESS_KEY_ID'].present? || 
                          Rails.application.credentials.dig(:aws, :access_key_id).present?
        
        require 'aws-sdk-costexplorer'
        
        Aws::CostExplorer::Client.new(
          region: 'us-east-1' # Cost Explorer is only available in us-east-1
        )
      rescue LoadError
        Rails.logger.warn "[CostExplorerSync] aws-sdk-costexplorer gem not installed"
        nil
      rescue StandardError => e
        Rails.logger.error "[CostExplorerSync] Failed to create client: #{e.message}"
        nil
      end

      def variance_status(variance_pct)
        case variance_pct.abs
        when 0..5 then :accurate
        when 5..15 then :minor_variance
        when 15..30 then :significant_variance
        else :major_variance
        end
      end
    end
  end
end
