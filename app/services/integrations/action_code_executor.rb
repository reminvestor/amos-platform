# frozen_string_literal: true

module Integrations
  # ActionCodeExecutor - Safely executes AI-generated Ruby mapping code
  #
  # Mirrors TransformCodeExecutor but for API parameter mapping instead of ETL.
  #
  # The AI generates mapping_code during SETUP. Once saved, it runs without AI.
  # This code converts normalized inputs (what Amos provides) into API-specific
  # parameters (what the external API expects).
  #
  # Example mapping_code:
  #   def map(inputs)
  #     {
  #       product_id: normalize_trading_pair(inputs[:symbol], :hyphen),
  #       side: inputs[:side].upcase,
  #       size: inputs[:quantity].to_s,
  #       price: inputs[:price].to_s,
  #       type: 'limit',
  #       time_in_force: 'GTC'
  #     }
  #   end
  #
  class ActionCodeExecutor
    attr_reader :action, :mapping_code, :response_mapping_code

    def initialize(action)
      @action = action
      @mapping_code = action.mapping_code
      @response_mapping_code = action.response_mapping_code
    end

    # Map normalized inputs to API parameters using the generated code
    def map_inputs(inputs)
      return fallback_mapping(inputs) if mapping_code.blank?

      sandbox = ActionSandbox.new(
        code: mapping_code,
        method_name: 'map',
        data: inputs,
        action: action
      )
      result = sandbox.execute

      { success: true, params: result }
    rescue => e
      Rails.logger.error "[ActionCodeExecutor] Mapping error: #{e.message}"
      { success: false, error: e.message, params: nil }
    end

    # Normalize API response using the generated code
    def normalize_response(response)
      return { success: true, data: response } if response_mapping_code.blank?

      sandbox = ActionSandbox.new(
        code: response_mapping_code,
        method_name: 'normalize',
        data: response,
        action: action
      )
      result = sandbox.execute

      { success: true, data: result }
    rescue => e
      Rails.logger.error "[ActionCodeExecutor] Response normalization error: #{e.message}"
      { success: false, error: e.message, data: response }
    end

    # Test the mapping code with sample data
    def test_mapping(sample_inputs = nil)
      inputs = sample_inputs || action.sample_input || {}

      start_time = Time.current
      result = map_inputs(inputs)
      duration = Time.current - start_time

      {
        success: result[:success],
        inputs: inputs,
        output: result[:params],
        error: result[:error],
        duration_ms: (duration * 1000).round(2)
      }
    end

    private

    # Simple fallback if no mapping code (direct pass-through)
    def fallback_mapping(inputs)
      { success: true, params: inputs.to_h.with_indifferent_access }
    end
  end

  # Sandboxed execution environment for action mapping code
  class ActionSandbox
    TIMEOUT_SECONDS = 5
    MAX_OUTPUT_SIZE = 1_000_000  # 1MB

    def initialize(code:, method_name:, data:, action:)
      @code = code
      @method_name = method_name
      @data = deep_dup(data)
      @action = action
      @integration = action.integration
    end

    def execute
      context = ActionContext.new(@data, @integration, @action)

      # Define the method directly in the context's scope
      # This allows the method body to access context helpers like present?, default, etc.
      wrapped_code = <<~RUBY
        #{@code}
        
        #{@method_name}(inputs)
      RUBY

      # Execute with timeout
      result = nil
      Timeout.timeout(TIMEOUT_SECONDS) do
        result = context.instance_eval(wrapped_code)
      end

      validate_output!(result)
      result
    end

    private

    def validate_output!(result)
      raise "Mapping must return a Hash" unless result.is_a?(Hash)
      raise "Output too large" if result.to_json.bytesize > MAX_OUTPUT_SIZE
    end

    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        obj.dup rescue obj
      end
    end
  end

  # Safe context for action code execution
  # Extends TransformContext with integration-specific helpers
  class ActionContext
    attr_reader :inputs, :integration, :action

    def initialize(data, integration, action)
      @inputs = data.with_indifferent_access
      @integration = integration
      @action = action
    end

    # ============================================
    # ALL TRANSFORM CONTEXT HELPERS (inherited pattern)
    # ============================================

    # Get a value from inputs, supporting dot notation
    def get(path)
      parts = path.to_s.split('.')
      value = inputs
      parts.each { |p| value = value.is_a?(Hash) ? value[p] : nil }
      value
    end

    # Format a string with input values
    def format(template)
      template.gsub(/\{\{(\w+)\}\}/) { |_| inputs[$1] || '' }
    end

    # String helpers
    def titleize(str); str.to_s.titleize; end
    def downcase(str); str.to_s.downcase; end
    def upcase(str); str.to_s.upcase; end
    def strip(str); str.to_s.strip; end
    def slugify(str); str.to_s.parameterize; end
    def truncate(str, len); str.to_s.truncate(len); end
    def camelize(str); str.to_s.camelize(:lower); end
    def underscore(str); str.to_s.underscore; end

    # Number helpers
    def to_cents(dollars); (dollars.to_f * 100).to_i; end
    def to_dollars(cents); (cents.to_f / 100).round(2); end
    def round(num, decimals = 2); num.to_f.round(decimals); end
    def to_string(num, precision = nil)
      precision ? sprintf("%.#{precision}f", num.to_f) : num.to_s
    end

    # Date helpers
    def parse_date(str); Date.parse(str.to_s) rescue nil; end
    def parse_datetime(str); DateTime.parse(str.to_s) rescue nil; end
    def from_unix(timestamp); Time.at(timestamp.to_i) rescue nil; end
    def to_unix(time); time.to_i; end
    def today; Date.current; end
    def now; Time.current; end
    def to_iso8601(time); time.iso8601; end

    # Array helpers
    def first(arr); arr.is_a?(Array) ? arr.first : arr; end
    def last(arr); arr.is_a?(Array) ? arr.last : arr; end
    def join(arr, sep = ', '); arr.is_a?(Array) ? arr.join(sep) : arr; end
    def split(str, sep = ','); str.to_s.split(sep).map(&:strip); end

    # Conditional helpers
    def present?(val); val.present?; end
    def blank?(val); val.blank?; end
    def default(val, fallback); val.present? ? val : fallback; end

    # Map a value to another using a hash
    def map_value(val, mapping, default_val = nil)
      mapping[val.to_s] || mapping[val] || default_val || val
    end

    # Build a hash from multiple fields
    def build_hash(*pairs)
      Hash[*pairs]
    end

    # Merge hashes
    def merge(*hashes)
      hashes.reduce({}) { |acc, h| acc.merge(h || {}) }
    end

    # ============================================
    # INTEGRATION-SPECIFIC HELPERS (new)
    # ============================================

    # Trading pair normalization
    # "BTC/USD" → "BTC-USD" (hyphen) or "BTCUSD" (concat) or "BTC_USD" (underscore)
    def normalize_trading_pair(pair, format = :hyphen)
      return pair if pair.blank?
      
      parts = pair.to_s.split(%r{[/\-_]})
      return pair if parts.length != 2

      case format
      when :hyphen then parts.join('-')
      when :underscore then parts.join('_')
      when :concat then parts.join('')
      else parts.join('-')
      end
    end

    # Enum value mapping based on integration
    def to_api_enum(value, mapping)
      mapping[value.to_s.downcase] || mapping[value.to_sym] || value
    end

    # Decimal formatting for trading APIs
    def to_api_decimal(value, precision: 8)
      sprintf("%.#{precision}f", value.to_f)
    end

    # Boolean to API format (some APIs use strings)
    def to_api_bool(value, format: :string)
      bool = value.is_a?(String) ? value.downcase == 'true' : !!value
      case format
      when :string then bool ? 'true' : 'false'
      when :integer then bool ? 1 : 0
      when :yes_no then bool ? 'yes' : 'no'
      else bool
      end
    end

    # Phone number formatting
    def format_phone(phone, format: :e164)
      return phone if phone.blank?
      
      digits = phone.to_s.gsub(/\D/, '')
      
      case format
      when :e164
        digits.start_with?('1') ? "+#{digits}" : "+1#{digits}"
      when :national
        digits.length == 10 ? "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}" : phone
      else phone
      end
    end

    # Email normalization
    def normalize_email(email)
      email.to_s.strip.downcase
    end

    # URL building
    def build_url(base, path, params = {})
      uri = URI.join(base.chomp('/') + '/', path.sub(/^\//, ''))
      uri.query = params.to_query if params.present?
      uri.to_s
    end

    # Pagination helpers
    def cursor_params(cursor, limit: 100)
      params = { limit: limit }
      params[:starting_after] = cursor if cursor.present?
      params
    end

    def page_params(page, per_page: 100)
      { page: page, per_page: per_page }
    end

    # Date range for API queries
    def date_range_params(start_date, end_date, format: :unix)
      case format
      when :unix
        { 
          created_gte: start_date.to_time.to_i,
          created_lte: end_date.to_time.to_i
        }
      when :iso8601
        {
          start_date: start_date.iso8601,
          end_date: end_date.iso8601
        }
      else
        { start_date: start_date, end_date: end_date }
      end
    end

    # ============================================
    # INTEGRATION METADATA HELPERS
    # ============================================

    def integration_slug
      integration&.slug
    end

    def integration_category
      integration&.category
    end

    # Get configuration from integration metadata
    def integration_config(key)
      integration&.metadata&.dig(key.to_s)
    end
  end
end

