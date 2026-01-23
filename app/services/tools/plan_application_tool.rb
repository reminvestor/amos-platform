# frozen_string_literal: true

module Tools
  # PlanApplicationTool handles the collaborative planning process
  # for building applications within the AMOS ecosystem.
  #
  # This tool:
  # 1. Creates a new ApplicationPlan or retrieves an existing draft
  # 2. Uses archetype intelligence to suggest components
  # 3. Shows a plan preview to the user
  # 4. Handles refinement requests
  # 5. Submits for approval when ready
  #
  class PlanApplicationTool < BaseTool
    def self.metadata
      {
        name: 'plan_application',
        description: 'Create or refine an application plan. Use this when a user wants to build ' \
                     'a new application, module, knowledge base, CRM, or any custom system. ' \
                     'The plan includes all components: modules, agent, tools, integrations, workflows, and scheduled tasks.',
        category: 'platform_factory',
        input_schema: {
          type: 'object',
          properties: {
            # For creating a new plan
            name: {
              type: 'string',
              description: 'Name of the application to build (e.g., "Knowledge Base", "Sales CRM")'
            },
            description: {
              type: 'string',
              description: 'Description of what the application should do'
            },
            # For working with existing plans
            plan_id: {
              type: 'integer',
              description: 'ID of an existing plan to refine (optional - omit to find active or create new)'
            },
            # For refinement
            action: {
              type: 'string',
              enum: %w[create refine submit_for_approval show],
              description: "Action: 'create' new plan, 'refine' existing, 'submit_for_approval', or 'show' current plan"
            },
            refinements: {
              type: 'object',
              description: 'Changes to make to the plan (for refine action)',
              properties: {
                add_module: { type: 'object', description: 'Module to add' },
                add_integration: { type: 'object', description: 'Integration to add' },
                add_workflow: { type: 'object', description: 'Workflow to add' },
                add_scheduled_task: { type: 'object', description: 'Scheduled task to add' },
                add_website: { type: 'boolean', description: 'Add a public-facing website' },
                add_website_feature: { type: 'string', description: 'Feature to add to website' },
                update_agent: { type: 'object', description: 'Changes to agent spec' }
              }
            },
            # Requirements for initial plan
            requirements: {
              type: 'object',
              description: 'Specific requirements for the plan',
              properties: {
                public_website: { type: 'boolean', description: 'Include a public-facing website' },
                integrations: { type: 'array', items: { type: 'object' }, description: 'Required integrations' },
                workflows: { type: 'array', items: { type: 'object' }, description: 'Required workflows' },
                additional_fields: { type: 'array', items: { type: 'object' }, description: 'Additional fields for the module' }
              }
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      action = get_arg(args, :action) || determine_action(args)
      
      case action
      when 'create'
        create_plan(args)
      when 'refine'
        refine_plan(args)
      when 'submit_for_approval'
        submit_for_approval(args)
      when 'show'
        show_plan(args)
      else
        { success: false, error: "Unknown action: #{action}" }
      end
    end
    
    private
    
    def determine_action(args)
      # If name is provided and no plan_id, we're creating
      return 'create' if get_arg(args, :name).present? && get_arg(args, :plan_id).blank?
      
      # If refinements are provided, we're refining
      return 'refine' if get_arg(args, :refinements).present?
      
      # Default to show
      'show'
    end
    
    # ============================================
    # CREATE
    # ============================================
    
    def create_plan(args)
      name = get_arg(args, :name)
      
      unless name.present?
        return {
          success: false,
          error: "Please provide a name for the application you want to build",
          hint: "Example: 'Knowledge Base', 'Sales CRM', 'Inventory Manager'"
        }
      end
      
      description = get_arg(args, :description)
      requirements = get_arg(args, :requirements) || {}
      
      # Check for existing active plan
      existing = ApplicationPlan.active.for_entity(@entity.id).for_user(@user.id).first
      if existing && existing.name.downcase == name.downcase
        return show_plan_response(existing, message: "You already have a plan in progress for '#{name}'")
      end
      
      # Create the plan
      planner = ApplicationPlannerService.new(entity: @entity, user: @user)
      plan = planner.create_plan(
        name: name,
        description: description,
        requirements: requirements.deep_symbolize_keys
      )
      
      # Submit for approval automatically (user will review)
      plan.submit_for_approval!
      
      # Broadcast the plan preview to the canvas
      broadcast_plan_preview(plan)
      
      {
        success: true,
        message: "📋 I've created a plan for '#{name}'",
        plan_id: plan.id,
        plan_name: plan.name,
        archetype: plan.archetype,
        summary: plan.component_summary,
        estimated_time: plan.estimated_build_time,
        status: plan.status,
        canvas_loaded: true,
        next_action: 'review_plan',
        prompt_for_user: build_review_prompt(plan)
      }
    end
    
    # ============================================
    # REFINE
    # ============================================
    
    def refine_plan(args)
      plan = find_plan(args)
      return plan if plan.is_a?(Hash) # Error response
      
      unless plan.editable?
        return { success: false, error: "This plan cannot be edited (status: #{plan.status})" }
      end
      
      refinements = get_arg(args, :refinements) || {}
      
      if refinements.empty?
        return {
          success: false,
          error: "Please specify what changes you want to make",
          hint: "Examples: add a website, add an integration, add a workflow"
        }
      end
      
      # Reset to drafting if it was pending approval
      plan.update!(status: 'drafting') if plan.pending_approval?
      
      # Apply refinements
      planner = ApplicationPlannerService.new(entity: @entity, user: @user)
      plan = planner.refine_plan(plan, refinements.deep_symbolize_keys)
      
      # Submit for approval again
      plan.submit_for_approval!
      
      # Broadcast updated preview
      broadcast_plan_preview(plan)
      
      {
        success: true,
        message: "✏️ Plan updated",
        plan_id: plan.id,
        summary: plan.component_summary,
        changes_applied: refinements.keys.map(&:to_s),
        canvas_loaded: true,
        prompt_for_user: "I've updated the plan. Take another look and let me know if you want more changes, or say **'build it'** to start building."
      }
    end
    
    # ============================================
    # SUBMIT FOR APPROVAL
    # ============================================
    
    def submit_for_approval(args)
      plan = find_plan(args)
      return plan if plan.is_a?(Hash) # Error response
      
      if plan.pending_approval? || plan.approved?
        return show_plan_response(plan, message: "This plan is already ready for approval")
      end
      
      plan.submit_for_approval!
      broadcast_plan_preview(plan)
      
      {
        success: true,
        message: "📋 Plan submitted for your review",
        plan_id: plan.id,
        status: plan.status,
        canvas_loaded: true,
        prompt_for_user: build_review_prompt(plan)
      }
    end
    
    # ============================================
    # SHOW
    # ============================================
    
    def show_plan(args)
      plan = find_plan(args)
      return plan if plan.is_a?(Hash) # Error response
      
      broadcast_plan_preview(plan)
      show_plan_response(plan)
    end
    
    def show_plan_response(plan, message: nil)
      {
        success: true,
        message: message || "📋 Here's your plan for '#{plan.name}'",
        plan: plan.to_preview,
        canvas_loaded: true,
        prompt_for_user: case plan.status
        when 'pending_approval'
          build_review_prompt(plan)
        when 'approved'
          "This plan is approved. Say **'build it'** to start building."
        when 'completed'
          "This application has been built! You can start using it now."
        when 'failed'
          "This build failed: #{plan.error_message}. Would you like to retry?"
        else
          "What would you like to change about this plan?"
        end
      }
    end
    
    # ============================================
    # HELPERS
    # ============================================
    
    def find_plan(args)
      plan_id = get_arg(args, :plan_id)
      
      if plan_id
        plan = ApplicationPlan.find_by(id: plan_id, entity_id: @entity.id)
        return { success: false, error: "Plan not found" } unless plan
        plan
      else
        # Find the most recent active plan for this user
        plan = ApplicationPlan.active.for_entity(@entity.id).for_user(@user.id).recent.first
        
        if plan.nil?
          return {
            success: false,
            error: "No active plan found",
            hint: "Tell me what you want to build, like 'I need a knowledge base' or 'Build me a CRM'"
          }
        end
        
        plan
      end
    end
    
    def broadcast_plan_preview(plan)
      session_id = @context[:session_id] if @context
      return unless session_id
      
      ActionCable.server.broadcast(
        "scout_channel_#{session_id}",
        {
          type: 'canvas_load',
          canvas_type: 'application_plan_preview',
          canvas_title: "Plan: #{plan.name}",
          canvas_data: plan.to_preview
        }
      )
    end
    
    def build_review_prompt(plan)
      summary = plan.component_summary
      parts = []
      
      parts << "📦 **#{summary[:modules]} module(s)** to manage your data"
      parts << "🤖 **AI Expert Agent** to help you work with it" if summary[:has_agent]
      parts << "🔧 **#{summary[:tools]} tools** for automation"
      parts << "🔌 **#{summary[:integrations]} integration(s)** to connect external systems" if summary[:integrations] > 0
      parts << "⚡ **#{summary[:workflows]} workflow(s)** for automation" if summary[:workflows] > 0
      parts << "📅 **#{summary[:scheduled_tasks]} scheduled task(s)** for background work" if summary[:scheduled_tasks] > 0
      parts << "🌐 **Website** with #{summary[:website_pages]} page(s)" if summary[:website_pages] > 0
      
      <<~PROMPT
        **Plan Preview:**
        #{parts.join("\n")}
        
        Estimated build time: **#{plan.estimated_build_time}**
        
        ✅ Say **"build it"** or **"looks good"** to start building
        ✏️ Or tell me what you'd like to change
      PROMPT
    end
  end
end

