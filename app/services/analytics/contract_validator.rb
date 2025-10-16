module Analytics
  class ContractValidator
    def initialize(contract)
      @contract = contract
    end
    
    def validate(data)
      errors = []
      pii_detected = false
      
      # Validate against schema
      schema = @contract.schema_definition
      
      if data.is_a?(Array)
        # Validate each row
        data.each_with_index do |row, idx|
          row_errors = validate_row(row, schema, idx)
          errors.concat(row_errors)
        end
      else
        # Single object
        errors = validate_row(data, schema, 0)
      end
      
      # Check for PII
      if @contract.has_pii?
        pii_detected = detect_pii(data)
      end
      
      {
        ok: errors.empty?,
        errors: errors,
        privacy: {
          fields: @contract.pii_fields,
          pii_detected: pii_detected
        }
      }
    end
    
    private
    
    def validate_row(row, schema, row_index)
      errors = []
      
      schema.each do |field, type_spec|
        value = row[field] || row[field.to_sym]
        
        # Check required fields
        if type_spec.to_s.include?('required') && value.nil?
          errors << {
            path: "row[#{row_index}].#{field}",
            message: "Required field missing"
          }
        end
        
        # Type validation
        if value.present?
          unless valid_type?(value, type_spec)
            errors << {
              path: "row[#{row_index}].#{field}",
              message: "Invalid type: expected #{type_spec}, got #{value.class}"
            }
          end
        end
      end
      
      errors
    end
    
    def valid_type?(value, type_spec)
      type = type_spec.to_s.gsub(/\(.*\)/, '') # Remove enum values
      
      case type
      when 'string'
        value.is_a?(String)
      when 'int', 'integer'
        value.is_a?(Integer)
      when 'float', 'number'
        value.is_a?(Numeric)
      when 'date'
        value.is_a?(Date) || value.is_a?(String) && Date.parse(value) rescue false
      when 'bool', 'boolean'
        [true, false].include?(value)
      when /^enum/
        true # Enum validation would go here
      else
        true # Unknown type, allow
      end
    end
    
    def detect_pii(data)
      pii_fields = @contract.pii_fields
      return false if pii_fields.empty?
      
      rows = data.is_a?(Array) ? data : [data]
      
      rows.any? do |row|
        pii_fields.any? { |field| row[field].present? || row[field.to_sym].present? }
      end
    end
  end
end

