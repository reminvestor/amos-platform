# frozen_string_literal: true

# Filter large vector embeddings from SQL logs
# pgvector queries include huge float arrays that provide no debugging value
# and make logs unreadable. This filter replaces them with [VECTOR].

module SqlLogFilter
  # Multiple patterns to catch all vector embedding formats:
  # 1. Standard SQL array syntax: '[0.123, -0.456, ...]'
  # 2. Scientific notation: [1.52587890625e-05, ...]
  # 3. PostgreSQL array cast: '[-0.123,0.456,...]'::vector
  
  # Match arrays with 20+ comma-separated float-like numbers
  VECTOR_PATTERNS = [
    # Standard format with spaces
    /'\[(?:-?\d+\.?\d*(?:e[+-]?\d+)?,\s*){20,}[^\]]*\]'/i,
    # Compact format without spaces
    /'\[(?:-?\d+\.?\d*(?:e[+-]?\d+)?,){20,}[^\]]*\]'/i,
    # Unquoted arrays
    /\[(?:-?\d+\.?\d*(?:e[+-]?\d+)?,\s*){20,}[^\]]*\]/i,
    # PostgreSQL <=> operator with vector (matches the whole param)
    /<=>.*?'\[.*?\]'/i,
  ].freeze

  def self.filter(sql)
    return sql unless sql.is_a?(String)
    return sql unless sql.length > 500 # Lower threshold to catch more
    
    result = sql.dup
    
    # Apply each pattern
    VECTOR_PATTERNS.each do |pattern|
      result.gsub!(pattern) do |match|
        if match.include?('<=>')
          "<=> '[VECTOR]'"
        else
          "'[VECTOR]'"
        end
      end
    end
    
    result
  end
end

# Monkey-patch ActiveRecord's log subscriber to filter vector embeddings
# Only in development - production uses JSON logging
if Rails.env.development?
  module ActiveRecord
    class LogSubscriber < ActiveSupport::LogSubscriber
      alias_method :original_sql, :sql unless method_defined?(:original_sql)
      
      def sql(event)
        # Filter vector embeddings from the SQL payload before logging
        if event.payload[:sql]&.length.to_i > 500
          event.payload[:sql] = SqlLogFilter.filter(event.payload[:sql])
        end
        original_sql(event)
      end
    end
  end
end
