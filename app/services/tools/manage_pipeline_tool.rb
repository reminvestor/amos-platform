module Tools
  class ManagePipelineTool < BaseTool
    def self.metadata
      {
        name: "manage_pipeline",
        description: "Create, list, monitor, and control AI development pipelines. Use this to start automated code generation pipelines from tickets, check pipeline status, retry failed pipelines, or cancel stuck ones.",
        category: "ai_pipeline",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: ["create", "list", "show", "retry", "cancel", "approve", "reject", "answer"],
              description: "Action to perform: create (start new pipeline), list (show pipelines), show (get details), retry (restart failed), cancel (stop running), approve (approve prod deployment), reject (reject changes), answer (respond to clarification)"
            },
            ticket_id: {
              type: "string",
              description: "Ticket ID (e.g., JIRA-123) for create action"
            },
            ticket_system: {
              type: "string",
              enum: ["jira", "azure_devops", "manual"],
              description: "Ticket system type (defaults to 'manual' if not from JIRA/Azure)"
            },
            ticket_title: {
              type: "string",
              description: "Ticket title/description for manual pipelines"
            },
            ticket_description: {
              type: "string",
              description: "Full ticket description for manual pipelines"
            },
            priority: {
              type: "string",
              enum: ["critical", "high", "medium", "low"],
              description: "Pipeline priority (defaults to 'medium')"
            },
            mcp_connection_id: {
              type: "integer",
              description: "MCP connection ID for JIRA/Azure ticket systems"
            },
            git_connection_id: {
              type: "integer",
              description: "Git connection ID (GitHub/Azure Repos)"
            },
            pipeline_id: {
              type: "integer",
              description: "Pipeline execution ID for show/retry/cancel/approve/reject actions"
            },
            status_filter: {
              type: "string",
              enum: ["new", "clarifying", "planning", "implementing", "review", "testing", "dev", "staging", "awaiting_prod_approval", "prod", "done", "failed", "blocked"],
              description: "Filter pipelines by status for list action"
            },
            limit: {
              type: "integer",
              description: "Number of pipelines to return in list (default 10, max 50)"
            },
            interaction_id: {
              type: "integer",
              description: "Interaction ID for approve/reject/answer actions"
            },
            response: {
              type: "string",
              description: "Response text for answer action (answering clarification questions)"
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action)

      # Validate required args
      if error = validate_required_args(args, [:action])
        return error
      end

      begin
        case action
        when "create"
          create_pipeline(args)
        when "list"
          list_pipelines(args)
        when "show"
          show_pipeline(args)
        when "retry"
          retry_pipeline(args)
        when "cancel"
          cancel_pipeline(args)
        when "approve"
          approve_interaction(args)
        when "reject"
          reject_interaction(args)
        when "answer"
          answer_clarification(args)
        else
          error_response("Unknown action: #{action}")
        end
      rescue => e
        Rails.logger.error "Pipeline tool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Pipeline operation failed: #{e.message}")
      end
    end

    private

    def create_pipeline(args)
      ticket_id = get_arg(args, :ticket_id)
      ticket_system = get_arg(args, :ticket_system, 'manual')
      ticket_title = get_arg(args, :ticket_title)
      ticket_description = get_arg(args, :ticket_description)
      priority = get_arg(args, :priority, 'medium')
      mcp_connection_id = get_arg(args, :mcp_connection_id)
      git_connection_id = get_arg(args, :git_connection_id)

      # Validate required fields
      unless ticket_id.present?
        return error_response("ticket_id is required for creating a pipeline")
      end

      unless ticket_title.present?
        return error_response("ticket_title is required for creating a pipeline")
      end

      # For manual tickets, generate ticket_id if not provided
      if ticket_system == 'manual' && !ticket_id.start_with?('MANUAL-')
        ticket_id = "MANUAL-#{Time.now.to_i}"
      end

      # Get MCP connection if specified
      mcp_connection = nil
      if mcp_connection_id.present?
        mcp_connection = entity.mcp_connections.find_by(id: mcp_connection_id)
        unless mcp_connection
          return error_response("MCP connection #{mcp_connection_id} not found")
        end
      end

      # Get git connection
      git_connection = if git_connection_id.present?
                        entity.mcp_connections.find_by(id: git_connection_id)
                      else
                        entity.mcp_connections.git_systems.active_connections.first
                      end

      unless git_connection
        return error_response("No active Git connection found. Please configure GitHub or Azure Repos first.")
      end

      # Create pipeline execution
      pipeline = entity.pipeline_executions.create!(
        ticket_id: ticket_id,
        ticket_system: ticket_system,
        ticket_title: ticket_title,
        ticket_description: ticket_description || ticket_title,
        ticket_url: mcp_connection ? "#{mcp_connection.config['base_url']}/browse/#{ticket_id}" : nil,
        priority: priority,
        status: :new,
        mcp_connection: mcp_connection,
        git_connection: git_connection
      )

      # Queue processing job
      ProcessPipelineJob.perform_later(pipeline.id)

      stream_progress("Pipeline #{pipeline.id} created and queued for processing")

      success_response(
        {
          pipeline_id: pipeline.id,
          ticket_id: pipeline.ticket_id,
          ticket_title: pipeline.ticket_title,
          status: pipeline.status,
          priority: pipeline.priority,
          created_at: pipeline.created_at.iso8601,
          admin_url: admin_pipeline_url(pipeline)
        },
        "✅ Pipeline created successfully! Starting #{pipeline.ticket_id} - #{pipeline.ticket_title}"
      )
    end

    def list_pipelines(args)
      status_filter = get_arg(args, :status_filter)
      limit = [get_arg(args, :limit, 10).to_i, 50].min

      pipelines = entity.pipeline_executions.order(created_at: :desc)

      if status_filter.present?
        pipelines = pipelines.where(status: status_filter)
      end

      pipelines = pipelines.limit(limit)

      pipeline_list = pipelines.map do |p|
        {
          id: p.id,
          ticket_id: p.ticket_id,
          ticket_title: p.ticket_title,
          status: p.status,
          status_label: p.status.titleize,
          priority: p.priority,
          created_at: p.created_at.iso8601,
          started_at: p.started_at&.iso8601,
          completed_at: p.completed_at&.iso8601,
          duration: p.duration_human,
          has_interactions: p.pipeline_interactions.pending.any?,
          admin_url: admin_pipeline_url(p)
        }
      end

      summary = "📋 Found #{pipeline_list.length} pipeline#{'s' unless pipeline_list.length == 1}"
      summary += " with status '#{status_filter}'" if status_filter.present?

      success_response(
        {
          pipelines: pipeline_list,
          count: pipeline_list.length,
          total: entity.pipeline_executions.count
        },
        summary
      )
    end

    def show_pipeline(args)
      pipeline_id = get_arg(args, :pipeline_id)

      unless pipeline_id.present?
        return error_response("pipeline_id is required for show action")
      end

      pipeline = entity.pipeline_executions.find_by(id: pipeline_id)

      unless pipeline
        return error_response("Pipeline #{pipeline_id} not found")
      end

      # Get latest events
      recent_events = pipeline.pipeline_events.order(created_at: :desc).limit(5).map do |event|
        {
          type: event.event_type,
          source: event.source,
          created_at: event.created_at.iso8601,
          metadata: event.metadata
        }
      end

      # Get agent executions
      agents = pipeline.agent_executions.order(created_at: :desc).map do |ae|
        {
          agent: ae.agent_id,
          status: ae.status,
          started_at: ae.started_at&.iso8601,
          completed_at: ae.completed_at&.iso8601,
          duration: ae.duration_human,
          tokens_used: ae.tokens_used,
          cost: ae.cost
        }
      end

      # Get pending interactions
      interactions = pipeline.pipeline_interactions.pending.map do |i|
        {
          id: i.id,
          type: i.interaction_type,
          message: i.question,
          priority: i.priority,
          asked_at: i.asked_at.iso8601,
          timeout_at: i.timeout_at&.iso8601
        }
      end

      # Get artifacts
      artifacts = pipeline.pipeline_artifacts.recent.limit(10).map do |a|
        {
          type: a.artifact_type,
          file_name: a.file_name,
          file_size: a.file_size_human,
          created_at: a.created_at.iso8601
        }
      end

      success_response(
        {
          pipeline: {
            id: pipeline.id,
            ticket_id: pipeline.ticket_id,
            ticket_title: pipeline.ticket_title,
            ticket_description: pipeline.ticket_description,
            ticket_url: pipeline.ticket_url,
            status: pipeline.status,
            priority: pipeline.priority,
            created_at: pipeline.created_at.iso8601,
            started_at: pipeline.started_at&.iso8601,
            completed_at: pipeline.completed_at&.iso8601,
            duration: pipeline.duration_human,
            pr_url: pipeline.pr_url,
            admin_url: admin_pipeline_url(pipeline)
          },
          agents: agents,
          recent_events: recent_events,
          pending_interactions: interactions,
          recent_artifacts: artifacts,
          stats: {
            total_cost: "$#{pipeline.total_cost.round(4)}",
            total_tokens: pipeline.total_tokens_used,
            agent_count: agents.length,
            event_count: pipeline.pipeline_events.count,
            artifact_count: pipeline.pipeline_artifacts.count
          }
        },
        "📊 Pipeline #{pipeline.ticket_id} - #{pipeline.status.titleize}"
      )
    end

    def retry_pipeline(args)
      pipeline_id = get_arg(args, :pipeline_id)

      unless pipeline_id.present?
        return error_response("pipeline_id is required for retry action")
      end

      pipeline = entity.pipeline_executions.find_by(id: pipeline_id)

      unless pipeline
        return error_response("Pipeline #{pipeline_id} not found")
      end

      unless ['failed', 'rolled_back'].include?(pipeline.status)
        return error_response("Can only retry failed or rolled back pipelines. Current status: #{pipeline.status}")
      end

      # Transition back to new state
      pipeline.update!(
        status: :new,
        started_at: nil,
        completed_at: nil
      )

      # Create retry event
      pipeline.create_event!(
        event_type: 'pipeline.retry',
        source: 'user',
        metadata: { user_id: user.id }
      )

      # Queue processing
      ProcessPipelineJob.perform_later(pipeline.id)

      stream_progress("Pipeline #{pipeline.id} queued for retry")

      success_response(
        {
          pipeline_id: pipeline.id,
          status: pipeline.status,
          admin_url: admin_pipeline_url(pipeline)
        },
        "🔄 Pipeline #{pipeline.ticket_id} queued for retry"
      )
    end

    def cancel_pipeline(args)
      pipeline_id = get_arg(args, :pipeline_id)

      unless pipeline_id.present?
        return error_response("pipeline_id is required for cancel action")
      end

      pipeline = entity.pipeline_executions.find_by(id: pipeline_id)

      unless pipeline
        return error_response("Pipeline #{pipeline_id} not found")
      end

      if pipeline.terminal_state?
        return error_response("Pipeline is already in terminal state: #{pipeline.status}")
      end

      # Mark as failed with cancellation reason
      pipeline.fail!("Cancelled by user #{user.email}")

      # Create cancellation event
      pipeline.create_event!(
        event_type: 'pipeline.cancelled',
        source: 'user',
        metadata: { user_id: user.id, reason: 'User requested cancellation' }
      )

      success_response(
        {
          pipeline_id: pipeline.id,
          status: pipeline.status,
          admin_url: admin_pipeline_url(pipeline)
        },
        "🛑 Pipeline #{pipeline.ticket_id} cancelled"
      )
    end

    def approve_interaction(args)
      pipeline_id = get_arg(args, :pipeline_id)
      interaction_id = get_arg(args, :interaction_id)

      unless pipeline_id.present?
        return error_response("pipeline_id is required for approve action")
      end

      pipeline = entity.pipeline_executions.find_by(id: pipeline_id)
      unless pipeline
        return error_response("Pipeline #{pipeline_id} not found")
      end

      # Find interaction
      interaction = if interaction_id.present?
                     pipeline.pipeline_interactions.find_by(id: interaction_id)
                   else
                     pipeline.pipeline_interactions.pending.where(interaction_type: 'approval').order(asked_at: :desc).first
                   end

      unless interaction
        return error_response("No pending approval found for pipeline #{pipeline_id}")
      end

      # Answer with approval
      interaction.answer!(user, "Approved")

      success_response(
        {
          pipeline_id: pipeline.id,
          interaction_id: interaction.id,
          status: pipeline.status,
          admin_url: admin_pipeline_url(pipeline)
        },
        "✅ Approval granted for pipeline #{pipeline.ticket_id}"
      )
    end

    def reject_interaction(args)
      pipeline_id = get_arg(args, :pipeline_id)
      interaction_id = get_arg(args, :interaction_id)
      response_text = get_arg(args, :response, "Rejected")

      unless pipeline_id.present?
        return error_response("pipeline_id is required for reject action")
      end

      pipeline = entity.pipeline_executions.find_by(id: pipeline_id)
      unless pipeline
        return error_response("Pipeline #{pipeline_id} not found")
      end

      # Find interaction
      interaction = if interaction_id.present?
                     pipeline.pipeline_interactions.find_by(id: interaction_id)
                   else
                     pipeline.pipeline_interactions.pending.where(interaction_type: 'approval').order(asked_at: :desc).first
                   end

      unless interaction
        return error_response("No pending approval found for pipeline #{pipeline_id}")
      end

      # Answer with rejection
      interaction.answer!(user, response_text)

      success_response(
        {
          pipeline_id: pipeline.id,
          interaction_id: interaction.id,
          status: pipeline.status,
          admin_url: admin_pipeline_url(pipeline)
        },
        "❌ Pipeline #{pipeline.ticket_id} rejected"
      )
    end

    def answer_clarification(args)
      pipeline_id = get_arg(args, :pipeline_id)
      interaction_id = get_arg(args, :interaction_id)
      response_text = get_arg(args, :response)

      unless pipeline_id.present?
        return error_response("pipeline_id is required for answer action")
      end

      unless response_text.present?
        return error_response("response is required for answer action")
      end

      pipeline = entity.pipeline_executions.find_by(id: pipeline_id)
      unless pipeline
        return error_response("Pipeline #{pipeline_id} not found")
      end

      # Find interaction
      interaction = if interaction_id.present?
                     pipeline.pipeline_interactions.find_by(id: interaction_id)
                   else
                     pipeline.pipeline_interactions.pending.where(interaction_type: 'clarification').order(asked_at: :desc).first
                   end

      unless interaction
        return error_response("No pending clarification found for pipeline #{pipeline_id}")
      end

      # Answer clarification
      interaction.answer!(user, response_text)

      stream_progress("Clarification answered, pipeline resuming")

      success_response(
        {
          pipeline_id: pipeline.id,
          interaction_id: interaction.id,
          status: pipeline.status,
          admin_url: admin_pipeline_url(pipeline)
        },
        "✅ Clarification answered for pipeline #{pipeline.ticket_id}"
      )
    end

    def admin_pipeline_url(pipeline)
      host = ENV['APP_HOST'] || 'http://localhost:3000'
      "#{host}/admin/pipeline/executions/#{pipeline.id}"
    end
  end
end
