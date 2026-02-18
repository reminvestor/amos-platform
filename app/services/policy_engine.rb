class PolicyEngine
  class << self
    def check(connection, operation_id, agent_role = nil)
      # Find applicable rules
      rules = find_applicable_rules(connection, operation_id, agent_role)

      # If no rules found, allow all operations for the connection's entity
      # This is the "open by default" policy for new integrations
      # Entities can add restrictive rules later if needed
      if rules.empty?
        # For custom/new integrations without rules, allow all operations
        # The integration was created by this entity, so they should be able to use it
        Rails.logger.info "PolicyEngine: No rules found for #{operation_id}, allowing by default"
        return true
      end

      # All rules must pass
      rules.all? do |rule|
        evaluate_rule(rule, connection, operation_id, agent_role)
      end
    end

    def check_budget(connection, operation_id)
      operation = connection.integration.integration_operations.find_by(operation_id: operation_id)
      return true unless operation

      # Check daily write budget
      if %w[POST PUT PATCH DELETE].include?(operation.http_method)
        return false unless connection.within_daily_budget?
      end

      # Check rate limits
      connection.within_rate_limit?
    end

    private

    def find_applicable_rules(connection, operation_id, agent_role)
      PolicyRule.active
                .where(
                  resource_type: [ "Connection", "Integration", "Operation" ],
                  entity_id: [ connection.entity_id, nil ]
                )
                .where(
                  "resource_id = ? OR resource_id = ? OR resource_id = ? OR resource_id IS NULL",
                  connection.id.to_s,
                  connection.integration_id.to_s,
                  operation_id
                )
                .where(
                  "agent_role = ? OR agent_role IS NULL",
                  agent_role
                )
    end

    def evaluate_rule(rule, connection, operation_id, agent_role)
      context = build_context(connection, operation_id, agent_role)

      result = case rule.conditions["type"]
      when "allow_list"
        evaluate_allow_list(rule.conditions, operation_id)
      when "deny_list"
        !evaluate_deny_list(rule.conditions, operation_id)
      when "time_window"
        evaluate_time_window(rule.conditions)
      when "budget_check"
        evaluate_budget(rule, connection)
      when "custom"
        evaluate_custom_conditions(rule.conditions, context)
      else
        Rails.logger.warn "PolicyEngine: Unknown rule type '#{rule.conditions['type']}' on rule #{rule.id}, allowing by default"
        true
      end

      unless result
        Rails.logger.info "PolicyEngine: Rule #{rule.id} (#{rule.conditions['type']}) blocked operation '#{operation_id}' on connection #{connection.id}"
      end

      result
    end

    def build_context(connection, operation_id, agent_role)
      {
        connection: connection,
        integration: connection.integration,
        operation_id: operation_id,
        agent_role: agent_role,
        time: Time.current,
        day_of_week: Time.current.wday,
        hour: Time.current.hour,
        entity: connection.entity,
        user_count: connection.entity.users.count
      }
    end

    def evaluate_allow_list(conditions, operation_id)
      allowed_operations = conditions["operations"] || []

      # Support wildcards
      allowed_operations.any? do |pattern|
        if pattern.include?("*")
          # Convert wildcard to regex
          regex_pattern = pattern.gsub(".", '\.').gsub("*", ".*")
          operation_id.match?(/\A#{regex_pattern}\z/)
        else
          operation_id == pattern
        end
      end
    end

    def evaluate_deny_list(conditions, operation_id)
      denied_operations = conditions["operations"] || []

      denied_operations.any? do |pattern|
        if pattern.include?("*")
          regex_pattern = pattern.gsub(".", '\.').gsub("*", ".*")
          operation_id.match?(/\A#{regex_pattern}\z/)
        else
          operation_id == pattern
        end
      end
    end

    def evaluate_time_window(conditions)
      start_time = Time.parse(conditions["start"]) rescue nil
      end_time = Time.parse(conditions["end"]) rescue nil

      return false unless start_time && end_time

      current = Time.current

      # Handle windows that cross midnight
      if start_time.hour > end_time.hour
        current.hour >= start_time.hour || current.hour <= end_time.hour
      else
        current.hour >= start_time.hour && current.hour <= end_time.hour
      end
    end

    def evaluate_budget(rule, connection)
      # Check against rule-specific limits
      if rule.max_daily_calls.present?
        todays_calls = connection.integration_logs
                                 .where(created_at: Time.current.beginning_of_day..)
                                 .count
        return false if todays_calls >= rule.max_daily_calls
      end

      if rule.max_write_calls.present?
        todays_writes = connection.integration_logs
                                  .where(created_at: Time.current.beginning_of_day..)
                                  .where(http_method: %w[POST PUT PATCH DELETE])
                                  .count
        return false if todays_writes >= rule.max_write_calls
      end

      true
    end

    def evaluate_custom_conditions(conditions, context)
      # For complex conditions, could integrate with a rules engine
      # For now, support simple Ruby expressions

      case conditions["expression"]
      when "business_hours_only"
        context[:hour] >= 9 && context[:hour] <= 17 && (1..5).include?(context[:day_of_week])
      when "high_value_entities_only"
        context[:entity].subscription_tier == "enterprise"
      else
        # Unknown custom rule - fail closed
        false
      end
    end
  end
end
