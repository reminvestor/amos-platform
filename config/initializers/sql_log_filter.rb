# frozen_string_literal: true

# Filter large vector embeddings from SQL logs
# pgvector queries include huge float arrays that provide no debugging value
# and make logs unreadable. This filter replaces them with [VECTOR].

module SqlLogFilter
  # Pattern to match vector embedding arrays in SQL (50+ floats)
  VECTOR_PATTERN = /\[(?:-?\d+\.?\d*(?:e[+-]?\d+)?,\s*){50,}(?:-?\d+\.?\d*(?:e[+-]?\d+)?)\]/i

  def self.filter(sql)
    return sql unless sql.is_a?(String)
    return sql unless sql.length > 1000 # Only filter long queries
    
    # Replace large vector arrays with [VECTOR]
    sql.gsub(VECTOR_PATTERN, '[VECTOR]')
  end
end

# Monkey-patch ActiveRecord's log subscriber to filter vector embeddings
# Only in development - production uses JSON logging
if Rails.env.development?
  module ActiveRecord
    class LogSubscriber < ActiveSupport::LogSubscriber
      alias_method :original_sql, :sql
      
      def sql(event)
        # Filter vector embeddings from the SQL payload before logging
        if event.payload[:sql]&.length.to_i > 1000
          event.payload[:sql] = SqlLogFilter.filter(event.payload[:sql])
        end
        original_sql(event)
      end
    end
  end
end
