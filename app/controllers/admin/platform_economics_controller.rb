# frozen_string_literal: true

module Admin
  class PlatformEconomicsController < Admin::BaseController
    before_action :ensure_admin!

    def index
      @economics = PlatformEconomicsService.dashboard
    rescue => e
      Rails.logger.error "[PlatformEconomics] Dashboard error: #{e.message}"
      @economics = empty_economics
      flash.now[:alert] = "Error loading economics data: #{e.message}"
    end

    def refresh
      # Clear cache to force fresh calculation
      Rails.cache.delete("platform_economics:current")
      
      # Optionally sync from AWS Cost Explorer
      if params[:sync_aws]
        result = Aws::CostExplorerSyncService.sync_daily!
        if result[:success]
          render json: { success: true, message: "Economics refreshed and AWS costs synced" }
        else
          render json: { success: true, message: "Economics refreshed (AWS sync failed: #{result[:error]})" }
        end
      else
        render json: { success: true, message: "Economics cache cleared" }
      end
    rescue => e
      render json: { success: false, error: e.message }, status: 500
    end

    def export
      @economics = PlatformEconomicsService.dashboard
      
      respond_to do |format|
        format.csv do
          send_data generate_csv, 
                    filename: "platform_economics_#{Date.current}.csv",
                    type: 'text/csv'
        end
        format.json do
          render json: @economics
        end
      end
    end

    def reconciliation
      start_date = params[:start_date]&.to_date || 30.days.ago.to_date
      end_date = params[:end_date]&.to_date || Date.yesterday

      @report = Aws::CostExplorerSyncService.reconciliation_report(
        start_date: start_date,
        end_date: end_date
      )
    rescue => e
      Rails.logger.error "[PlatformEconomics] Reconciliation error: #{e.message}"
      flash[:alert] = "Error generating reconciliation: #{e.message}"
      redirect_to admin_platform_economics_path
    end

    private

    def ensure_admin!
      unless current_user&.admin?
        flash[:alert] = "You must be an admin to access this page."
        redirect_to root_path
      end
    end

    def empty_economics
      {
        financials: {
          monthly_revenue: 0,
          monthly_costs: 0,
          profit_margin: 0,
          runway_months: 0,
          profit_ratio: 0
        },
        token_economy: {
          total_staked: 0,
          daily_emission: 16_000,
          decay_rate: 0.10,
          decay_status: 'unknown',
          halving_multiplier: 1.0
        },
        cost_breakdown: {},
        revenue_breakdown: {},
        equations: {},
        generated_at: Time.current
      }
    end

    def generate_csv
      require 'csv'
      
      CSV.generate(headers: true) do |csv|
        csv << ['Metric', 'Value', 'Category']
        
        # Financials
        csv << ['Monthly Revenue', @economics[:financials][:monthly_revenue], 'Financials']
        csv << ['Monthly Costs', @economics[:financials][:monthly_costs], 'Financials']
        csv << ['Profit Margin', @economics[:financials][:profit_margin], 'Financials']
        csv << ['Profit Ratio', @economics[:financials][:profit_ratio], 'Financials']
        csv << ['Runway Months', @economics[:financials][:runway_months], 'Financials']
        
        # Token Economy
        csv << ['Total Staked', @economics[:token_economy][:total_staked], 'Token Economy']
        csv << ['Daily Emission', @economics[:token_economy][:daily_emission], 'Token Economy']
        csv << ['Decay Rate', @economics[:token_economy][:decay_rate], 'Token Economy']
        csv << ['Decay Status', @economics[:token_economy][:decay_status], 'Token Economy']
        csv << ['Halving Multiplier', @economics[:token_economy][:halving_multiplier], 'Token Economy']
        
        # Cost Breakdown
        @economics[:cost_breakdown]&.each do |category, amount|
          csv << [category.to_s.humanize, amount, 'Cost Breakdown']
        end
        
        # Revenue Breakdown
        @economics[:revenue_breakdown]&.each do |source, amount|
          csv << [source.to_s.humanize, amount, 'Revenue Breakdown']
        end
      end
    end

    # Helper methods exposed to view
    helper_method :profit_status_text, :profit_color, :decay_badge_color, 
                  :cost_icon, :revenue_icon, :cost_percentage, :revenue_percentage

    def profit_status_text(ratio)
      return "No data" if ratio.nil?
      
      case ratio
      when 0.20..Float::INFINITY then "Excellent"
      when 0.10...0.20 then "Healthy"
      when 0.0...0.10 then "Break-even"
      when -0.10...0.0 then "Slight Loss"
      else "Significant Loss"
      end
    end

    def profit_color(ratio)
      return "secondary" if ratio.nil?
      
      case ratio
      when 0.10..Float::INFINITY then "success"
      when 0.0...0.10 then "warning"
      else "danger"
      end
    end

    def decay_badge_color(status)
      case status&.to_s
      when "excellent" then "success"
      when "healthy" then "primary"
      when "moderate" then "warning"
      when "elevated" then "danger"
      else "secondary"
      end
    end

    def cost_icon(category)
      case category.to_s
      when /ai|compute/ then "cpu"
      when /email/ then "envelope"
      when /storage/ then "hdd"
      when /database/ then "server"
      when /network/ then "globe"
      else "tag"
      end
    end

    def revenue_icon(source)
      case source.to_s
      when /subscription/ then "calendar-check"
      when /compute/ then "lightning"
      when /payment/ then "credit-card"
      else "currency-dollar"
      end
    end

    def cost_percentage(amount, total)
      return 0 if total.nil? || total.zero?
      [(amount.to_f / total * 100).round(1), 100].min
    end

    def revenue_percentage(amount, total)
      return 0 if total.nil? || total.zero?
      [(amount.to_f / total * 100).round(1), 100].min
    end
  end
end
