# frozen_string_literal: true

# Update agent spaces for unified mode (no more separate Operations/Design dropdown)
# Key agents need to be accessible from both operations and design modes
class UpdateAgentSpacesForUnifiedMode < ActiveRecord::Migration[7.1]
  def up
    # Agents that should be accessible from both operations and design
    unified_agents = %w[
      landing_page_manager
      workflow_architect
      application_planner
      frontend_design_expert
      module_architect
      platform_factory
    ]
    
    unified_agents.each do |slug|
      execute <<-SQL
        UPDATE agent_plugins 
        SET spaces = '["operations", "design"]'::jsonb,
            updated_at = NOW()
        WHERE slug = '#{slug}';
      SQL
    end
    
    Rails.logger.info "📦 Updated #{unified_agents.count} agents to unified operations+design spaces"
  end

  def down
    # Revert to original spaces
    execute <<-SQL
      UPDATE agent_plugins 
      SET spaces = '["work", "team"]'::jsonb,
          updated_at = NOW()
      WHERE slug = 'landing_page_manager';
    SQL
    
    execute <<-SQL
      UPDATE agent_plugins 
      SET spaces = '["design"]'::jsonb,
          updated_at = NOW()
      WHERE slug = 'workflow_architect';
    SQL
  end
end
