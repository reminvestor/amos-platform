# frozen_string_literal: true

# Archive the old AI Landing Page Creator agent
# It has been replaced by Landing Page Manager which has better capabilities
class ArchiveAiLandingPageCreatorAgent < ActiveRecord::Migration[7.1]
  def up
    # Find and archive the old agent
    execute <<-SQL
      UPDATE agent_plugins 
      SET status = 'archived', 
          updated_at = NOW()
      WHERE slug = 'ai_landing_page_creator'
        AND status != 'archived';
    SQL
    
    # Log what was done
    agent = AgentPlugin.find_by(slug: 'ai_landing_page_creator') rescue nil
    if agent
      Rails.logger.info "📦 Archived AI Landing Page Creator (id: #{agent.id})"
    else
      Rails.logger.info "📦 AI Landing Page Creator not found or already archived"
    end
  end

  def down
    # Reversible but should not be undone
    execute <<-SQL
      UPDATE agent_plugins 
      SET status = 'active', 
          updated_at = NOW()
      WHERE slug = 'ai_landing_page_creator';
    SQL
  end
end
