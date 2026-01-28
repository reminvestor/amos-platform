# Manages conversation state and context for Amos
module Amos
  class ConversationContext
    attr_reader :session_id, :messages, :job_results, :user, :entity, :fresh_start_at
    
    def initialize(session_id, user, entity, fresh_start_at: nil)
      @session_id = session_id
      @user = user
      @entity = entity
      @fresh_start_at = fresh_start_at  # Filter memory to only after this time
      @messages = []
      @job_results = {}
      @active_workflows = {}
      load_existing_context
    end
    
    def add_message(source, content, metadata = {})
      # Ensure metadata is a regular hash, not ActionController::Parameters
      clean_metadata = case metadata
                       when ActionController::Parameters
                         metadata.to_h.deep_symbolize_keys
                       when Hash
                         metadata.deep_symbolize_keys
                       else
                         {}
                       end
                       
      @messages << {
        source: source,
        content: content,
        metadata: clean_metadata,
        timestamp: Time.current
      }
      
      # Keep context window manageable
      @messages = @messages.last(50)
    end
    
    def add_job_result(job_id, result)
      @job_results[job_id] = {
        result: result,
        timestamp: Time.current
      }
    end
    
    def snapshot
      {
        session_id: @session_id,
        user_id: @user.id,
        entity_id: @entity.id,
        recent_messages: recent_messages(12),  # Full 12 message context window
        active_jobs: @job_results.keys,
        entity_context: entity_snapshot,
        timestamp: Time.current
      }
    end
    
    def recent_messages(limit = 10)
      @messages.last(limit).map { |m|
        # Ensure metadata is a plain hash
        clean_meta = case m[:metadata]
                     when ActionController::Parameters
                       m[:metadata].to_h.deep_symbolize_keys
                     when Hash
                       m[:metadata].deep_symbolize_keys
                     else
                       {}
                     end
        
        {
          role: source_to_role(m[:source]),
          content: m[:content],
          metadata: clean_meta
        }
      }
    end
    
    def has_active_workflow?
      @active_workflows.any?
    end
    
    def active_workflow
      @active_workflows.values.first
    end
    
    def set_active_workflow(job_id, workflow_data)
      @active_workflows[job_id] = workflow_data.merge(job_id: job_id)
    end
    
    def clear_workflow(job_id)
      @active_workflows.delete(job_id)
    end
    
    def entity_snapshot
      {
        name: @entity.name,
        subdomain: @entity.subdomain,
        settings: @entity.settings,
        has_stripe: @entity.connections.joins(:integration).exists?(integrations: { slug: 'stripe' }),
        landing_pages_count: @entity.landing_pages.count,
        contacts_count: @entity.contacts.count
      }
    end
    
    private
    
    def load_existing_context
      # Load recent messages from database
      scope = ScoutMessage
        .where(session_id: @session_id)
      
      # Filter by fresh_start_at if set (excludes old messages from before Fresh Start)
      if @fresh_start_at
        scope = scope.where("created_at > ?", @fresh_start_at)
        Rails.logger.info "📜 [ConversationContext] Filtering to messages after fresh_start: #{@fresh_start_at}"
      end
      
      recent_scout_messages = scope
        .order(created_at: :desc)
        .limit(20)
        .reverse
      
      recent_scout_messages.each do |msg|
        add_message(
          msg.role == 'user' ? :user : :assistant,
          msg.content,
          msg.metadata || {}
        )
      end
    end
    
    def source_to_role(source)
      case source
      when :user then 'user'
      when :assistant, :amos then 'assistant'
      when :system then 'system'
      else 'assistant'
      end
    end
  end
end

