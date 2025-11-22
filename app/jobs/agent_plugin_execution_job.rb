class AgentPluginExecutionJob < ApplicationJob
  queue_as :agents

  def perform(execution_id, task_description, context_data = {})
    execution = AgentPluginExecution.find(execution_id)
    agent_plugin = execution.agent_plugin
    user = execution.user

    Rails.logger.info "🤖 Executing AgentPlugin: #{agent_plugin.name} (ID: #{agent_plugin.id})"
    Rails.logger.info "   Task: #{task_description.truncate(100)}"

    begin
      # Instantiate the agent with full context
      agent = agent_plugin.instantiate(
        entity: context_data[:entity] || user.entity,
        user: user,
        session_id: context_data[:session_id],
        execution: execution,
        config: context_data[:additional_context] || {}
      )

      # Execute the agent with the task
      result = agent.run(task_description, context_data)

      # Mark execution as completed with the result
      execution.mark_completed!(
        output: result,
        result_data: {
          task: task_description,
          completed_at: Time.current
        }
      )

      # Broadcast completion to Scout if we have a session
      if context_data[:session_id]
        broadcast_completion(context_data[:session_id], agent_plugin, execution, result)
      end

      Rails.logger.info "✅ AgentPlugin #{agent_plugin.name} completed successfully"

    rescue => e
      Rails.logger.error "AgentPlugin execution failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      execution.mark_failed!(e.message)

      # Broadcast failure to Scout if we have a session
      if context_data[:session_id]
        broadcast_failure(context_data[:session_id], agent_plugin, execution, e)
      end

      raise
    end
  end

  private

  def broadcast_completion(session_id, agent_plugin, execution, result)
    ScoutChannel.broadcast_to(session_id, {
      type: 'agent_plugin_completed',
      execution_id: execution.id,
      agent_name: agent_plugin.name,
      result: result.is_a?(String) ? result : result.to_s,
      duration_ms: execution.duration_ms,
      tokens_used: execution.tokens_used
    })

    # Also broadcast task progress update
    ScoutChannel.broadcast_to(session_id, {
      type: 'task_progress',
      job_id: execution.id,
      status: 'completed',
      agent_type: agent_plugin.slug,
      message: "✅ #{agent_plugin.name} completed",
      result: result.is_a?(String) ? result.truncate(200) : result.to_s.truncate(200)
    })

    # Check for auto-load canvas on completion
    if agent_plugin.canvas_on_completion.present?
      Rails.logger.info "🎨 Auto-loading canvas: #{agent_plugin.canvas_on_completion}"
      ScoutChannel.broadcast_to(session_id, {
        type: 'load_canvas',
        canvas_name: agent_plugin.canvas_on_completion,
        canvas_data: { 
          execution_id: execution.id,
          result: result
        }
      })
    end
  end

  def broadcast_failure(session_id, agent_plugin, execution, error)
    ScoutChannel.broadcast_to(session_id, {
      type: 'agent_plugin_failed',
      execution_id: execution.id,
      agent_name: agent_plugin.name,
      error: error.message
    })

    # Also broadcast task progress update
    ScoutChannel.broadcast_to(session_id, {
      type: 'task_progress',
      job_id: execution.id,
      status: 'failed',
      agent_type: agent_plugin.slug,
      message: "❌ #{agent_plugin.name} failed: #{error.message}"
    })
  end
end
