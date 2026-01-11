# frozen_string_literal: true

module Integrations
  # TransformCodeExecutor - Safely executes AI-generated Ruby transform code
  #
  # The AI generates this code during SETUP. Once saved, it runs without AI.
  #
  # Generated code must define a `transform(record)` method that takes
  # a Hash (external record) and returns a Hash (internal record).
  #
  class TransformCodeExecutor
    attr_reader :sync_config, :transform_code

    def initialize(sync_config)
      @sync_config = sync_config
      @transform_code = sync_config.transform_code
    end

    # Transform a single record using the generated code
    def transform(external_record)
      return fallback_transform(external_record) if transform_code.blank?

      sandbox = create_sandbox(external_record)
      result = sandbox.execute

      { success: true, data: result }
    rescue => e
      Rails.logger.error "[TransformCodeExecutor] Error: #{e.message}"
      { success: false, error: e.message, data: nil }
    end

    # Transform a batch of records
    def transform_batch(records)
      results = { successful: [], failed: [], total: records.length }

      records.each_with_index do |record, idx|
        transformed = transform(record)

        if transformed[:success]
          results[:successful] << { index: idx, data: transformed[:data] }
        else
          results[:failed] << { index: idx, error: transformed[:error] }
        end
      end

      results
    end

    # Test the transform code with sample data
    def test_transform(sample_input = nil)
      input = sample_input || sync_config.sample_input || {}
      
      start_time = Time.current
      result = transform(input)
      duration = Time.current - start_time

      {
        success: result[:success],
        input: input,
        output: result[:data],
        error: result[:error],
        duration_ms: (duration * 1000).round(2)
      }
    end

    private

    # Create a sandboxed execution environment
    def create_sandbox(record)
      TransformSandbox.new(transform_code, record, sync_config)
    end

    # Fallback to simple field mapping if no custom code
    def fallback_transform(record)
      return { success: true, data: record } if sync_config.field_mappings.blank?

      result = {}
      sync_config.field_mappings.each do |source, target|
        value = record[source] || record[source.to_sym]
        result[target.to_sym] = value
      end

      { success: true, data: result }
    end
  end

  # Sandboxed execution environment for transform code
  class TransformSandbox
    TIMEOUT_SECONDS = 5
    MAX_OUTPUT_SIZE = 1_000_000  # 1MB

    def initialize(code, record, sync_config)
      @code = code
      @record = deep_dup(record)
      @sync_config = sync_config
      @entity = sync_config.entity
    end

    def execute
      # Build the execution context
      context = build_context

      # Wrap the code in a module to prevent pollution
      wrapped_code = <<~RUBY
        module TransformModule
          extend self

          #{@code}
        end

        TransformModule.transform(record)
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

    def build_context
      # Create a context object with safe helpers
      TransformContext.new(@record, @entity)
    end

    def validate_output!(result)
      raise "Transform must return a Hash" unless result.is_a?(Hash)
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

  # Safe context for transform execution
  class TransformContext
    attr_reader :record, :entity

    def initialize(record, entity)
      @record = record.with_indifferent_access
      @entity = entity
    end

    # ============================================
    # SAFE HELPERS AVAILABLE TO TRANSFORM CODE
    # ============================================

    # Get a value from the record, supporting dot notation
    def get(path)
      parts = path.to_s.split('.')
      value = record
      parts.each { |p| value = value.is_a?(Hash) ? value[p] : nil }
      value
    end

    # Format a string with record values
    def format(template)
      template.gsub(/\{\{(\w+)\}\}/) { |_| record[$1] || '' }
    end

    # String helpers
    def titleize(str); str.to_s.titleize; end
    def downcase(str); str.to_s.downcase; end
    def upcase(str); str.to_s.upcase; end
    def strip(str); str.to_s.strip; end
    def slugify(str); str.to_s.parameterize; end
    def truncate(str, len); str.to_s.truncate(len); end

    # Number helpers
    def to_cents(dollars); (dollars.to_f * 100).to_i; end
    def to_dollars(cents); (cents.to_f / 100).round(2); end
    def round(num, decimals = 2); num.to_f.round(decimals); end

    # Date helpers
    def parse_date(str); Date.parse(str.to_s) rescue nil; end
    def parse_datetime(str); DateTime.parse(str.to_s) rescue nil; end
    def from_unix(timestamp); Time.at(timestamp.to_i) rescue nil; end
    def to_unix(time); time.to_i; end
    def today; Date.current; end
    def now; Time.current; end

    # Array helpers
    def first(arr); arr.is_a?(Array) ? arr.first : arr; end
    def last(arr); arr.is_a?(Array) ? arr.last : arr; end
    def join(arr, sep = ', '); arr.is_a?(Array) ? arr.join(sep) : arr; end
    def split(str, sep = ','); str.to_s.split(sep).map(&:strip); end

    # Conditional helpers
    def present?(val); val.present?; end
    def blank?(val); val.blank?; end
    def default(val, fallback); val.present? ? val : fallback; end

    # Lookup helpers (read-only database access)
    def lookup_contact_by_email(email)
      return nil if email.blank? || entity.nil?
      contact = entity.contacts.find_by(email: email.to_s.downcase)
      contact&.id
    end

    def lookup_user_by_email(email)
      return nil if email.blank? || entity.nil?
      user = entity.users.find_by(email: email.to_s.downcase)
      user&.id
    end

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
  end
end

