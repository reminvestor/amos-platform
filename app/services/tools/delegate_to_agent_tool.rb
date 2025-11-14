module Tools
  class DelegateToAgentTool < BaseTool
    def self.metadata
      {
        name: "delegate_to_agent",
        description: "Delegate a complex task directly to a specialized agent. The agent will handle the task independently and communicate progress back through Scout.",
        category: "task_management",
        input_schema: {
          type: "object",
          properties: {
            agent_type: {
              type: "string",
              description: "The type of specialist agent needed (e.g., 'landing_page_agent', 'email_agent', 'integration_agent', 'data_agent')"
            },
            task_description: {
              type: "string",
              description: "Clear description of what the agent should do"
            },
            context: {
              type: "object",
              description: "Any additional context or requirements for the agent",
              properties: {}
            }
          },
          required: [ "agent_type", "task_description" ]
        }
      }
    end

    def execute(args)
      Rails.logger.info "🤝 Delegating to agent: #{args['agent_type']}"

      agent_type = args["agent_type"]
      task_description = args["task_description"]
      additional_context = args["context"] || {}

      begin
        # Generate a unique job ID
        job_id = SecureRandom.uuid
        
        # Create job record for the agent
        job = Amos::JobRecord.create!(
          job_id: job_id,
          agent_type: agent_type,
          session_id: context[:session_id] || SecureRandom.uuid,
          status: 'queued',
          input_data: {
            task: task_description,
            user_id: user.id,
            entity_id: entity.id,
            context: additional_context.merge({
              model_preference: context[:model_preference],
              from_scout: true
            })
          },
          result_data: {},
          started_at: Time.current
        )

        # Queue the appropriate job based on agent type
        job_class = case agent_type.to_s
        when 'landing_page_agent'
          AgentJobs::LandingPageAgentJob
        when 'email_agent'
          AgentJobs::EmailAgentJob
        when 'integration_agent'
          AgentJobs::IntegrationAgentJob
        when 'data_agent'
          AgentJobs::DataAgentJob
        when 'analytics_agent'
          AgentJobs::AnalyticsAgentJob
        else
          # Try to find a custom agent
          agent_class = "AgentJobs::#{agent_type.to_s.camelize}Job"
          agent_class.constantize rescue nil
        end

        if job_class
          # Pass the correct parameters to the job
          job_class.perform_later(
            job_id: job_id,
            task: task_description,
            context: {
              user_id: user.id,
              entity_id: entity.id,
              session_id: context[:session_id],
              model_preference: context[:model_preference],
              additional_context: additional_context
            },
            callback_url: Rails.application.routes.url_helpers.amos_callback_url(
              session_id: context[:session_id] || job_id, 
              host: Rails.application.config.action_mailer.default_url_options[:host] || 'localhost'
            )
          )
          
          # Notify about the delegation
          @progress_callback&.call({
            type: "agent_delegated",
            agent: agent_type,
            job_id: job.id,
            message: "Task delegated to #{agent_type.to_s.humanize}"
          })
          
          # Automatically load the task monitor canvas if we have a session_id
          if context[:session_id]
            # Check if task monitor is already loaded
            unless current_canvas_is_task_monitor?
              Rails.logger.info "[DelegateToAgentTool] Auto-loading task monitor"
              ScoutChannel.broadcast_to(context[:session_id], {
                type: 'load_canvas',
                canvas_name: 'parallel_tasks',
                canvas_data: { session_id: context[:session_id] }
              })
            end
            
            # Broadcast job creation to task monitor
            ScoutChannel.broadcast_to(context[:session_id], {
              type: 'task_progress',
              job_id: job.id,
              status: 'created',
              agent_type: agent_type,
              message: "Starting #{agent_type.to_s.humanize.downcase}..."
            })
          end

          {
            success: true,
            job_id: job.id,
            agent_type: agent_type
          }
        else
          job.update!(status: 'failed', status_message: 'Unknown agent type')
          {
            success: false,
            error: "I don't recognize the agent type '#{agent_type}'"
          }
        end
      rescue => e
        Rails.logger.error "DelegateToAgentTool error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        {
          success: false,
          error: "Failed to delegate to agent: #{e.message}"
        }
      end
    end
    
    private
    
    def current_canvas_is_task_monitor?
      # Check if the current canvas context shows task monitor is loaded
      # This is a simple check - could be enhanced based on actual state tracking
      @context[:current_canvas] && @context[:current_canvas][:type] == 'parallel_tasks'
    end
  end
end
