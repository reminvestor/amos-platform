class AgentExecutionJob < ApplicationJob
  queue_as :agents

  def perform(agent_execution_id)
    agent_execution = AgentExecution.find(agent_execution_id)

    Rails.logger.info "🤖 Executing agent: #{agent_execution.agent_id}"

    # Start execution
    agent_execution.start!

    # Get appropriate agent class
    agent_class = case agent_execution.agent_id
                 when 'clarifier'
                   AiAgents::Pipeline::ClarifierAgent
                 when 'planner'
                   AiAgents::Pipeline::PlannerAgent
                 when 'coder'
                   AiAgents::Pipeline::CoderAgent
                 when 'reviewer'
                   AiAgents::Pipeline::ReviewerAgent
                 when 'cua_pack'
                   AiAgents::Pipeline::CuaPackAgent
                 when 'release_manager'
                   AiAgents::Pipeline::ReleaseManagerAgent
                 else
                   raise "Unknown agent: #{agent_execution.agent_id}"
                 end

    # Execute agent
    agent = agent_class.new(agent_execution)
    agent.execute!

    Rails.logger.info "✅ Agent #{agent_execution.agent_id} completed successfully"

    # Trigger next pipeline step
    ProcessPipelineJob.perform_later(agent_execution.pipeline_execution_id)
  rescue => e
    Rails.logger.error "Agent execution failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    agent_execution.fail!(e.message)
    raise
  end
end
