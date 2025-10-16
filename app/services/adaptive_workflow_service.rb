class AdaptiveWorkflowService
  def initialize(user, entity, session_id)
    @user = user
    @entity = entity
    @session_id = session_id
    @ai_service = BedrockService.new(user: user, entity: entity)
    @tool_catalog = Tools::ToolCatalog.instance
  end

  def execute_with_flexibility(workflow_plan, progress_callback = nil)
    @progress_callback = progress_callback

    # Start with the original plan
    current_plan = workflow_plan
    attempt = 1
    max_attempts = 3

    while attempt <= max_attempts
      @progress_callback&.call("🎯 Attempt #{attempt}: Executing workflow plan...")

      result = execute_plan_flexibly(current_plan, attempt)

      case result[:status]
      when "completed"
        @progress_callback&.call("🎉 Workflow completed successfully!")
        return result
      when "failed"
        if attempt < max_attempts
          @progress_callback&.call("⚠️ Plan failed, asking AI to adapt the approach...")

          # Ask AI to create an adaptive plan based on the failure
          current_plan = create_adaptive_plan(current_plan, result[:error], result[:completed_steps])

          if current_plan
            @progress_callback&.call("🔄 AI created an adaptive plan, trying again...")
            attempt += 1
          else
            @progress_callback&.call("❌ Could not create adaptive plan, workflow failed.")
            return result
          end
        else
          @progress_callback&.call("❌ Workflow failed after #{max_attempts} attempts.")
          return result
        end
      when "partial"
        @progress_callback&.call("✅ Workflow partially completed, asking AI to finish remaining steps...")

        # Ask AI to complete remaining steps
        completion_plan = create_completion_plan(current_plan, result[:completed_steps], result[:remaining_steps])

        if completion_plan
          current_plan = completion_plan
          attempt += 1
        else
          return result
        end
      end
    end

    {
      status: "failed",
      error: "Maximum attempts reached",
      message: "Workflow could not be completed after multiple adaptive attempts."
    }
  end

  private

  def execute_plan_flexibly(plan, attempt)
    @progress_callback&.call("📋 Executing #{plan[:steps]&.length || 0} steps...")

    completed_steps = []
    failed_steps = []

    plan[:steps]&.each do |step|
      @progress_callback&.call("🔧 Starting: #{step[:name] || step['name']}")

      result = execute_step_with_retry(step)

      if result[:success]
        completed_steps << step
        @progress_callback&.call("✅ Completed: #{step[:name] || step['name']}")
      else
        failed_steps << { step: step, error: result[:error] }
        @progress_callback&.call("❌ Failed: #{step[:name] || step['name']} - #{result[:error]}")

        # Try to recover with AI assistance
        recovery_result = attempt_step_recovery(step, result[:error])

        if recovery_result[:success]
          completed_steps << step
          @progress_callback&.call("🔄 Recovered: #{step[:name] || step['name']}")
        else
          # Step failed, return partial result
          return {
            status: "failed",
            completed_steps: completed_steps,
            failed_step: step,
            error: result[:error],
            message: "Workflow failed at step: #{step[:name] || step['name']}"
          }
        end
      end
    end

    {
      status: "completed",
      completed_steps: completed_steps,
      message: "All steps completed successfully"
    }
  end

  def execute_step_with_retry(step)
    tool_name = step[:config][:tool] || step["config"]["tool"]
    tool_args = step[:config][:tool_args] || step["config"]["tool_args"] || {}

    begin
      result = @tool_catalog.execute_tool(
        tool_name,
        tool_args,
        user: @user,
        entity: @entity
      )

      @progress_callback&.call("🔧 Tool result: #{result[:success] ? 'Success' : 'Failed'}")

      result
    rescue => e
      Rails.logger.error "Step execution error: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end
  end

  def attempt_step_recovery(step, error)
    @progress_callback&.call("🤔 AI analyzing failure and attempting recovery...")

    # Ask AI to suggest a fix for the failed step
    recovery_prompt = build_recovery_prompt(step, error)

    begin
      response = @ai_service.complete(
        messages: [
          { role: "system", content: "You are an expert at fixing workflow step failures." },
          { role: "user", content: recovery_prompt }
        ],
        max_tokens: 4000,
        temperature: 0.3
      )

      # Try to extract a corrected step configuration
      if response.include?("CORRECTED_STEP")
        json_match = response.match(/CORRECTED_STEP:\s*(\{.*?\})/m)
        if json_match
          corrected_config = JSON.parse(json_match[1])

          @progress_callback&.call("🔧 AI suggested a fix, trying corrected approach...")

          # Execute with corrected configuration
          return execute_step_with_retry(step.merge(config: corrected_config))
        end
      end

      {
        success: false,
        error: "Could not recover from step failure"
      }
    rescue => e
      Rails.logger.error "Recovery attempt failed: #{e.message}"
      {
        success: false,
        error: "Recovery failed: #{e.message}"
      }
    end
  end

  def create_adaptive_plan(original_plan, error, completed_steps)
    @progress_callback&.call("🧠 AI creating adaptive plan...")

    adaptation_prompt = build_adaptation_prompt(original_plan, error, completed_steps)

    begin
      response = @ai_service.complete(
        messages: [
          { role: "system", content: "You are an expert workflow planner who can adapt plans when they fail." },
          { role: "user", content: adaptation_prompt }
        ],
        max_tokens: 8000,
        temperature: 0.5
      )

      # Extract JSON plan from response
      json_match = response.match(/\{.*\}/m)
      if json_match
        JSON.parse(json_match[0], symbolize_names: true)
      else
        nil
      end
    rescue => e
      Rails.logger.error "Adaptive planning failed: #{e.message}"
      nil
    end
  end

  def create_completion_plan(original_plan, completed_steps, remaining_steps)
    @progress_callback&.call("🎯 AI creating completion plan for remaining steps...")

    # Similar to adaptive plan but focused on completing remaining work
    completion_prompt = build_completion_prompt(original_plan, completed_steps, remaining_steps)

    begin
      response = @ai_service.complete(
        messages: [
          { role: "system", content: "You are an expert at completing partially finished workflows." },
          { role: "user", content: completion_prompt }
        ],
        max_tokens: 8000,
        temperature: 0.5
      )

      # Extract JSON plan from response
      json_match = response.match(/\{.*\}/m)
      if json_match
        JSON.parse(json_match[0], symbolize_names: true)
      else
        nil
      end
    rescue => e
      Rails.logger.error "Completion planning failed: #{e.message}"
      nil
    end
  end

  def build_recovery_prompt(step, error)
    <<~PROMPT
      A workflow step failed and needs to be corrected:

      FAILED STEP:
      #{step.to_json}

      ERROR:
      #{error}

      Please analyze the error and provide a corrected step configuration.

      Available tools: #{@tool_catalog.tools.keys.join(', ')}

      If you can fix it, respond with:
      CORRECTED_STEP: {corrected step configuration in JSON}

      If you can't fix it, respond with:
      CANNOT_RECOVER: {explanation}
    PROMPT
  end

  def build_adaptation_prompt(original_plan, error, completed_steps)
    <<~PROMPT
      A workflow plan failed and needs to be adapted:

      ORIGINAL PLAN:
      #{original_plan.to_json}

      FAILURE ERROR:
      #{error}

      COMPLETED STEPS:
      #{completed_steps.map { |s| s[:name] || s['name'] }.join(', ')}

      Please create an alternative approach that:
      1. Builds on the completed steps
      2. Avoids the error that caused the failure
      3. Still achieves the original goal

      Available tools: #{@tool_catalog.tools.keys.join(', ')}

      Return a complete workflow plan in JSON format:
      {
        "name": "Adaptive Plan",
        "description": "Alternative approach",
        "steps": [...]
      }
    PROMPT
  end

  def build_completion_prompt(original_plan, completed_steps, remaining_steps)
    <<~PROMPT
      A workflow was partially completed and needs finishing:

      ORIGINAL PLAN:
      #{original_plan.to_json}

      COMPLETED STEPS:
      #{completed_steps.map { |s| s[:name] || s['name'] }.join(', ')}

      REMAINING WORK:
      #{remaining_steps.map { |s| s[:name] || s['name'] }.join(', ')}

      Please create a plan to complete the remaining work, taking into account:
      1. What has already been accomplished
      2. Any data/results from completed steps
      3. The most efficient way to finish

      Available tools: #{@tool_catalog.tools.keys.join(', ')}

      Return a workflow plan in JSON format focusing on the remaining steps.
    PROMPT
  end
end
