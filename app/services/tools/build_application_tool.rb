# frozen_string_literal: true

module Tools
  # BuildApplicationTool executes an approved ApplicationPlan
  # and creates all the components in the AMOS ecosystem.
  #
  # This tool:
  # 1. Approves the plan (if pending)
  # 2. Executes the build via ApplicationBuildService
  # 3. Streams progress updates
  # 4. Returns the complete results
  #
  class BuildApplicationTool < BaseTool
    def self.metadata
      {
        name: 'build_application',
        description: 'Build an application from an approved plan. Use this when the user says ' \
                     '"build it", "looks good", "go ahead", or otherwise approves the plan. ' \
                     'This creates all modules, the AI agent, tools, integrations, workflows, and scheduled tasks.',
        category: 'platform_factory',
        input_schema: {
          type: 'object',
          properties: {
            plan_id: {
              type: 'integer',
              description: 'ID of the plan to build (optional - uses the most recent pending plan if omitted)'
            },
            confirm: {
              type: 'boolean',
              description: 'Confirm the build (should be true when user approves)'
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      # Find the plan
      plan = find_plan(args)
      return plan if plan.is_a?(Hash) # Error response
      
      # Validate plan state
      unless plan.pending_approval? || plan.approved?
        return {
          success: false,
          error: "This plan is in '#{plan.status}' state and cannot be built",
          hint: plan.completed? ? "This application was already built!" : "Use plan_application to update the plan first"
        }
      end
      
      # Approve if pending
      plan.approve! if plan.pending_approval?
      
      # Stream progress if we have a session
      progress_callback = build_progress_callback
      
      # Execute the build
      stream_progress("🚀 Starting build for '#{plan.name}'...")
      
      service = ApplicationBuildService.new(plan, progress_callback: progress_callback)
      result = service.execute!
      
      if result[:success]
        build_success_response(plan.reload, result[:results])
      else
        build_failure_response(plan.reload, result[:error])
      end
    end
    
    private
    
    def find_plan(args)
      plan_id = get_arg(args, :plan_id)
      
      if plan_id
        plan = ApplicationPlan.find_by(id: plan_id, entity_id: @entity.id)
        return { success: false, error: "Plan not found" } unless plan
        plan
      else
        # Find the most recent plan that's ready to build
        plan = ApplicationPlan
          .where(entity_id: @entity.id, created_by_id: @user.id)
          .where(status: %w[pending_approval approved])
          .order(created_at: :desc)
          .first
        
        if plan.nil?
          return {
            success: false,
            error: "No plan found to build",
            hint: "First, tell me what you want to build (e.g., 'I need a knowledge base')"
          }
        end
        
        plan
      end
    end
    
    def build_progress_callback
      session_id = @context[:session_id] if @context
      return nil unless session_id
      
      ->(message) {
        stream_progress(message)
      }
    end
    
    def stream_progress(message)
      session_id = @context[:session_id] if @context
      return unless session_id
      
      ActionCable.server.broadcast(
        "scout_channel_#{session_id}",
        {
          type: 'build_progress',
          message: message,
          timestamp: Time.current.iso8601
        }
      )
    end
    
    def build_success_response(plan, results)
      # Get the primary module for canvas loading
      primary_module = results[:modules]&.first
      canvas_slug = primary_module ? "module_#{primary_module[:slug]}_list" : nil
      
      # Broadcast canvas load to show the new module
      if canvas_slug
        session_id = @context[:session_id] if @context
        if session_id
          ActionCable.server.broadcast(
            "scout_channel_#{session_id}",
            {
              type: 'canvas_load',
              canvas_type: canvas_slug,
              canvas_title: primary_module[:name],
              canvas_data: {}
            }
          )
        end
      end
      
      # Build the response
      built_items = []
      built_items << "📦 #{results[:modules].count} module(s) created" if results[:modules].any?
      built_items << "🤖 #{results[:agent][:name]}" if results[:agent]
      built_items << "🔧 #{results[:tools].count} tools registered" if results[:tools].any?
      built_items << "🔌 #{results[:integrations].count} integration(s) wired" if results[:integrations].any?
      built_items << "⚡ #{results[:workflows].count} workflow(s) created" if results[:workflows].any?
      built_items << "📅 #{results[:scheduled_tasks].count} scheduled task(s)" if results[:scheduled_tasks].any?
      built_items << "🌐 Website created (draft)" if results[:website]
      
      {
        success: true,
        message: "🎉 Your '#{plan.name}' is live!",
        built: built_items,
        results: {
          plan_id: plan.id,
          plan_name: plan.name,
          modules: results[:modules],
          agent: results[:agent],
          tools_count: results[:tools].count,
          integrations_count: results[:integrations].count,
          workflows_count: results[:workflows].count,
          scheduled_tasks_count: results[:scheduled_tasks].count,
          website: results[:website]
        },
        canvas_loaded: canvas_slug,
        ecosystem_powers: build_ecosystem_powers(plan, results),
        next_steps: build_next_steps(plan, results)
      }
    end
    
    def build_failure_response(plan, error)
      {
        success: false,
        message: "❌ Build failed for '#{plan.name}'",
        error: error,
        plan_id: plan.id,
        status: plan.status,
        hint: "You can try again by saying 'retry the build' or modify the plan first"
      }
    end
    
    def build_ecosystem_powers(plan, results)
      powers = []
      
      if results[:agent]
        powers << "🤖 Talk to '#{results[:agent][:name]}' for expert help with your #{plan.name.downcase}"
      end
      
      if results[:modules].any?
        module_name = results[:modules].first[:name]
        powers << "📊 Other agents can now access your #{module_name.downcase} data"
        powers << "🔗 Include #{module_name.downcase} in workflows and automations"
      end
      
      if results[:tools].any?
        powers << "🔧 #{results[:tools].count} new tools available for all agents to use"
      end
      
      if results[:integrations].any?
        powers << "🔌 Data will sync automatically with connected integrations"
      end
      
      if results[:workflows].any?
        powers << "⚡ #{results[:workflows].count} workflows running automatically"
      end
      
      if results[:scheduled_tasks].any?
        powers << "📅 Background tasks keeping everything in sync"
      end
      
      powers << "📥 Export data anytime as CSV, PDF, or Excel"
      
      powers
    end
    
    def build_next_steps(plan, results)
      steps = []
      
      if results[:modules].any?
        module_name = results[:modules].first[:name]
        steps << "Say 'add a new #{module_name.singularize.downcase}' to create your first record"
      end
      
      if results[:integrations].any?
        pending = results[:integrations].select { |i| i[:status] != 'connected' }
        if pending.any?
          steps << "Connect #{pending.first[:integration_name]} in Settings → Integrations"
        end
      end
      
      if results[:agent]
        steps << "Ask '#{results[:agent][:name]}' anything about your #{plan.name.downcase}"
      end
      
      if results[:website]
        steps << "Preview your website at #{results[:website][:slug]}"
      end
      
      steps << "Say 'customize' to add more features"
      
      steps
    end
  end
end

