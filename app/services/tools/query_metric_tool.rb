module Tools
  class QueryMetricTool < BaseTool
    def self.metadata
      {
        name: 'query_metric',
        description: 'Query business metrics with automatic tenant isolation, budget enforcement, and safe execution',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            metric: {
              type: 'string',
              description: 'Metric name (e.g., "revenue", "orders", "conversion_rate")'
            },
            start_date: {
              type: 'string',
              description: 'Start date in YYYY-MM-DD format'
            },
            end_date: {
              type: 'string',
              description: 'End date in YYYY-MM-DD format'
            },
            time_grain: {
              type: 'string',
              enum: ['day', 'week', 'month'],
              description: 'Time aggregation level (default: week)'
            },
            group_by: {
              type: 'array',
              description: 'Dimensions to group by (e.g., ["region", "channel"])',
              items: { type: 'string' }
            },
            where: {
              type: 'object',
              description: 'Filters as key-value pairs (equality only)'
            },
            limit: {
              type: 'integer',
              description: 'Maximum rows to return (default: 10000, max: 100000)'
            },
            dry_run: {
              type: 'boolean',
              description: 'If true, returns compiled query without executing'
            }
          },
          required: ['metric', 'start_date', 'end_date']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      metric = get_arg(args, :metric)
      start_date = get_arg(args, :start_date)
      end_date = get_arg(args, :end_date)
      time_grain = get_arg(args, :time_grain, 'week')
      group_by = get_arg(args, :group_by, [])
      where_filters = get_arg(args, :where, {})
      limit = get_arg(args, :limit, 10000)
      dry_run = get_arg(args, :dry_run, false)
      
      # Validate required args
      if error = validate_required_args(args, [:metric, :start_date, :end_date])
        return error
      end
      
      begin
        # Execute via Analytics::QueryExecutor
        result = Analytics::QueryExecutor.execute(
          metric: metric,
          params: {
            start_date: start_date,
            end_date: end_date,
            time_grain: time_grain,
            group_by: group_by,
            where: where_filters,
            limit: limit,
            dry_run: dry_run
          },
          entity: @entity,
          user: @user
        )
        
        if result[:success]
          if dry_run
            # Dry run response
            success_response(
              executed: false,
              dry_run: true,
              metric: metric,
              sql: result[:sql],
              params: result[:params],
              estimate_rows: result[:estimate_rows],
              message: "Query compiled successfully (not executed)"
            )
          else
            # Actual execution
            success_response(
              executed: true,
              metric: metric,
              data: result[:rows],
              row_count: result[:rows].count,
              stats: result[:stats],
              message: "Successfully queried #{metric}: #{result[:rows].count} rows returned"
            )
          end
        else
          error_response(result[:error])
        end
      rescue => e
        Rails.logger.error "Query metric tool failed: #{e.message}"
        error_response("Query failed: #{e.message}")
      end
    end
  end
end

