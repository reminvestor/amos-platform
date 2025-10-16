module Analytics
  class QueryBuilder
    def initialize(metric_def, entity)
      @metric_def = metric_def
      @entity = entity
    end
    
    def build_query(params)
      # Build safe SQL from metric definition and parameters
      # NO string interpolation - use parameterized queries!
      
      start_date = params[:start_date] || params['start_date']
      end_date = params[:end_date] || params['end_date']
      time_grain = params[:time_grain] || params['time_grain'] || @metric_def.default_grain
      group_by = params[:group_by] || params['group_by'] || []
      where_clause = params[:where] || params['where'] || {}
      limit = params[:limit] || params['limit'] || 10000
      
      # Start building query
      sql_parts = []
      sql_params = []
      
      # SELECT clause
      select_cols = build_select_clause(time_grain, group_by)
      sql_parts << "SELECT #{select_cols.join(', ')}"
      
      # FROM clause
      sql_parts << "FROM #{@metric_def.source}"
      
      # WHERE clause (ALWAYS includes tenant filter!)
      where_conditions = ["entity_id = ?"]
      sql_params << @entity.id
      
      # Add time window
      where_conditions << "#{@metric_def.time_column} >= ?"
      where_conditions << "#{@metric_def.time_column} <= ?"
      sql_params << start_date
      sql_params << end_date
      
      # Add user filters (equality only - safe!)
      where_clause.each do |field, value|
        if value.is_a?(Array)
          placeholders = value.map { '?' }.join(', ')
          where_conditions << "#{field} IN (#{placeholders})"
          sql_params.concat(value)
        else
          where_conditions << "#{field} = ?"
          sql_params << value
        end
      end
      
      sql_parts << "WHERE #{where_conditions.join(' AND ')}"
      
      # GROUP BY clause
      if group_by.any?
        group_cols = build_group_by_clause(time_grain, group_by)
        sql_parts << "GROUP BY #{group_cols.join(', ')}"
      end
      
      # ORDER BY clause
      sql_parts << "ORDER BY period DESC"
      
      # LIMIT clause
      sql_parts << "LIMIT ?"
      sql_params << limit
      
      sql = sql_parts.join("\n")
      
      {
        sql: sql,
        params: sql_params,
        hash: Digest::SHA256.hexdigest("#{sql}#{sql_params.to_json}")
      }
    end
    
    private
    
    def build_select_clause(time_grain, dimensions)
      cols = []
      
      # Time period column
      case time_grain
      when 'day'
        cols << "DATE(#{@metric_def.time_column}) as period"
      when 'week'
        cols << "DATE_TRUNC('week', #{@metric_def.time_column}) as period"
      when 'month'
        cols << "DATE_TRUNC('month', #{@metric_def.time_column}) as period"
      end
      
      # Dimension columns
      dimensions.each do |dim|
        cols << dim
      end
      
      # Metric expression
      cols << "#{@metric_def.expression} as value"
      
      cols
    end
    
    def build_group_by_clause(time_grain, dimensions)
      cols = []
      
      # Time period
      cols << "1" # Reference to first SELECT column (period)
      
      # Dimensions (by position)
      dimensions.each_with_index do |dim, idx|
        cols << (idx + 2).to_s  # +2 because period is 1
      end
      
      cols
    end
  end
end

