module Agents
  class PlannerAgent < BaseAgent
    def execute!
      log("Starting implementation planning...")

      inputs = agent_execution.inputs
      ticket_info = {
        title: inputs['ticket_title'],
        description: inputs['ticket_description'],
        clarifications: inputs['clarifications']
      }

      system_prompt = "You are an expert software architect creating implementation plans. Generate a detailed plan with steps, acceptance tests, and architecture diagrams in markdown format."

      user_message = <<~MSG
        Create an implementation plan for:
        Title: #{ticket_info[:title]}
        Description: #{ticket_info[:description]}

        Include:
        1. Implementation steps
        2. Acceptance tests
        3. Technical considerations
        4. Files to modify/create
      MSG

      result = call_claude(system_prompt, user_message, model: 'claude-sonnet-4-5', max_tokens: 8000, temperature: 0.5)

      if result[:success]
        plan_content = result[:content]
        save_artifact('plan', 'plan.md', plan_content)
        agent_execution.complete!(plan: plan_content)
        log("Plan created successfully")
      else
        raise "Planning failed: #{result[:error]}"
      end
    end
  end
end
