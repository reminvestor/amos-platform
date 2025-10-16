module Tools
  class ExplainQueryTool < BaseTool
    def self.read_only?
      true
    end
    
    def self.metadata
      {
        name: 'explain_query',
        description: 'Explain how a metric query will be executed, showing SQL, lineage, and estimated rows',
        category: 'analytics',
        input_schema: {
          type: 'object',
          properties: {
            metric: {
              type: 'string',
              description: 'Metric name to explain'
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
              description: 'Time aggregation level'
            },
            group_by: {
              type: 'array',
              description: 'Dimensions to group by'
            },
            where: {
              type: 'object',
              description: 'Filters'
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
      
      # Validate required args
      if error = validate_required_args(args, [:metric, :start_date, :end_date])
        return error
      end
      
      begin
        # Explain query
        explanation = Analytics::QueryExecutor.explain(
          metric: metric,
          params: {
            start_date: start_date,
            end_date: end_date,
            time_grain: time_grain,
            group_by: group_by,
            where: where_filters
          },
          entity: @entity
        )
        
        if explanation[:error]
          return error_response(explanation[:error])
        end
        
        success_response(
          metric: metric,
          compiled_query: explanation[:compiled_query],
          lineage: explanation[:lineage],
          estimate_rows: explanation[:estimate_rows],
          message: "Query explanation generated (estimated #{explanation[:estimate_rows]} rows)"
        )
      rescue => e
        Rails.logger.error "Explain query failed: #{e.message}"
        error_response("Failed to explain query: #{e.message}")
      end
    end
  end
end

