module Agents
  module Specialized
    class VerifierAgent < Agents::Base::BaseAgent
      include Agents::Resilience

      def initialize(initial_context: {})
        super(
          role: "verifier",
          capabilities: [
            "data_validation",
            "result_verification",
            "quality_assurance",
            "compliance_checking",
            "output_validation"
          ],
          context: initial_context,
          task_session: initial_context[:task_session]
        )

        # Load verification-specific tools
        @tool_catalog = ::Tools::ToolCatalog.instance rescue nil
        @ai_service = BedrockService.new(
          user: initial_context[:user],
          entity: initial_context[:entity]
        ) rescue nil

        Rails.logger.info "VerifierAgent #{@id}: Initialized with verification capabilities"
      end

      def execute_step(step, inputs = {})
        Rails.logger.info "VerifierAgent #{@id}: Verifying step #{step[:id]} (#{step[:type]})"

        # Record verification start
        verification_record = {
          step_id: step[:id],
          started_at: Time.current,
          inputs: sanitize_inputs(inputs),
          verification_type: determine_verification_type(step)
        }

        begin
          # Validate step requirements
          validate_step_requirements(step, inputs)

          # Execute verification based on step type
          result = case step[:type]
          when "tool_call"
            verify_tool_execution(step, inputs)
          when "validation"
            execute_validation_rules(step, inputs)
          when "quality_check"
            perform_quality_check(step, inputs)
          else
            execute_tool_step(step, inputs)
          end

          # Verify the result meets quality standards
          if result[:success] && step[:config] && step[:config][:verification_rules]
            Rails.logger.info "VerifierAgent: Applying verification rules"
            verification_result = apply_verification_rules(result, step[:config][:verification_rules])
            unless verification_result[:passed]
              Rails.logger.error "VerifierAgent: Verification failed - #{verification_result[:reasons].join(', ')}"
              result = {
                success: false,
                error: "Verification failed: #{verification_result[:reasons].join(', ')}",
                verification_details: verification_result
              }
            else
              Rails.logger.info "VerifierAgent: Verification passed"
            end
          end

          # Update memory with verification outcome
          @memory.store_short_term(:verification_completed, {
            step_id: step[:id],
            result: result,
            verification_passed: result[:success],
            timestamp: Time.current
          })

          result
        rescue => e
          Rails.logger.error "VerifierAgent #{@id}: Verification failed - #{e.message}"

          {
            success: false,
            error: "Verification error: #{e.message}",
            verification_failed: true
          }
        end
      end

      def verify_data_integrity(data, schema = nil)
        Rails.logger.info "VerifierAgent #{@id}: Verifying data integrity"

        verification_results = {
          passed: true,
          issues: [],
          warnings: []
        }

        # Check for required fields
        if schema && schema[:required_fields]
          missing_fields = schema[:required_fields] - data.keys.map(&:to_s)
          if missing_fields.any?
            verification_results[:passed] = false
            verification_results[:issues] << "Missing required fields: #{missing_fields.join(', ')}"
          end
        end

        # Check data types
        if schema && schema[:fields]
          data.each do |field, value|
            field_schema = schema[:fields][field.to_s] || schema[:fields][field.to_sym]
            if field_schema && !validate_field_type(value, field_schema[:type])
              verification_results[:warnings] << "Field '#{field}' type mismatch: expected #{field_schema[:type]}"
            end
          end
        end

        # Check for suspicious values
        data.each do |field, value|
          if value.to_s.strip.empty? && field.to_s.include?("name")
            verification_results[:warnings] << "Field '#{field}' appears to be empty"
          end
        end

        verification_results
      end

      def verify_workflow_completion(workflow, expected_outcomes = {})
        Rails.logger.info "VerifierAgent #{@id}: Verifying workflow completion"

        verification = {
          passed: true,
          completed_steps: 0,
          failed_steps: 0,
          issues: []
        }

        workflow[:steps]&.each do |step|
          case step[:status] || step["status"]
          when "completed"
            verification[:completed_steps] += 1
          when "failed"
            verification[:failed_steps] += 1
            verification[:issues] << "Step '#{step[:name] || step['name']}' failed"
          when "pending", "in_progress"
            verification[:passed] = false
            verification[:issues] << "Step '#{step[:name] || step['name']}' not completed"
          end
        end

        # Check if expected outcomes were achieved
        if expected_outcomes.any?
          expected_outcomes.each do |outcome, expected_value|
            # This would check against actual system state
            # For now, just log the expectation
            Rails.logger.info "Expected outcome: #{outcome} = #{expected_value}"
          end
        end

        verification
      end

      private

      def with_resilience(operation_name, &block)
        # Simple resilience wrapper - can be enhanced later
        begin
          block.call
        rescue => e
          Rails.logger.error "VerifierAgent #{@id}: Operation #{operation_name} failed: #{e.message}"
          # Could add retry logic here
          raise
        end
      end

      def validate_step_requirements(step, inputs)
        # Basic validation - can be extended based on step type
        validation_result = { valid: true, errors: [] }

        # Check if step has required config
        if step[:type] == "tool_call" && !step[:config][:tool]
          validation_result[:valid] = false
          validation_result[:errors] << "Tool call step missing tool name"
        end

        # Check if required inputs are present
        if step[:config][:required_inputs]
          missing_inputs = step[:config][:required_inputs] - inputs.keys.map(&:to_s)
          if missing_inputs.any?
            validation_result[:valid] = false
            validation_result[:errors] << "Missing required inputs: #{missing_inputs.join(', ')}"
          end
        end

        validation_result
      end

      def determine_verification_type(step)
        if step[:config][:verification_rules]
          "rule_based"
        elsif step[:type] == "validation"
          "validation"
        elsif step[:config][:quality_checks]
          "quality_assurance"
        else
          "standard"
        end
      end

      def verify_tool_execution(step, inputs)
        tool_name = step[:config][:tool]
        tool_args = step[:config][:tool_args] || {}
        merged_inputs = tool_args.merge(inputs)

        Rails.logger.info "VerifierAgent #{@id}: Verifying tool execution: #{tool_name}"

        # Execute the tool with verification context
        if @tool_catalog
          context = {
            user: @task_session&.user,
            entity: @task_session&.user&.entity,
            context: { task_session_id: @task_session&.id, verification: true }
          }

          with_resilience(tool_name) do
            result = @tool_catalog.execute_tool(tool_name, merged_inputs, context)

            # Add verification metadata
            result[:verified_by] = @id
            result[:verification_timestamp] = Time.current

            result
          end
        else
          {
            success: false,
            error: "Tool catalog not available for verification"
          }
        end
      end

      def execute_validation_rules(step, inputs)
        rules = step[:config][:rules] || []
        validation_results = {
          passed: true,
          failed_rules: [],
          warnings: []
        }

        rules.each do |rule|
          result = evaluate_validation_rule(rule, inputs)
          unless result[:passed]
            validation_results[:passed] = false
            validation_results[:failed_rules] << {
              rule: rule,
              reason: result[:reason]
            }
          end
        end

        {
          success: validation_results[:passed],
          validation_results: validation_results,
          error: validation_results[:passed] ? nil : "Validation failed: #{validation_results[:failed_rules].map { |r| r[:reason] }.join(', ')}"
        }
      end

      def perform_quality_check(step, inputs)
        quality_checks = step[:config][:quality_checks] || []

        quality_results = {
          score: 100,
          passed: true,
          issues: [],
          recommendations: []
        }

        quality_checks.each do |check|
          result = evaluate_quality_check(check, inputs)
          quality_results[:score] -= result[:penalty] if result[:penalty]

          if result[:critical] && !result[:passed]
            quality_results[:passed] = false
            quality_results[:issues] << result[:message]
          elsif !result[:passed]
            quality_results[:recommendations] << result[:message]
          end
        end

        {
          success: quality_results[:passed],
          quality_score: quality_results[:score],
          quality_results: quality_results,
          error: quality_results[:passed] ? nil : "Quality check failed: #{quality_results[:issues].join(', ')}"
        }
      end

      def apply_verification_rules(result, rules)
        verification = {
          passed: true,
          reasons: []
        }

        Rails.logger.info "VerifierAgent: Checking #{rules.length} verification rules"
        Rails.logger.info "VerifierAgent: Result structure keys: #{result.keys}"

        rules.each do |rule|
          rule_type = rule[:type] || rule[:rule] || rule["rule"]
          field_name = rule[:field] || rule["field"]

          Rails.logger.info "VerifierAgent: Checking rule #{rule_type} for field #{field_name}"

          # Navigate to the field in the result
          # Check multiple possible locations for records
          records = result[:records] ||
                   result.dig(:data, :records) ||
                   result.dig(:data, :result, :records) ||
                   result.dig(:result, :records)

          field_value = if records&.first
            # Handle array results (like from get_data)
            Rails.logger.info "VerifierAgent: Found records array with #{records.length} records"
            record = records.first
            Rails.logger.info "VerifierAgent: First record keys: #{record.keys if record.is_a?(Hash)}"
            record[field_name.to_sym] || record[field_name]
          elsif result.dig(:data, :result, :record)
            # Handle single record creation results
            Rails.logger.info "VerifierAgent: Found single record result"
            record = result.dig(:data, :result, :record)
            record[field_name.to_sym] || record[field_name]
          else
            # Handle direct field access
            Rails.logger.info "VerifierAgent: No records array, checking direct fields"
            result.dig(:data, :result, field_name.to_sym) ||
            result.dig(:data, :result, field_name) ||
            result.dig(:data, field_name.to_sym) ||
            result.dig(:data, field_name) ||
            result[field_name.to_sym] ||
            result[field_name]
          end

          Rails.logger.info "VerifierAgent: Field value for #{field_name}: #{field_value.inspect}"

          case rule_type
          when "not_null", "not_empty"
            if field_value.nil? || field_value.to_s.strip.empty?
              verification[:passed] = false
              verification[:reasons] << (rule[:message] || "Field '#{field_name}' is empty")
            end
          when "min_count"
            if field_value.is_a?(Array) && field_value.length < rule[:value]
              verification[:passed] = false
              verification[:reasons] << "Field '#{field_name}' has fewer than #{rule[:value]} items"
            end
          when "contains"
            unless field_value.to_s.include?(rule[:value])
              verification[:passed] = false
              verification[:reasons] << "Field '#{field_name}' does not contain '#{rule[:value]}'"
            end
          end
        end

        verification
      end

      def validate_field_type(value, expected_type)
        case expected_type.to_s
        when "string"
          value.is_a?(String)
        when "integer"
          value.is_a?(Integer) || (value.is_a?(String) && value.match?(/^\d+$/))
        when "boolean"
          [ true, false ].include?(value) || [ "true", "false" ].include?(value.to_s)
        when "datetime"
          value.is_a?(Time) || value.is_a?(DateTime) || (value.is_a?(String) && Time.parse(value) rescue false)
        else
          true # Unknown type, assume valid
        end
      end

      def evaluate_validation_rule(rule, inputs)
        # Implement specific validation rule logic
        {
          passed: true,
          reason: nil
        }
      end

      def evaluate_quality_check(check, inputs)
        # Implement specific quality check logic
        {
          passed: true,
          penalty: 0,
          critical: false,
          message: nil
        }
      end

      def sanitize_inputs(inputs)
        # Remove sensitive data from inputs for logging
        inputs.except(:password, :api_key, :secret)
      end
    end
  end
end
