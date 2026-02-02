# frozen_string_literal: true

# DefaultPoliciesService
#
# Creates sensible default AI usage policies for an entity.
# These policies ensure user protection while allowing AI to operate effectively.
#
# Usage:
#   DefaultPoliciesService.create_for(entity)
#
class DefaultPoliciesService
  DEFAULT_POLICIES = [
    # === WRITE PROTECTION ===
    {
      name: "Require confirmation for write operations",
      resource_type: "Operation",
      action: "write",
      requires_confirmation: true,
      is_active: true,
      agent_role: nil,
      conditions: {
        type: "confirmation_required",
        description: "User must approve before AI can create or modify records"
      }
    },
    
    # === DELETE PROTECTION ===
    {
      name: "Require confirmation for delete operations",
      resource_type: "Operation",
      action: "delete",
      requires_confirmation: true,
      is_active: true,
      agent_role: nil,
      conditions: {
        type: "confirmation_required",
        description: "User must approve before AI can delete records"
      }
    },
    
    # === EXTERNAL API PROTECTION ===
    {
      name: "Limit external API calls",
      resource_type: "Integration",
      action: "execute",
      requires_confirmation: false,
      is_active: true,
      max_daily_calls: 1000,
      agent_role: nil,
      conditions: {
        type: "budget_check",
        description: "Prevents runaway API usage"
      }
    },
    
    # === EMAIL SENDING PROTECTION ===
    {
      name: "Require confirmation for email sending",
      resource_type: "Tool",
      resource_id: "send_email",
      action: "execute",
      requires_confirmation: true,
      is_active: true,
      max_daily_calls: 100,
      agent_role: nil,
      conditions: {
        type: "confirmation_required",
        description: "User must approve before AI sends emails"
      }
    },
    
    # === BULK OPERATIONS PROTECTION ===
    {
      name: "Require confirmation for bulk operations",
      resource_type: "Tool",
      resource_id: "bulk_update",
      action: "execute",
      requires_confirmation: true,
      is_active: true,
      agent_role: nil,
      conditions: {
        type: "confirmation_required",
        description: "User must approve before AI performs bulk updates"
      }
    },
    
    # === PAYMENT/FINANCIAL PROTECTION ===
    {
      name: "Block financial operations without confirmation",
      resource_type: "Tool",
      resource_id: "process_payment",
      action: "execute",
      requires_confirmation: true,
      is_active: true,
      agent_role: nil,
      conditions: {
        type: "confirmation_required",
        description: "Financial operations always require user approval"
      }
    },
    
    # === DATA EXPORT PROTECTION ===
    {
      name: "Require confirmation for data exports",
      resource_type: "Tool",
      resource_id: "export_data",
      action: "execute",
      requires_confirmation: true,
      is_active: true,
      agent_role: nil,
      conditions: {
        type: "confirmation_required",
        description: "User must approve before AI exports data"
      }
    },
    
    # === READ ACCESS (Allow by default) ===
    {
      name: "Allow read operations",
      resource_type: "Global",
      action: "read",
      requires_confirmation: false,
      is_active: true,
      agent_role: nil,
      conditions: {
        type: "allow",
        description: "AI can freely read data to assist users"
      }
    }
  ].freeze

  class << self
    # Create default policies for an entity
    def create_for(entity)
      return if entity.nil?
      
      created_count = 0
      
      DEFAULT_POLICIES.each do |policy_attrs|
        # Skip if policy already exists
        next if entity.policy_rules.exists?(name: policy_attrs[:name])
        
        entity.policy_rules.create!(policy_attrs)
        created_count += 1
      end
      
      Rails.logger.info "[DefaultPoliciesService] Created #{created_count} policies for entity #{entity.id}"
      created_count
    rescue => e
      Rails.logger.error "[DefaultPoliciesService] Failed to create policies: #{e.message}"
      0
    end

    # Create global fallback policies (no entity)
    def create_global_fallbacks
      global_policies = [
        {
          name: "[Global] Require confirmation for all writes",
          resource_type: "Global",
          action: "write",
          requires_confirmation: true,
          is_active: true,
          agent_role: nil,
          conditions: {
            type: "fallback",
            description: "Global fallback - requires confirmation for any write"
          }
        },
        {
          name: "[Global] Require confirmation for all deletes",
          resource_type: "Global",
          action: "delete",
          requires_confirmation: true,
          is_active: true,
          agent_role: nil,
          conditions: {
            type: "fallback",
            description: "Global fallback - requires confirmation for any delete"
          }
        }
      ]

      created_count = 0
      
      global_policies.each do |policy_attrs|
        next if PolicyRule.where(entity_id: nil).exists?(name: policy_attrs[:name])
        
        PolicyRule.create!(policy_attrs.merge(entity_id: nil))
        created_count += 1
      end
      
      created_count
    end

    # Backfill policies for entities that don't have them
    def backfill_all
      Entity.find_each do |entity|
        create_for(entity) if entity.policy_rules.empty?
      end
      
      create_global_fallbacks
    end
  end
end
