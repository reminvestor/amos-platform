# frozen_string_literal: true

class AiSettings::SecurityController < ApplicationController
  before_action :authenticate_user!
  before_action :require_entity_admin!

  layout "customer_admin"

  def show
    redirect_to chat_mode_path, status: :moved_permanently
  end

  def update
    # Q-LLM (CAMEL) is always on — not a user-configurable setting.

    # Update individual tool policies
    if params[:tool_policies].present?
      params[:tool_policies].each do |tool_name, settings|
        requires_confirmation = settings[:requires_confirmation] == "1"
        ToolPolicyService.update_policy(
          entity: current_entity,
          tool_name: tool_name,
          requires_confirmation: requires_confirmation
        )
      end
    end

    redirect_to chat_mode_path, notice: "Security settings updated successfully."
  rescue => e
    Rails.logger.error "[SecuritySettings] Update failed: #{e.message}"
    redirect_to chat_mode_path, alert: "Failed to update settings: #{e.message}"
  end

  def reset_to_defaults
    # Delete all custom tool policies for this entity
    PolicyRule.where(entity: current_entity, resource_type: 'Tool').destroy_all

    # Q-LLM (CAMEL) is always on — nothing to reset.

    redirect_to chat_mode_path, notice: "Security settings reset to defaults."
  end

  def expire_pending
    count = PendingToolConfirmation
      .where(entity: current_entity)
      .where(status: 'pending')
      .update_all(status: 'expired', resolved_at: Time.current)

    redirect_to chat_mode_path, notice: "Expired #{count} pending confirmations."
  end

  private

  def require_entity_admin!
    unless current_user.entity_admin?
      redirect_to chat_mode_path, alert: "You need to be an entity admin to access AI settings."
    end
  end

  def categorize_policies(policies)
    categories = {
      "Data Operations" => [],
      "Communication" => [],
      "Integrations" => [],
      "Publishing" => [],
      "CRM" => [],
      "Automation" => [],
      "Read Only" => [],
      "Other" => []
    }

    policies.each do |tool_name, policy|
      category = case policy[:category]
                 when 'data' then policy[:action] == 'read' ? "Read Only" : "Data Operations"
                 when 'communication' then "Communication"
                 when 'integration' then "Integrations"
                 when 'publish' then "Publishing"
                 when 'crm' then "CRM"
                 when 'automation' then "Automation"
                 when 'ui', 'system', 'display' then "Read Only"
                 else "Other"
                 end
      
      categories[category] << { name: tool_name, **policy }
    end

    # Sort each category
    categories.each { |_, tools| tools.sort_by! { |t| t[:name] } }
    
    # Remove empty categories
    categories.reject { |_, tools| tools.empty? }
  end
end
