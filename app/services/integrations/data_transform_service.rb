# frozen_string_literal: true

module Integrations
  # DataTransformService - The ETL transformation layer for iPaaS
  #
  # NO AI INVOLVED during execution - Pure Ruby transformation logic.
  # AI generates the transform_code during SETUP, then it runs without AI.
  #
  # Priority:
  # 1. Custom transform_code (AI-generated Ruby) - most powerful
  # 2. Field mappings + transformations (config-based) - fallback
  #
  class DataTransformService
    attr_reader :sync_config, :field_mappings, :transformations, :default_values

    def initialize(sync_config)
      @sync_config = sync_config
      @field_mappings = sync_config.field_mappings || {}
      @transformations = sync_config.transformations || {}
      @default_values = sync_config.default_values || {}
    end

    # Transform a single record
    def transform(external_record)
      # Use AI-generated code if available
      if sync_config.transform_code.present?
        return TransformCodeExecutor.new(sync_config).transform(external_record)
      end

      # Otherwise fall back to config-based transform
      transform_with_config(external_record)
    end

    # Config-based transform (no custom code)
    def transform_with_config(external_record)
      result = {}
      errors = []

      # Step 1: Apply field mappings
      field_mappings.each do |source_field, target_field|
        value = extract_value(external_record, source_field)
        
        # Step 2: Apply transformation if defined
        if transformations[source_field].present?
          value = apply_transformation(value, transformations[source_field], external_record)
        end

        result[target_field.to_sym] = value unless value.nil?
      end

      # Step 3: Apply default values
      default_values.each do |field, default|
        result[field.to_sym] ||= evaluate_default(default, external_record)
      end

      { success: true, data: result, errors: errors }
    rescue => e
      { success: false, data: nil, errors: [e.message] }
    end

    # Transform a batch
    def transform_batch(records)
      results = { successful: [], failed: [], total: records.length }

      records.each_with_index do |record, idx|
        transformed = transform(record)
        
        if transformed[:success]
          results[:successful] << { index: idx, data: transformed[:data] }
        else
          results[:failed] << { index: idx, errors: transformed[:errors] }
        end
      end

      results
    end

    private

    def extract_value(record, field_path)
      parts = field_path.to_s.split('.')
      value = record
      parts.each { |p| value = value.is_a?(Hash) ? (value[p] || value[p.to_sym]) : nil }
      value
    end

    def apply_transformation(value, transform_spec, full_record)
      case transform_spec
      when String then apply_simple_transform(value, transform_spec)
      when Hash then apply_complex_transform(value, transform_spec, full_record)
      else value
      end
    end

    def apply_simple_transform(value, type)
      case type
      when 'lowercase' then value.to_s.downcase
      when 'uppercase' then value.to_s.upcase
      when 'titlecase' then value.to_s.titleize
      when 'strip' then value.to_s.strip
      when 'to_integer' then value.to_i
      when 'to_float' then value.to_f
      when 'cents_to_dollars' then (value.to_f / 100).round(2)
      when 'dollars_to_cents' then (value.to_f * 100).to_i
      when 'to_boolean' then ActiveModel::Type::Boolean.new.cast(value)
      when 'to_date' then Date.parse(value.to_s) rescue nil
      when 'to_datetime' then DateTime.parse(value.to_s) rescue nil
      when 'unix_to_datetime' then Time.at(value.to_i) rescue nil
      when 'join' then value.is_a?(Array) ? value.join(', ') : value
      when 'first' then value.is_a?(Array) ? value.first : value
      else value
      end
    end

    def apply_complex_transform(value, spec, full_record)
      type = spec['type'] || spec[:type]

      case type
      when 'concat'
        fields = spec['fields'] || []
        separator = spec['separator'] || ' '
        fields.map { |f| extract_value(full_record, f) }.compact.join(separator)
      when 'map'
        mappings = spec['mappings'] || {}
        mappings[value.to_s] || mappings[value] || spec['default'] || value
      when 'lookup'
        perform_lookup(value, spec)
      when 'conditional'
        evaluate_condition(spec['if'], full_record) ? spec['then'] : spec['else']
      else
        value
      end
    end

    def evaluate_default(default, record)
      return Time.current if default.is_a?(Hash) && default['type'] == 'current_time'
      return Date.current if default.is_a?(Hash) && default['type'] == 'current_date'
      default
    end

    def perform_lookup(value, spec)
      return nil if value.blank?
      klass = spec['model'].constantize
      record = klass.find_by(spec['field'] => value)
      record&.send(spec['return'] || 'id')
    rescue => e
      nil
    end

    def evaluate_condition(condition, record)
      return false if condition.blank?
      if condition.include?('==')
        field, val = condition.split('==').map(&:strip)
        extract_value(record, field).to_s == val.gsub(/["']/, '')
      else
        false
      end
    end
  end
end
