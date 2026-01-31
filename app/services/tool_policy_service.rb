# frozen_string_literal: true

# ToolPolicyService - CaMeL-style policy enforcement for tool execution
#
# Checks whether a tool execution should:
# 1. Proceed automatically (trusted data, read-only operations)
# 2. Require user confirmation (write operations, untrusted data)
# 3. Be blocked entirely (policy violation)
#
# Integrates with existing PolicyEngine and PolicyRule infrastructure.
#
# Usage:
#   result = ToolPolicyService.check(
#     entity: entity,
#     user: user,
#     tool_name: 'send_email',
#     args: { recipient: email, subject: subject },
#     data_sources: DataSourceTracker.collect_sources(args)
#   )
#
#   if result[:requires_confirmation]
#     # Ask user to confirm
#   elsif result[:allowed]
#     # Execute
#   else
#     # Block
#   end
#
class ToolPolicyService
  # Default policies for tools (used when no entity-specific rule exists)
  # Users can override these in AI Settings
  DEFAULT_POLICIES = {
    # Write operations - confirm by default
    'create_object' => { requires_confirmation: true, action: 'write', category: 'data' },
    'update_object' => { requires_confirmation: true, action: 'write', category: 'data' },
    'delete_object' => { requires_confirmation: true, action: 'write', category: 'data' },
    
    # Communication - confirm and check trust
    'send_email' => { requires_confirmation: true, action: 'execute', category: 'communication', trust_required: true },
    
    # Integration operations - confirm writes
    'execute_integration' => { requires_confirmation: true, action: 'execute', category: 'integration' },
    'invoke_operation' => { requires_confirmation: true, action: 'execute', category: 'integration' },
    
    # Publishing - always confirm
    'publish_app' => { requires_confirmation: true, action: 'execute', category: 'publish' },
    'publish_landing_page' => { requires_confirmation: true, action: 'execute', category: 'publish' },
    
    # Contact management - confirm creates/updates
    'create_contact' => { requires_confirmation: true, action: 'write', category: 'crm' },
    'update_contact' => { requires_confirmation: true, action: 'write', category: 'crm' },
    
    # CRM operations
    'create_opportunity' => { requires_confirmation: true, action: 'write', category: 'crm' },
    'create_activity' => { requires_confirmation: false, action: 'write', category: 'crm' }, # Activities are often auto-logged
    
    # Sequence operations
    'enroll_in_sequence' => { requires_confirmation: true, action: 'execute', category: 'automation' },
    
    # Read operations - no confirmation needed
    'get_data' => { requires_confirmation: false, action: 'read', category: 'data' },
    'search_contacts' => { requires_confirmation: false, action: 'read', category: 'data' },
    'search_documents' => { requires_confirmation: false, action: 'read', category: 'data' },
    'query_rag_store' => { requires_confirmation: false, action: 'read', category: 'data' },
    'discover_tools' => { requires_confirmation: false, action: 'read', category: 'system' },
    'get_schema' => { requires_confirmation: false, action: 'read', category: 'system' },
    
    # Display operations - no confirmation
    'create_freeform_canvas' => { requires_confirmation: false, action: 'display', category: 'ui' },
    'load_design_canvas' => { requires_confirmation: false, action: 'display', category: 'ui' },
    'create_dynamic_visualization' => { requires_confirmation: false, action: 'display', category: 'ui' }
  }.freeze

  # Categories that are generally safe (no confirmation even if not explicitly listed)
  SAFE_CATEGORIES = %w[read display system].freeze

  class << self
    # Main policy check method
    # @param entity [Entity] The entity performing the action
    # @param user [User] The user performing the action
    # @param tool_name [String] Name of the tool being executed
    # @param args [Hash] Arguments being passed to the tool
    # @param data_sources [Array<Hash>] Data sources collected from args
    # @return [Hash] Policy decision
    def check(entity:, user:, tool_name:, args: {}, data_sources: [])
      # Get applicable policy (entity override or default)
      policy = get_policy(entity, tool_name)
      
      # If no policy and tool is not in defaults, allow by default
      # (fail-open for unknown tools, but log for review)
      unless policy
        Rails.logger.info "[ToolPolicy] No policy for #{tool_name}, allowing by default"
        return { allowed: true, requires_confirmation: false, reason: 'no_policy' }
      end
      
      # Check entity-level settings for confirmation overrides
      confirmation_required = check_confirmation_required(entity, policy, data_sources)
      
      # Build the decision
      decision = {
        allowed: true,
        requires_confirmation: confirmation_required,
        policy: policy,
        tool_name: tool_name,
        action: policy[:action],
        category: policy[:category]
      }
      
      # Add reason and untrusted sources if confirmation needed
      if confirmation_required
        decision[:reason] = build_confirmation_reason(tool_name, policy, data_sources)
        decision[:untrusted_sources] = data_sources.select { |ds| ds[:trust_level] != :trusted }
        decision[:action_description] = describe_action(tool_name, args)
      end
      
      decision
    end

    # Check if user has already confirmed this type of action recently
    # @param entity [Entity]
    # @param user [User]
    # @param tool_name [String]
    # @param args [Hash]
    # @return [Boolean]
    def recently_confirmed?(entity:, user:, tool_name:, args:)
      # Check session-based confirmations (stored in cache)
      cache_key = "tool_confirmed:#{entity.id}:#{user.id}:#{tool_name}:#{args.hash}"
      Rails.cache.exist?(cache_key)
    end

    # Record that user confirmed an action
    # @param entity [Entity]
    # @param user [User]
    # @param tool_name [String]
    # @param args [Hash]
    def record_confirmation(entity:, user:, tool_name:, args:)
      cache_key = "tool_confirmed:#{entity.id}:#{user.id}:#{tool_name}:#{args.hash}"
      Rails.cache.write(cache_key, true, expires_in: 5.minutes)
    end

    # Get entity's policy for a specific tool
    # @param entity [Entity]
    # @param tool_name [String]
    # @return [Hash, nil]
    def get_policy(entity, tool_name)
      # Check for entity-specific override in PolicyRule
      entity_rule = PolicyRule.active
        .where(entity: entity)
        .where(resource_type: 'Tool')
        .where("resource_id = ? OR conditions->>'tool_name' = ?", tool_name, tool_name)
        .first
      
      if entity_rule
        return {
          requires_confirmation: entity_rule.requires_confirmation,
          action: entity_rule.action,
          category: entity_rule.conditions&.dig('category') || 'custom',
          trust_required: entity_rule.conditions&.dig('trust_required'),
          source: :entity_rule
        }
      end
      
      # Fall back to default policy
      default = DEFAULT_POLICIES[tool_name.to_s]
      return default.merge(source: :default) if default
      
      # Check if tool name suggests a safe category
      if tool_name.to_s.start_with?('get_', 'search_', 'query_', 'list_', 'load_')
        return { requires_confirmation: false, action: 'read', category: 'data', source: :inferred }
      end
      
      nil
    end

    # Get all policies for an entity (for settings UI)
    # @param entity [Entity]
    # @return [Hash] Tool name => policy
    def all_policies_for_entity(entity)
      policies = {}
      
      # Start with defaults
      DEFAULT_POLICIES.each do |tool_name, policy|
        policies[tool_name] = policy.merge(source: :default)
      end
      
      # Override with entity-specific rules
      PolicyRule.active
        .where(entity: entity)
        .where(resource_type: 'Tool')
        .each do |rule|
          tool_name = rule.resource_id || rule.conditions&.dig('tool_name')
          next unless tool_name
          
          policies[tool_name] = {
            requires_confirmation: rule.requires_confirmation,
            action: rule.action,
            category: rule.conditions&.dig('category') || 'custom',
            source: :entity_rule,
            rule_id: rule.id
          }
        end
      
      policies
    end

    # Update policy for an entity
    # @param entity [Entity]
    # @param tool_name [String]
    # @param requires_confirmation [Boolean]
    def update_policy(entity:, tool_name:, requires_confirmation:)
      rule = PolicyRule.find_or_initialize_by(
        entity: entity,
        resource_type: 'Tool',
        resource_id: tool_name
      )
      
      default = DEFAULT_POLICIES[tool_name] || {}
      
      rule.update!(
        name: "#{tool_name} policy",
        action: default[:action] || 'execute',
        requires_confirmation: requires_confirmation,
        conditions: {
          tool_name: tool_name,
          category: default[:category] || 'custom'
        },
        is_active: true
      )
      
      rule
    end

    private

    def check_confirmation_required(entity, policy, data_sources)
      # If policy explicitly requires confirmation, check it
      return false unless policy[:requires_confirmation]
      
      # If trust is required and we have untrusted data, definitely confirm
      if policy[:trust_required]
        has_untrusted = data_sources.any? { |ds| ds[:trust_level] != :trusted }
        return true if has_untrusted
      end
      
      # Otherwise, use the policy's requires_confirmation setting
      policy[:requires_confirmation]
    end

    def build_confirmation_reason(tool_name, policy, data_sources)
      reasons = []
      
      case policy[:action]
      when 'write'
        reasons << "This will modify data"
      when 'execute'
        reasons << "This will perform an action"
      end
      
      untrusted = data_sources.select { |ds| ds[:trust_level] != :trusted }
      if untrusted.any?
        sources = untrusted.map { |ds| ds[:source].to_s.humanize }.uniq.join(', ')
        reasons << "Uses data from: #{sources}"
      end
      
      reasons.join('. ')
    end

    def describe_action(tool_name, args)
      case tool_name.to_s
      when 'send_email'
        recipient = args[:recipient] || args['recipient'] || 'unknown'
        subject = args[:subject] || args['subject'] || 'no subject'
        "Send email to #{recipient}: \"#{subject.to_s.truncate(50)}\""
      when 'create_object'
        type = args[:object_type] || args['object_type'] || 'record'
        "Create new #{type}"
      when 'update_object'
        type = args[:object_type] || args['object_type'] || 'record'
        "Update #{type}"
      when 'delete_object'
        type = args[:object_type] || args['object_type'] || 'record'
        "Delete #{type}"
      when 'execute_integration'
        operation = args[:operation_id] || args['operation_id'] || 'operation'
        "Execute integration: #{operation}"
      when 'enroll_in_sequence'
        "Enroll contact in email sequence"
      when 'publish_app', 'publish_landing_page'
        "Publish to production"
      else
        tool_name.to_s.humanize
      end
    end
  end
end
