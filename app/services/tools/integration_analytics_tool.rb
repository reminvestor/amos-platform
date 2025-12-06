# frozen_string_literal: true

module Tools
  class IntegrationAnalyticsTool < BaseTool
    def self.metadata
      {
        name: "integration_analytics",
        description: "Get analytics and aggregated metrics from integrations like Stripe, QuickBooks, etc. Use this for questions about sales, revenue, transactions, customers over time periods. Returns summarized data instead of raw records.",
        category: "analytics",
        input_schema: {
          type: "object",
          properties: {
            integration: {
              type: "string",
              description: 'Integration to analyze (e.g., "stripe", "quickbooks")'
            },
            metric_type: {
              type: "string",
              enum: ["sales", "revenue", "transactions", "customers", "subscriptions", "invoices", "refunds"],
              description: "Type of metric to analyze"
            },
            time_period: {
              type: "string",
              enum: ["today", "yesterday", "this_week", "last_week", "this_month", "last_month", "last_30_days", "last_90_days", "this_year", "custom"],
              description: "Time period for analysis"
            },
            start_date: {
              type: "string",
              description: "Custom start date (YYYY-MM-DD format, required if time_period is 'custom')"
            },
            end_date: {
              type: "string",
              description: "Custom end date (YYYY-MM-DD format, required if time_period is 'custom')"
            },
            group_by: {
              type: "string",
              enum: ["none", "day", "week", "month", "status", "product", "customer"],
              description: "How to group the results (default: none)"
            },
            currency: {
              type: "string",
              description: "Filter by currency (e.g., 'usd', 'eur'). Default: all currencies"
            }
          },
          required: ["integration", "metric_type", "time_period"]
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      integration = get_arg(args, :integration)&.downcase
      metric_type = get_arg(args, :metric_type)
      time_period = get_arg(args, :time_period)
      start_date = get_arg(args, :start_date)
      end_date = get_arg(args, :end_date)
      group_by = get_arg(args, :group_by, "none")
      currency = get_arg(args, :currency)

      # Validate required args
      if error = validate_required_args(args, [:integration, :metric_type, :time_period])
        return error
      end

      # Parse date range
      date_range = parse_date_range(time_period, start_date, end_date)
      return date_range if date_range[:error]

      begin
        case integration
        when "stripe"
          analyze_stripe(metric_type, date_range, group_by, currency)
        when "quickbooks", "qbo"
          analyze_quickbooks(metric_type, date_range, group_by, currency)
        else
          error_response("Analytics not yet supported for '#{integration}'. Supported: stripe, quickbooks")
        end
      rescue => e
        Rails.logger.error "Integration analytics failed: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        error_response("Analytics failed: #{e.message}")
      end
    end

    private

    def parse_date_range(time_period, start_date, end_date)
      # Use Pacific time for user-facing date calculations
      # This ensures "today" means the user's local day, not UTC
      pacific = ActiveSupport::TimeZone['America/Los_Angeles']
      now_pacific = Time.current.in_time_zone(pacific)
      today = now_pacific.to_date
      
      case time_period
      when "today"
        # Use Pacific timezone for start/end of day
        { 
          start_time: pacific.local(today.year, today.month, today.day).beginning_of_day, 
          end_time: pacific.local(today.year, today.month, today.day).end_of_day, 
          label: "Today" 
        }
      when "yesterday"
        yesterday = today - 1.day
        { 
          start_time: pacific.local(yesterday.year, yesterday.month, yesterday.day).beginning_of_day, 
          end_time: pacific.local(yesterday.year, yesterday.month, yesterday.day).end_of_day, 
          label: "Yesterday" 
        }
      when "this_week"
        week_start = today.beginning_of_week
        { 
          start_time: pacific.local(week_start.year, week_start.month, week_start.day).beginning_of_day, 
          end_time: now_pacific.end_of_day, 
          label: "This Week" 
        }
      when "last_week"
        last_week = today - 1.week
        week_start = last_week.beginning_of_week
        week_end = last_week.end_of_week
        { 
          start_time: pacific.local(week_start.year, week_start.month, week_start.day).beginning_of_day, 
          end_time: pacific.local(week_end.year, week_end.month, week_end.day).end_of_day, 
          label: "Last Week" 
        }
      when "this_month"
        month_start = today.beginning_of_month
        { 
          start_time: pacific.local(month_start.year, month_start.month, month_start.day).beginning_of_day, 
          end_time: now_pacific.end_of_day, 
          label: "This Month" 
        }
      when "last_month"
        last_month = today - 1.month
        month_start = last_month.beginning_of_month
        month_end = last_month.end_of_month
        { 
          start_time: pacific.local(month_start.year, month_start.month, month_start.day).beginning_of_day, 
          end_time: pacific.local(month_end.year, month_end.month, month_end.day).end_of_day, 
          label: "Last Month" 
        }
      when "last_30_days"
        start_day = today - 30.days
        { 
          start_time: pacific.local(start_day.year, start_day.month, start_day.day).beginning_of_day, 
          end_time: now_pacific.end_of_day, 
          label: "Last 30 Days" 
        }
      when "last_90_days"
        start_day = today - 90.days
        { 
          start_time: pacific.local(start_day.year, start_day.month, start_day.day).beginning_of_day, 
          end_time: now_pacific.end_of_day, 
          label: "Last 90 Days" 
        }
      when "this_year"
        year_start = today.beginning_of_year
        { 
          start_time: pacific.local(year_start.year, year_start.month, year_start.day).beginning_of_day, 
          end_time: now_pacific.end_of_day, 
          label: "This Year" 
        }
      when "custom"
        return { error: "start_date and end_date required for custom time period" } if start_date.blank? || end_date.blank?
        begin
          parsed_start = Date.parse(start_date)
          parsed_end = Date.parse(end_date)
          { 
            start_time: pacific.local(parsed_start.year, parsed_start.month, parsed_start.day).beginning_of_day, 
            end_time: pacific.local(parsed_end.year, parsed_end.month, parsed_end.day).end_of_day,
            label: "#{start_date} to #{end_date}"
          }
        rescue Date::Error
          { error: "Invalid date format. Use YYYY-MM-DD" }
        end
      else
        { error: "Invalid time_period: #{time_period}" }
      end
    end

    # ==================== STRIPE ANALYTICS ====================
    
    def analyze_stripe(metric_type, date_range, group_by, currency)
      # Find Stripe connection
      connection = find_stripe_connection
      return error_response("No active Stripe connection found") unless connection

      case metric_type
      when "sales", "revenue", "transactions"
        analyze_stripe_charges(connection, date_range, group_by, currency)
      when "customers"
        analyze_stripe_customers(connection, date_range, group_by)
      when "subscriptions"
        analyze_stripe_subscriptions(connection, date_range, group_by)
      when "invoices"
        analyze_stripe_invoices(connection, date_range, group_by, currency)
      when "refunds"
        analyze_stripe_refunds(connection, date_range, group_by, currency)
      else
        error_response("Unsupported metric type '#{metric_type}' for Stripe")
      end
    end

    def find_stripe_connection
      integration = Integration.find_by(slug: "stripe")
      return nil unless integration

      # Try user's own connection first (new user-scoped connections)
      connection = @user.connections.find_by(integration: integration, status: :connected)
      
      # Fall back to entity connections (handles legacy connections without user_id)
      connection ||= @user.entity&.connections&.find_by(integration: integration, status: :connected)
      
      connection
    end

    def analyze_stripe_charges(connection, date_range, group_by, currency)
      stream_progress("Fetching Stripe charges...")
      
      # Fetch charges with pagination
      all_charges = fetch_stripe_data(connection, "charges", date_range)
      
      # Filter by currency if specified
      if currency.present?
        all_charges = all_charges.select { |c| c["currency"]&.downcase == currency.downcase }
      end

      # Filter to successful charges only
      successful_charges = all_charges.select { |c| c["status"] == "succeeded" }
      
      # Calculate aggregations
      total_amount = successful_charges.sum { |c| c["amount"].to_i }
      total_count = successful_charges.count
      average_amount = total_count > 0 ? total_amount / total_count : 0
      
      # Determine currency (use most common if mixed)
      currencies = successful_charges.group_by { |c| c["currency"] }
      primary_currency = currencies.max_by { |_, v| v.length }&.first || "usd"
      
      # Group results if requested
      grouped_data = group_charges(successful_charges, group_by)

      # Get top transactions
      top_transactions = successful_charges
        .sort_by { |c| -c["amount"].to_i }
        .first(5)
        .map { |c| format_charge_summary(c) }

      success_response(
        metric_type: "sales",
        period: date_range[:label],
        period_start: date_range[:start_time].iso8601,
        period_end: date_range[:end_time].iso8601,
        summary: {
          total_revenue: format_amount(total_amount, primary_currency),
          total_revenue_cents: total_amount,
          transaction_count: total_count,
          average_transaction: format_amount(average_amount, primary_currency),
          average_transaction_cents: average_amount,
          currency: primary_currency.upcase,
          successful_rate: all_charges.any? ? ((successful_charges.count.to_f / all_charges.count) * 100).round(1) : 0
        },
        breakdown: grouped_data,
        top_transactions: top_transactions,
        currencies_breakdown: currencies.transform_values do |charges|
          {
            count: charges.count,
            total: charges.sum { |c| c["amount"].to_i }
          }
        end
      )
    end

    def analyze_stripe_customers(connection, date_range, group_by)
      stream_progress("Fetching Stripe customers...")
      
      all_customers = fetch_stripe_data(connection, "customers", date_range)
      
      new_customers = all_customers.count
      
      # Group by creation date if requested
      grouped_data = if group_by == "day"
        all_customers.group_by { |c| Time.at(c["created"]).to_date.to_s }
          .transform_values(&:count)
      else
        {}
      end

      success_response(
        metric_type: "customers",
        period: date_range[:label],
        summary: {
          new_customers: new_customers,
          total_in_period: all_customers.count
        },
        breakdown: grouped_data,
        recent_customers: all_customers.first(5).map { |c|
          {
            id: c["id"],
            email: c["email"],
            name: c["name"],
            created: Time.at(c["created"]).iso8601
          }
        }
      )
    end

    def analyze_stripe_subscriptions(connection, date_range, group_by)
      stream_progress("Fetching Stripe subscriptions...")
      
      all_subs = fetch_stripe_data(connection, "subscriptions", date_range, created_filter: false)
      
      # Group by status
      by_status = all_subs.group_by { |s| s["status"] }
      
      # Calculate MRR from active subscriptions
      active_subs = by_status["active"] || []
      mrr = active_subs.sum do |s|
        interval = s.dig("plan", "interval") || s.dig("items", "data", 0, "plan", "interval")
        amount = s.dig("plan", "amount") || s.dig("items", "data", 0, "plan", "amount") || 0
        
        case interval
        when "month" then amount
        when "year" then amount / 12
        when "week" then amount * 4
        else amount
        end
      end

      success_response(
        metric_type: "subscriptions",
        period: date_range[:label],
        summary: {
          total_subscriptions: all_subs.count,
          active: (by_status["active"] || []).count,
          trialing: (by_status["trialing"] || []).count,
          past_due: (by_status["past_due"] || []).count,
          canceled: (by_status["canceled"] || []).count,
          monthly_recurring_revenue: format_amount(mrr, "usd"),
          mrr_cents: mrr
        },
        status_breakdown: by_status.transform_values(&:count)
      )
    end

    def analyze_stripe_invoices(connection, date_range, group_by, currency)
      stream_progress("Fetching Stripe invoices...")
      
      all_invoices = fetch_stripe_data(connection, "invoices", date_range)
      
      if currency.present?
        all_invoices = all_invoices.select { |i| i["currency"]&.downcase == currency.downcase }
      end

      paid_invoices = all_invoices.select { |i| i["status"] == "paid" }
      total_paid = paid_invoices.sum { |i| i["amount_paid"].to_i }
      
      primary_currency = all_invoices.first&.dig("currency") || "usd"

      success_response(
        metric_type: "invoices",
        period: date_range[:label],
        summary: {
          total_invoices: all_invoices.count,
          paid_invoices: paid_invoices.count,
          total_collected: format_amount(total_paid, primary_currency),
          total_collected_cents: total_paid,
          open_invoices: all_invoices.count { |i| i["status"] == "open" },
          draft_invoices: all_invoices.count { |i| i["status"] == "draft" }
        },
        status_breakdown: all_invoices.group_by { |i| i["status"] }.transform_values(&:count)
      )
    end

    def analyze_stripe_refunds(connection, date_range, group_by, currency)
      stream_progress("Fetching Stripe refunds...")
      
      all_refunds = fetch_stripe_data(connection, "refunds", date_range)
      
      if currency.present?
        all_refunds = all_refunds.select { |r| r["currency"]&.downcase == currency.downcase }
      end

      total_refunded = all_refunds.sum { |r| r["amount"].to_i }
      primary_currency = all_refunds.first&.dig("currency") || "usd"

      success_response(
        metric_type: "refunds",
        period: date_range[:label],
        summary: {
          total_refunds: all_refunds.count,
          total_amount_refunded: format_amount(total_refunded, primary_currency),
          total_refunded_cents: total_refunded,
          average_refund: all_refunds.any? ? format_amount(total_refunded / all_refunds.count, primary_currency) : "$0.00"
        },
        reasons_breakdown: all_refunds.group_by { |r| r["reason"] || "not_specified" }.transform_values(&:count)
      )
    end

    def fetch_stripe_data(connection, resource, date_range, created_filter: true)
      # Get the active credential - prefer most recently updated, with API key
      # integration_credentials is a has_many association
      credential = connection.integration_credentials
        .active
        .order(updated_at: :desc)
        .find { |cred| cred.credentials&.dig("api_key") || cred.credentials&.dig("secret_key") }
      
      return [] unless credential&.credentials

      api_key = credential.credentials["api_key"] || credential.credentials["secret_key"]
      return [] unless api_key

      Stripe.api_key = api_key
      
      all_data = []
      params = { limit: 100 }
      
      if created_filter
        params[:created] = {
          gte: date_range[:start_time].to_i,
          lte: date_range[:end_time].to_i
        }
      end

      stream_progress("Fetching #{resource} from Stripe...")

      begin
        case resource
        when "charges"
          data = Stripe::Charge.list(params)
        when "customers"
          data = Stripe::Customer.list(params)
        when "subscriptions"
          data = Stripe::Subscription.list(params.merge(status: "all"))
        when "invoices"
          data = Stripe::Invoice.list(params)
        when "refunds"
          data = Stripe::Refund.list(params)
        else
          return []
        end

        # Auto-paginate up to 500 records
        # NOTE: take() returns an array, doesn't accept a block - must chain .each
        data.auto_paging_each.take(500).each do |item|
          all_data << item.to_hash
        end
      rescue Stripe::StripeError => e
        Rails.logger.error "Stripe API error: #{e.message}"
        return []
      end

      all_data
    end

    def group_charges(charges, group_by)
      return {} if group_by == "none"

      case group_by
      when "day"
        charges.group_by { |c| Time.at(c["created"]).to_date.to_s }
          .transform_values { |cs| { count: cs.count, total: cs.sum { |c| c["amount"].to_i } } }
      when "week"
        charges.group_by { |c| Time.at(c["created"]).beginning_of_week.to_date.to_s }
          .transform_values { |cs| { count: cs.count, total: cs.sum { |c| c["amount"].to_i } } }
      when "month"
        charges.group_by { |c| Time.at(c["created"]).strftime("%Y-%m") }
          .transform_values { |cs| { count: cs.count, total: cs.sum { |c| c["amount"].to_i } } }
      when "status"
        charges.group_by { |c| c["status"] }
          .transform_values { |cs| { count: cs.count, total: cs.sum { |c| c["amount"].to_i } } }
      else
        {}
      end
    end

    def format_charge_summary(charge)
      {
        id: charge["id"],
        amount: format_amount(charge["amount"].to_i, charge["currency"]),
        amount_cents: charge["amount"].to_i,
        customer: charge["customer"],
        description: charge["description"]&.truncate(50),
        created: Time.at(charge["created"]).iso8601
      }
    end

    def format_amount(cents, currency)
      return "$0.00" if cents.nil? || cents == 0
      
      dollars = cents / 100.0
      symbol = currency_symbol(currency)
      "#{symbol}#{sprintf('%.2f', dollars)}"
    end

    def currency_symbol(currency)
      case currency&.downcase
      when "usd" then "$"
      when "eur" then "€"
      when "gbp" then "£"
      when "jpy" then "¥"
      when "cad" then "C$"
      when "aud" then "A$"
      else "$"
      end
    end

    # ==================== QUICKBOOKS ANALYTICS ====================
    
    def analyze_quickbooks(metric_type, date_range, group_by, currency)
      # Find QuickBooks connection
      connection = find_quickbooks_connection
      return error_response("No active QuickBooks connection found") unless connection

      # QuickBooks analytics implementation would go here
      # For now, return a placeholder
      error_response("QuickBooks analytics coming soon. Use 'stripe' for now.")
    end

    def find_quickbooks_connection
      integration = Integration.find_by(slug: "quickbooks")
      return nil unless integration

      # Try user's own connection first (new user-scoped connections)
      connection = @user.connections.find_by(integration: integration, status: :connected)
      
      # Fall back to entity connections (handles legacy connections without user_id)
      connection ||= @user.entity&.connections&.find_by(integration: integration, status: :connected)
      
      connection
    end
  end
end

