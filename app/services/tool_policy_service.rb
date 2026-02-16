# frozen_string_literal: true

# ToolPolicyService
#
# Bridges the PolicyRule model with the tool execution system.
# Determines whether tools require user confirmation before executing,
# manages confirmation caching, and provides a unified API for the
# AiSettings::SecurityController and ToolConfirmationsController.
#
# Uses PolicyRule records (resource_type: 'Tool') for entity-specific overrides,
# falling back to sensible defaults based on tool name patterns and categories.
#
class ToolPolicyService
  # Default tool policies — used when no entity-specific PolicyRule exists.
  # Tools not listed here inherit policy from name-pattern inference.
  DEFAULT_TOOL_POLICIES = {
    # Data operations (write)
    "create_object"  => { action: "write",   category: "data",          requires_confirmation: true },
    "update_object"  => { action: "write",   category: "data",          requires_confirmation: true },
    "bulk_update"    => { action: "write",   category: "data",          requires_confirmation: true },
    "delete_object"  => { action: "delete",  category: "data",          requires_confirmation: true },
    "export_data"    => { action: "execute", category: "data",          requires_confirmation: true },

    # Communication
    "send_email"     => { action: "execute", category: "communication", requires_confirmation: true },
    "send_campaign"  => { action: "execute", category: "communication", requires_confirmation: true },

    # Financial
    "process_payment" => { action: "execute", category: "financial",    requires_confirmation: true },

    # Integrations
    "invoke_operation" => { action: "execute", category: "integration", requires_confirmation: false },
    "list_connections" => { action: "read",    category: "integration", requires_confirmation: false },
    "list_operations"  => { action: "read",    category: "integration", requires_confirmation: false },

    # Publishing
    "generate_ai_landing_page" => { action: "write",  category: "publish", requires_confirmation: false },

    # Read-only / display
    "get_data"             => { action: "read", category: "data",    requires_confirmation: false },
    "get_workflow_context"  => { action: "read", category: "system",  requires_confirmation: false },
    "manage_task_list"      => { action: "read", category: "system",  requires_confirmation: false },
    "web_search_tool"       => { action: "read", category: "system",  requires_confirmation: false },
    "load_canvas"           => { action: "read", category: "display", requires_confirmation: false },

    # CRM
    "create_contact"   => { action: "write", category: "crm", requires_confirmation: true },
    "update_contact"   => { action: "write", category: "crm", requires_confirmation: true },

    # Automation
    "delegate_to_planner_tool" => { action: "execute", category: "automation", requires_confirmation: false }
  }.freeze

  class << self
    # ═══════════════════════════════════════════════════════════════
    # CHECK — Does this tool require confirmation right now?
    # ═══════════════════════════════════════════════════════════════

    def check(entity:, user:, tool_name:, args: {}, data_sources: [])
      policy = get_policy(entity, tool_name)

      result = {
        allowed: true,
        requires_confirmation: policy ? policy[:requires_confirmation] : false,
        action: policy ? policy[:action] : "execute",
        policy_source: policy ? policy[:source] : :none
      }

      # If action requires confirmation, generate a description
      if result[:requires_confirmation]
        result[:action_description] = describe_action(tool_name, args)

        # Check if recently confirmed (cached)
        if recently_confirmed?(entity: entity, user: user, tool_name: tool_name, args: args)
          result[:requires_confirmation] = false
          result[:cached_confirmation] = true
        end
      end

      # Flag untrusted data sources
      if data_sources.any?
        untrusted = data_sources.select { |ds| ds[:trust_level] == :untrusted }
        if untrusted.any?
          result[:requires_confirmation] = true
          result[:untrusted_sources] = untrusted
        end
      end

      result
    end

    # ═══════════════════════════════════════════════════════════════
    # GET POLICY — Resolve the effective policy for a tool
    # ═══════════════════════════════════════════════════════════════

    def get_policy(entity, tool_name)
      # 1. Check for entity-specific PolicyRule override
      if entity
        entity_rule = PolicyRule.active
                                .where(entity: entity, resource_type: "Tool", resource_id: tool_name)
                                .first

        if entity_rule
          return {
            action: entity_rule.action,
            category: infer_category(tool_name),
            requires_confirmation: entity_rule.requires_confirmation,
            source: :entity_rule,
            max_daily_calls: entity_rule.max_daily_calls,
            max_write_calls: entity_rule.max_write_calls
          }
        end
      end

      # 2. Check hardcoded defaults
      default = DEFAULT_TOOL_POLICIES[tool_name]
      if default
        return default.merge(source: :default)
      end

      # 3. Infer from tool name pattern
      infer_policy_from_name(tool_name)
    end

    # ═══════════════════════════════════════════════════════════════
    # ALL POLICIES — List everything for the settings UI
    # ═══════════════════════════════════════════════════════════════

    def all_policies_for_entity(entity)
      policies = {}

      # Start with defaults
      DEFAULT_TOOL_POLICIES.each do |tool_name, policy|
        policies[tool_name] = policy.merge(source: :default)
      end

      # Apply entity overrides
      if entity
        PolicyRule.active
                  .where(entity: entity, resource_type: "Tool")
                  .find_each do |rule|
          policies[rule.resource_id] = {
            action: rule.action,
            category: infer_category(rule.resource_id),
            requires_confirmation: rule.requires_confirmation,
            source: :entity_rule,
            max_daily_calls: rule.max_daily_calls,
            max_write_calls: rule.max_write_calls
          }
        end
      end

      policies
    end

    # ═══════════════════════════════════════════════════════════════
    # UPDATE POLICY — Create or update an entity-specific override
    # ═══════════════════════════════════════════════════════════════

    def update_policy(entity:, tool_name:, requires_confirmation:)
      rule = PolicyRule.find_or_initialize_by(
        entity: entity,
        resource_type: "Tool",
        resource_id: tool_name
      )

      default = DEFAULT_TOOL_POLICIES[tool_name] || {}

      rule.assign_attributes(
        name: "#{requires_confirmation ? 'Require confirmation' : 'Auto-allow'} for #{tool_name}",
        action: default[:action] || infer_action(tool_name),
        requires_confirmation: requires_confirmation,
        is_active: true,
        conditions: { type: "entity_override", updated_by: "settings_ui" }
      )

      rule.save!
      rule
    end

    # ═══════════════════════════════════════════════════════════════
    # CONFIRMATION CACHE — Prevent duplicate confirmations
    # ═══════════════════════════════════════════════════════════════

    def record_confirmation(entity:, user:, tool_name:, args:)
      cache_key = confirmation_cache_key(entity, user, tool_name, args)
      Rails.cache.write(cache_key, true, expires_in: 10.minutes)
    end

    def recently_confirmed?(entity:, user:, tool_name:, args:)
      cache_key = confirmation_cache_key(entity, user, tool_name, args)
      Rails.cache.read(cache_key) == true
    end

    private

    def confirmation_cache_key(entity, user, tool_name, args)
      # Hash the args so similar calls share the confirmation window
      args_hash = Digest::MD5.hexdigest(args.to_json)[0..7]
      "tool_confirmation:#{entity.id}:#{user.id}:#{tool_name}:#{args_hash}"
    end

    def describe_action(tool_name, args)
      case tool_name
      when "send_email"
        to = args[:recipient] || args["recipient"] || args.dig(:inputs, :to) || args.dig("inputs", "to")
        "Send email to #{to || 'recipient'}"
      when "send_campaign"
        id = args[:campaign_id] || args["campaign_id"]
        "Send campaign ##{id} to all recipients"
      when "create_object", "create_contact"
        type = args[:object_type] || args["object_type"] || args[:type] || args["type"]
        "Create new #{type || 'record'}"
      when "update_object", "update_contact"
        type = args[:object_type] || args["object_type"]
        id = args[:id] || args["id"]
        "Update #{type} ##{id}"
      when "delete_object"
        type = args[:object_type] || args["object_type"]
        id = args[:id] || args["id"]
        "Delete #{type} ##{id}"
      when "process_payment"
        amount = args[:amount] || args["amount"]
        "Process payment of #{amount}"
      when "bulk_update"
        type = args[:object_type] || args["object_type"]
        count = args[:count] || args["count"]
        "Bulk update #{count || 'multiple'} #{type || 'records'}"
      when "export_data"
        type = args[:type] || args["type"]
        "Export #{type || 'data'}"
      else
        "Execute #{tool_name}"
      end
    end

    def infer_policy_from_name(tool_name)
      case tool_name
      when /^get_/, /^list_/, /^search_/, /^find_/, /^view_/, /^read_/
        { action: "read", category: infer_category(tool_name), requires_confirmation: false, source: :inferred }
      when /^create_/, /^add_/, /^insert_/
        { action: "write", category: infer_category(tool_name), requires_confirmation: true, source: :inferred }
      when /^update_/, /^edit_/, /^modify_/
        { action: "write", category: infer_category(tool_name), requires_confirmation: true, source: :inferred }
      when /^delete_/, /^remove_/, /^destroy_/
        { action: "delete", category: infer_category(tool_name), requires_confirmation: true, source: :inferred }
      when /^send_/, /^email_/, /^notify_/
        { action: "execute", category: "communication", requires_confirmation: true, source: :inferred }
      when /^export_/, /^download_/
        { action: "execute", category: "data", requires_confirmation: true, source: :inferred }
      else
        nil
      end
    end

    def infer_action(tool_name)
      case tool_name
      when /^get_/, /^list_/, /^search_/, /^find_/, /^view_/, /^read_/ then "read"
      when /^create_/, /^add_/, /^insert_/, /^update_/, /^edit_/ then "write"
      when /^delete_/, /^remove_/, /^destroy_/ then "delete"
      else "execute"
      end
    end

    def infer_category(tool_name)
      return nil unless tool_name
      case tool_name
      when /email|campaign|send|notify/ then "communication"
      when /payment|charge|invoice|billing/ then "financial"
      when /integration|connection|operation|invoke/ then "integration"
      when /contact|lead|deal|company/ then "crm"
      when /landing_page|publish|website/ then "publish"
      when /export|import|bulk/ then "data"
      when /canvas|display|load|view/ then "display"
      when /search|get|list|read|query|context|task/ then "system"
      else "other"
      end
    end
  end
end
