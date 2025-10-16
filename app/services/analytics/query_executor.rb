module Analytics
  class QueryExecutor
    attr_reader :entity, :user
    
    def initialize(entity:, user:)
      @entity = entity
      @user = user
    end
    
    # Execute a metric query (safe, tenant-isolated)
    def self.execute(metric:, params:, entity:, user:)
      new(entity: entity, user: user).execute(metric: metric, params: params)
    end
    
    def execute(metric:, params:)
      start_time = Time.current
      
      begin
        # 1. Find metric definition
        metric_def = find_metric(metric)
        return error_response("Metric '#{metric}' not found") unless metric_def
        
        # 2. Validate parameters
        validation = validate_params(metric_def, params)
        return error_response(validation[:error]) unless validation[:valid]
        
        # 3. Check tenant quota
        quota = get_tenant_quota
        unless quota.within_rate_limit?
          return error_response("Rate limit exceeded. Try again in a moment.")
        end
        
        # 4. Validate time window
        start_date = Date.parse(params[:start_date] || params['start_date'])
        end_date = Date.parse(params[:end_date] || params['end_date'])
        
        unless quota.window_allowed?(start_date, end_date)
          return error_response("Time window exceeds cap of #{quota.window_days_cap} days")
        end
        
        # 5. Build safe query
        query_builder = QueryBuilder.new(metric_def, @entity)
        compiled = query_builder.build_query(params)
        
        # 6. Check row budget (dry-run if requested)
        if params[:dry_run]
          return dry_run_response(compiled, metric_def)
        end
        
        estimate = estimate_rows(compiled)
        unless quota.within_budget?(estimate)
          return error_response("Query would scan ~#{estimate} rows, exceeds budget of #{quota.row_budget}")
        end
        
        # 7. Execute query
        result = execute_query(compiled)
        
        duration_ms = ((Time.current - start_time) * 1000).round
        
        # 8. Log execution (audit trail)
        log_execution(
          metric_def: metric_def,
          params: params,
          query_hash: compiled[:hash],
          rows: result[:rows],
          duration_ms: duration_ms,
          success: true
        )
        
        # 9. Return results
        {
          success: true,
          executed: true,
          metric: metric,
          rows: result[:rows],
          stats: {
            scanned_rows: result[:rows].count,
            latency_ms: duration_ms,
            from_cache: result[:from_cache] || false
          }
        }
        
      rescue => e
        Rails.logger.error "Analytics query failed: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        log_execution(
          metric_def: metric_def,
          params: params,
          query_hash: nil,
          rows: [],
          duration_ms: ((Time.current - start_time) * 1000).round,
          success: false,
          error: e.message
        )
        
        error_response("Query failed: #{e.message}")
      end
    end
    
    # Explain query without executing
    def self.explain(metric:, params:, entity:)
      new(entity: entity, user: nil).explain(metric: metric, params: params)
    end
    
    def explain(metric:, params:)
      metric_def = find_metric(metric)
      return { error: "Metric not found" } unless metric_def
      
      query_builder = QueryBuilder.new(metric_def, @entity)
      compiled = query_builder.build_query(params)
      
      {
        compiled_query: {
          sql: compiled[:sql],
          params: compiled[:params]
        },
        lineage: {
          datasets: [metric_def.source],
          metric_definition_version: metric_def.version,
          owner: metric_def.owner
        },
        estimate_rows: estimate_rows(compiled)
      }
    end
    
    private
    
    def find_metric(name)
      MetricDefinition.latest_for(name)
    end
    
    def get_tenant_quota
      TenantQuota.find_or_create_by(entity: @entity)
    end
    
    def validate_params(metric_def, params)
      errors = []
      
      # Validate required params
      errors << "start_date required" unless params[:start_date] || params['start_date']
      errors << "end_date required" unless params[:end_date] || params['end_date']
      
      # Validate dimensions
      if params[:group_by] || params['group_by']
        group_by = params[:group_by] || params['group_by']
        invalid_dims = group_by - metric_def.available_dimensions
        errors << "Invalid dimensions: #{invalid_dims.join(', ')}" if invalid_dims.any?
      end
      
      if errors.any?
        { valid: false, error: errors.join('; ') }
      else
        { valid: true }
      end
    end
    
    def execute_query(compiled)
      # Get analytics connection
      connection = AnalyticsConnection.where(entity: @entity, status: :connected).first
      
      if connection
        # Use warehouse connector
        connector = WarehouseConnector.new(connection)
        connector.execute(compiled[:sql], compiled[:params])
      else
        # Use internal database (AMOS data)
        execute_internal_query(compiled)
      end
    end
    
    def execute_internal_query(compiled)
      # Query AMOS internal data (campaigns, contacts, etc.)
      # This is safe - uses ActiveRecord, tenant-scoped
      result = ActiveRecord::Base.connection.exec_query(
        compiled[:sql],
        'Analytics Query',
        compiled[:params]
      )
      
      {
        rows: result.to_a,
        from_cache: false
      }
    end
    
    def estimate_rows(compiled)
      # Simple estimation - can be enhanced
      # For now, conservative estimate based on time window
      start_date = Date.parse(compiled[:params][:start_date])
      end_date = Date.parse(compiled[:params][:end_date])
      days = (end_date - start_date).to_i
      
      # Rough estimate: ~1000 rows per day (can be refined)
      days * 1000
    end
    
    def dry_run_response(compiled, metric_def)
      {
        success: true,
        executed: false,
        dry_run: true,
        sql: compiled[:sql],
        params: compiled[:params],
        estimate_rows: estimate_rows(compiled),
        metric: metric_def.name
      }
    end
    
    def log_execution(metric_def:, params:, query_hash:, rows:, duration_ms:, success:, error: nil)
      AnalyticsQueryLog.create!(
        entity: @entity,
        user: @user,
        metric_definition: metric_def,
        metric_name: metric_def&.name || params[:metric],
        query_hash: query_hash || Digest::SHA256.hexdigest(params.to_json),
        query_params: params,
        compiled_query: query_hash ? "query_#{query_hash}" : nil,
        rows_returned: rows.is_a?(Array) ? rows.count : 0,
        execution_time_ms: duration_ms,
        success: success,
        error_message: error,
        metadata: {
          executed_at: Time.current,
          user_agent: 'amos_analytics'
        }
      )
    rescue => e
      Rails.logger.error "Failed to log analytics query: #{e.message}"
    end
    
    def error_response(message)
      {
        success: false,
        error: message
      }
    end
  end
end

