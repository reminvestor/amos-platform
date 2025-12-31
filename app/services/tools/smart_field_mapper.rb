# frozen_string_literal: true

module Tools
  # Intelligently maps user-provided field values to valid database values
  # When a user says "set status to qualified", we figure out what they really mean
  class SmartFieldMapper
    # Field synonyms - map user intent to correct field names
    FIELD_SYNONYMS = {
      # User might say "status" but mean lifecycle_stage
      'status' => {
        'qualified' => { field: 'lifecycle_stage', value: 'mql' },
        'mql' => { field: 'lifecycle_stage', value: 'mql' },
        'sql' => { field: 'lifecycle_stage', value: 'sql' },
        'lead' => { field: 'lifecycle_stage', value: 'lead' },
        'customer' => { field: 'lifecycle_stage', value: 'customer' },
        'opportunity' => { field: 'lifecycle_stage', value: 'opportunity' },
        'subscriber' => { field: 'lifecycle_stage', value: 'subscriber' },
        'evangelist' => { field: 'lifecycle_stage', value: 'evangelist' },
        # These are actual status values - keep as status
        'active' => { field: 'status', value: 'active' },
        'inactive' => { field: 'status', value: 'inactive' },
        'unsubscribed' => { field: 'status', value: 'unsubscribed' },
        'bounced' => { field: 'status', value: 'bounced' }
      },
      'lifecycle' => 'lifecycle_stage',
      'stage' => 'lifecycle_stage',
      'lifecycle_status' => 'lifecycle_stage'
    }.freeze

    # Value mappings for specific fields
    VALUE_MAPPINGS = {
      'lifecycle_stage' => {
        # Common variations users might say
        'qualified' => 'mql',
        'marketing qualified' => 'mql',
        'marketing qualified lead' => 'mql',
        'sales qualified' => 'sql',
        'sales qualified lead' => 'sql',
        'prospect' => 'lead',
        'new' => 'lead',
        'won' => 'customer',
        'closed' => 'customer',
        'converted' => 'customer',
        'fan' => 'evangelist',
        'advocate' => 'evangelist'
      },
      'status' => {
        # Map invalid status values to lifecycle_stage redirects
        'qualified' => :redirect_to_lifecycle,
        'lead' => :redirect_to_lifecycle,
        'customer' => :redirect_to_lifecycle,
        'mql' => :redirect_to_lifecycle,
        'sql' => :redirect_to_lifecycle
      }
    }.freeze

    # Valid values for each constrained field (for Contact model)
    VALID_VALUES = {
      'status' => %w[active inactive unsubscribed bounced],
      'lifecycle_stage' => %w[subscriber lead mql sql opportunity customer evangelist other]
    }.freeze

    attr_reader :corrections

    def initialize
      @corrections = []
    end

    # Map data hash, correcting any invalid values
    # Returns { corrected_data: {...}, corrections: [...] }
    def map_data(data, model_class = nil)
      @corrections = []
      corrected = data.dup.stringify_keys

      corrected.each do |field, value|
        next if value.nil?
        
        result = map_field_value(field, value, model_class)
        
        if result[:changed]
          # Field was remapped
          corrected.delete(field) if result[:new_field] != field
          corrected[result[:new_field]] = result[:new_value]
          
          @corrections << {
            original_field: field,
            original_value: value,
            corrected_field: result[:new_field],
            corrected_value: result[:new_value],
            reason: result[:reason]
          }
        end
      end

      { corrected_data: corrected, corrections: @corrections }
    end

    # Map a single field/value pair
    def map_field_value(field, value, model_class = nil)
      field = field.to_s
      value_str = value.to_s.downcase.strip

      # Check if this field has synonym mappings with value-specific rules
      if FIELD_SYNONYMS[field].is_a?(Hash) && FIELD_SYNONYMS[field][value_str]
        mapping = FIELD_SYNONYMS[field][value_str]
        return {
          changed: mapping[:field] != field || mapping[:value] != value_str,
          new_field: mapping[:field],
          new_value: mapping[:value],
          reason: "Mapped '#{field}=#{value}' to '#{mapping[:field]}=#{mapping[:value]}' for better accuracy"
        }
      end

      # Check if this field name is a synonym for another field
      if FIELD_SYNONYMS[field].is_a?(String)
        new_field = FIELD_SYNONYMS[field]
        return {
          changed: true,
          new_field: new_field,
          new_value: map_value_for_field(new_field, value_str),
          reason: "Field '#{field}' mapped to '#{new_field}'"
        }
      end

      # Check if the value needs mapping for this field
      if VALUE_MAPPINGS[field]
        mapped = VALUE_MAPPINGS[field][value_str]
        
        if mapped == :redirect_to_lifecycle
          # This value belongs in lifecycle_stage, not status
          lifecycle_value = VALUE_MAPPINGS['lifecycle_stage'][value_str] || value_str
          return {
            changed: true,
            new_field: 'lifecycle_stage',
            new_value: lifecycle_value,
            reason: "'#{value}' is a lifecycle stage, not a status. Updated lifecycle_stage instead."
          }
        elsif mapped
          return {
            changed: true,
            new_field: field,
            new_value: mapped,
            reason: "Mapped '#{value}' to '#{mapped}' (valid value for #{field})"
          }
        end
      end

      # Validate against known valid values
      if VALID_VALUES[field] && !VALID_VALUES[field].include?(value_str)
        # Try fuzzy match
        closest = find_closest_value(value_str, VALID_VALUES[field])
        if closest
          return {
            changed: true,
            new_field: field,
            new_value: closest,
            reason: "Corrected '#{value}' to '#{closest}' (closest valid value)"
          }
        end
      end

      # No change needed
      { changed: false, new_field: field, new_value: value }
    end

    private

    def map_value_for_field(field, value)
      value_str = value.to_s.downcase.strip
      
      if VALUE_MAPPINGS[field] && VALUE_MAPPINGS[field][value_str]
        mapped = VALUE_MAPPINGS[field][value_str]
        return mapped unless mapped == :redirect_to_lifecycle
      end
      
      value_str
    end

    def find_closest_value(input, valid_values)
      return nil if valid_values.empty?
      
      # Exact match
      return input if valid_values.include?(input)
      
      # Substring match
      valid_values.each do |valid|
        return valid if valid.include?(input) || input.include?(valid)
      end
      
      # Levenshtein-like simple match (first 3 chars)
      valid_values.each do |valid|
        return valid if valid[0..2] == input[0..2]
      end
      
      nil
    end
  end
end

