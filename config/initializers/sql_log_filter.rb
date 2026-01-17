# frozen_string_literal: true

# Filter large vector embeddings from SQL logs
# pgvector queries include huge float arrays that provide no debugging value
# and make logs unreadable. This filter replaces them with [VECTOR].

module SqlLogFilter
  # Ultra-aggressive pattern: any sequence of 20+ comma-separated floats
  # Handles: standard floats, scientific notation, negative numbers, with/without spaces
  FLOAT_SEQUENCE_PATTERN = /
    \[                                          # Opening bracket
    (?:
      -?                                        # Optional negative
      \d+                                       # Integer part
      (?:\.\d+)?                                # Optional decimal
      (?:[eE][+-]?\d+)?                         # Optional scientific notation
      \s*,\s*                                   # Comma with optional spaces
    ){15,}                                      # At least 15 floats (vectors are 1024+)
    -?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?            # Final float
    \]                                          # Closing bracket
  /x

  def self.filter(sql)
    return sql unless sql.is_a?(String)
    return sql unless sql.length > 300 # Even lower threshold
    
    # Replace any float array (quoted or unquoted) with [VECTOR]
    sql.gsub(FLOAT_SEQUENCE_PATTERN, '[VECTOR]')
  end
end

# Monkey-patch ActiveRecord's log subscriber to filter vector embeddings
# Only in development - production uses structured logging
if Rails.env.development?
  Rails.application.config.after_initialize do
    # Safer prepend-based approach (Ruby 2.0+)
    unless ActiveRecord::LogSubscriber.ancestors.include?(SqlLogFilter::LogSubscriberPatch)
      module SqlLogFilter
        module LogSubscriberPatch
          def sql(event)
            # Filter vector embeddings from the SQL payload before logging
            if event.payload[:sql].is_a?(String) && event.payload[:sql].length > 300
              event.payload[:sql] = SqlLogFilter.filter(event.payload[:sql])
            end
            super
          end
        end
      end
      
      ActiveRecord::LogSubscriber.prepend(SqlLogFilter::LogSubscriberPatch)
      Rails.logger.debug "[SqlLogFilter] Installed vector filtering for SQL logs"
    end
  end
end
