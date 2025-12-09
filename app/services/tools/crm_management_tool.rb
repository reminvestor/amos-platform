# frozen_string_literal: true

module Tools
  class CrmManagementTool < BaseTool
    def self.metadata
      {
        name: "crm_management",
        description: "Comprehensive CRM tool for managing opportunities, activities, contacts, and the sales pipeline. Use this for any CRM-related tasks including creating opportunities, logging activities (calls, notes, emails), assigning contacts/opportunities to users or AI agents, updating pipeline stages, and scheduling follow-ups.",
        category: "crm",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              description: "The CRM action to perform",
              enum: [
                "get_pipeline",
                "create_opportunity",
                "update_opportunity",
                "move_stage",
                "close_won",
                "close_lost",
                "assign_opportunity",
                "log_note",
                "log_call",
                "log_email",
                "create_task",
                "schedule_meeting",
                "complete_task",
                "assign_contact",
                "get_contact_timeline",
                "get_tasks",
                "update_lead_score",
                "promote_lifecycle",
                "schedule_follow_up"
              ]
            },
            contact_id: {
              type: "integer",
              description: "Contact ID for contact-related actions"
            },
            opportunity_id: {
              type: "integer",
              description: "Opportunity ID for opportunity-related actions"
            },
            activity_id: {
              type: "integer",
              description: "Activity ID for activity-related actions"
            },
            name: {
              type: "string",
              description: "Name for opportunity or subject for activities"
            },
            stage: {
              type: "string",
              description: "Pipeline stage: lead, qualified, proposal, negotiation, closed_won, closed_lost"
            },
            value: {
              type: "number",
              description: "Opportunity value/deal size"
            },
            description: {
              type: "string",
              description: "Description or notes content"
            },
            outcome: {
              type: "string",
              description: "Outcome for calls (connected, voicemail, no_answer) or meetings"
            },
            due_at: {
              type: "string",
              description: "Due date/time for tasks (ISO 8601 format)"
            },
            scheduled_at: {
              type: "string",
              description: "Scheduled date/time for meetings (ISO 8601 format)"
            },
            priority: {
              type: "string",
              description: "Priority level: low, normal, high, urgent"
            },
            assign_to_user_id: {
              type: "integer",
              description: "User ID to assign to"
            },
            assign_to_agent_id: {
              type: "integer",
              description: "Agent ID to assign to"
            },
            lost_reason: {
              type: "string",
              description: "Reason for losing opportunity"
            },
            score_delta: {
              type: "integer",
              description: "Amount to adjust lead score (positive or negative)"
            },
            new_lifecycle_stage: {
              type: "string",
              description: "New lifecycle stage for contact"
            },
            follow_up_at: {
              type: "string",
              description: "Follow-up date/time (ISO 8601 format)"
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      action = get_arg(args, :action)
      
      case action
      when "get_pipeline"
        get_pipeline
      when "create_opportunity"
        create_opportunity(args)
      when "update_opportunity"
        update_opportunity(args)
      when "move_stage"
        move_stage(args)
      when "close_won"
        close_won(args)
      when "close_lost"
        close_lost(args)
      when "assign_opportunity"
        assign_opportunity(args)
      when "log_note"
        log_note(args)
      when "log_call"
        log_call(args)
      when "log_email"
        log_email(args)
      when "create_task"
        create_task(args)
      when "schedule_meeting"
        schedule_meeting(args)
      when "complete_task"
        complete_task(args)
      when "assign_contact"
        assign_contact(args)
      when "get_contact_timeline"
        get_contact_timeline(args)
      when "get_tasks"
        get_tasks(args)
      when "update_lead_score"
        update_lead_score(args)
      when "promote_lifecycle"
        promote_lifecycle(args)
      when "schedule_follow_up"
        schedule_follow_up(args)
      else
        error_response("Unknown action: #{action}")
      end
    rescue => e
      Rails.logger.error "CRM Management Tool Error: #{e.message}"
      error_response(e.message)
    end

    private

    def get_pipeline
      stats = Opportunity.pipeline_stats(@entity)
      opportunities = @entity.opportunities.open.includes(:contact, :user, :assigned_agent).ordered_by_position

      pipeline = Opportunity::STAGES.keys.each_with_object({}) do |stage, hash|
        stage_opps = opportunities.select { |o| o.stage == stage }
        hash[stage] = {
          label: Opportunity::STAGES[stage][:label],
          color: Opportunity::STAGES[stage][:color],
          count: stage_opps.count,
          total_value: stage_opps.sum(&:value) || 0,
          opportunities: stage_opps.first(5).map do |o|
            {
              id: o.id,
              name: o.name,
              value: o.value,
              contact_name: o.contact.full_name,
              assigned_to: o.assigned_name,
              days_in_stage: o.days_in_stage
            }
          end
        }
      end

      success_response(
        pipeline: pipeline,
        stats: stats,
        message: "Pipeline retrieved. #{stats[:total_open]} open opportunities worth #{format_currency(stats[:total_value])} (#{format_currency(stats[:weighted_value])} weighted)"
      )
    end

    def create_opportunity(args)
      contact_id = get_arg(args, :contact_id)
      return error_response("contact_id is required") unless contact_id

      contact = @entity.contacts.find_by(id: contact_id)
      return error_response("Contact not found") unless contact

      opportunity = contact.create_opportunity!(
        name: get_arg(args, :name) || "Opportunity for #{contact.full_name}",
        value: get_arg(args, :value),
        source: contact.lead_source || 'direct',
        user: @user
      )

      success_response(
        opportunity: opportunity_summary(opportunity),
        message: "Created opportunity '#{opportunity.name}' for #{contact.full_name}"
      )
    end

    def update_opportunity(args)
      opportunity = find_opportunity(args)
      return opportunity if opportunity.is_a?(Hash) # Error response

      updates = {}
      updates[:name] = get_arg(args, :name) if get_arg(args, :name).present?
      updates[:value] = get_arg(args, :value) if get_arg(args, :value).present?
      updates[:notes] = get_arg(args, :description) if get_arg(args, :description).present?

      opportunity.update!(updates) if updates.any?

      success_response(
        opportunity: opportunity_summary(opportunity),
        message: "Updated opportunity '#{opportunity.name}'"
      )
    end

    def move_stage(args)
      opportunity = find_opportunity(args)
      return opportunity if opportunity.is_a?(Hash)

      new_stage = get_arg(args, :stage)
      return error_response("stage is required") unless new_stage

      if opportunity.move_to_stage!(new_stage, user: @user, notes: get_arg(args, :description))
        success_response(
          opportunity: opportunity_summary(opportunity),
          message: "Moved '#{opportunity.name}' to #{opportunity.stage_label}"
        )
      else
        error_response("Failed to move opportunity: #{opportunity.errors.full_messages.join(', ')}")
      end
    end

    def close_won(args)
      opportunity = find_opportunity(args)
      return opportunity if opportunity.is_a?(Hash)

      if opportunity.close_won!(user: @user, notes: get_arg(args, :description))
        success_response(
          opportunity: opportunity_summary(opportunity),
          message: "Congratulations! '#{opportunity.name}' marked as WON! Value: #{format_currency(opportunity.value)}"
        )
      else
        error_response("Failed to close opportunity: #{opportunity.errors.full_messages.join(', ')}")
      end
    end

    def close_lost(args)
      opportunity = find_opportunity(args)
      return opportunity if opportunity.is_a?(Hash)

      lost_reason = get_arg(args, :lost_reason)
      return error_response("lost_reason is required") unless lost_reason

      if opportunity.close_lost!(reason: lost_reason, user: @user, notes: get_arg(args, :description))
        success_response(
          opportunity: opportunity_summary(opportunity),
          message: "'#{opportunity.name}' marked as lost. Reason: #{lost_reason}"
        )
      else
        error_response("Failed to close opportunity: #{opportunity.errors.full_messages.join(', ')}")
      end
    end

    def assign_opportunity(args)
      opportunity = find_opportunity(args)
      return opportunity if opportunity.is_a?(Hash)

      if get_arg(args, :assign_to_user_id).present?
        user = @entity.users.find_by(id: get_arg(args, :assign_to_user_id))
        return error_response("User not found") unless user
        opportunity.assign_to_user!(user)
        success_response(message: "Assigned '#{opportunity.name}' to #{user.full_name}")
      elsif get_arg(args, :assign_to_agent_id).present?
        agent = AgentPlugin.for_entity(@entity).find_by(id: get_arg(args, :assign_to_agent_id))
        return error_response("Agent not found") unless agent
        opportunity.assign_to_agent!(agent)
        success_response(message: "Assigned '#{opportunity.name}' to AI Agent: #{agent.name}")
      else
        error_response("assign_to_user_id or assign_to_agent_id is required")
      end
    end

    def log_note(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      description = get_arg(args, :description)
      return error_response("description is required") unless description

      opportunity = get_arg(args, :opportunity_id).present? ? @entity.opportunities.find_by(id: get_arg(args, :opportunity_id)) : nil

      activity = Activity.log_note(
        contact: contact,
        entity: @entity,
        description: description,
        user: @user,
        opportunity: opportunity
      )

      success_response(
        activity: activity_summary(activity),
        message: "Note logged for #{contact.full_name}"
      )
    end

    def log_call(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      outcome = get_arg(args, :outcome) || 'connected'
      opportunity = get_arg(args, :opportunity_id).present? ? @entity.opportunities.find_by(id: get_arg(args, :opportunity_id)) : nil

      activity = Activity.log_call(
        contact: contact,
        entity: @entity,
        outcome: outcome,
        description: get_arg(args, :description),
        user: @user,
        opportunity: opportunity
      )

      success_response(
        activity: activity_summary(activity),
        message: "Call logged for #{contact.full_name} - #{outcome}"
      )
    end

    def log_email(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      subject = get_arg(args, :name) || "Email to #{contact.full_name}"
      opportunity = get_arg(args, :opportunity_id).present? ? @entity.opportunities.find_by(id: get_arg(args, :opportunity_id)) : nil

      activity = Activity.log_email(
        contact: contact,
        entity: @entity,
        subject: subject,
        description: get_arg(args, :description),
        user: @user,
        opportunity: opportunity
      )

      success_response(
        activity: activity_summary(activity),
        message: "Email logged for #{contact.full_name}"
      )
    end

    def create_task(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      subject = get_arg(args, :name) || "Task for #{contact.full_name}"
      due_at = get_arg(args, :due_at).present? ? Time.parse(get_arg(args, :due_at)) : nil
      
      # Determine assignee
      assigned_user = get_arg(args, :assign_to_user_id).present? ? @entity.users.find_by(id: get_arg(args, :assign_to_user_id)) : nil
      assigned_agent = get_arg(args, :assign_to_agent_id).present? ? AgentPlugin.for_entity(@entity).find_by(id: get_arg(args, :assign_to_agent_id)) : nil
      opportunity = get_arg(args, :opportunity_id).present? ? @entity.opportunities.find_by(id: get_arg(args, :opportunity_id)) : nil

      activity = Activity.create_task(
        contact: contact,
        entity: @entity,
        subject: subject,
        description: get_arg(args, :description),
        due_at: due_at,
        priority: get_arg(args, :priority) || 'normal',
        assigned_user: assigned_user || @user,
        assigned_agent: assigned_agent,
        opportunity: opportunity,
        user: @user
      )

      success_response(
        activity: activity_summary(activity),
        message: "Task '#{subject}' created#{due_at ? " due #{due_at.strftime('%b %d, %Y')}" : ''}"
      )
    end

    def schedule_meeting(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      scheduled_at = get_arg(args, :scheduled_at)
      return error_response("scheduled_at is required") unless scheduled_at

      subject = get_arg(args, :name) || "Meeting with #{contact.full_name}"
      opportunity = get_arg(args, :opportunity_id).present? ? @entity.opportunities.find_by(id: get_arg(args, :opportunity_id)) : nil

      activity = Activity.schedule_meeting(
        contact: contact,
        entity: @entity,
        subject: subject,
        scheduled_at: Time.parse(scheduled_at),
        description: get_arg(args, :description),
        assigned_user: @user,
        opportunity: opportunity,
        user: @user
      )

      success_response(
        activity: activity_summary(activity),
        message: "Meeting '#{subject}' scheduled for #{Time.parse(scheduled_at).strftime('%b %d, %Y at %I:%M %p')}"
      )
    end

    def complete_task(args)
      activity_id = get_arg(args, :activity_id)
      return error_response("activity_id is required") unless activity_id

      activity = @entity.activities.find_by(id: activity_id)
      return error_response("Task not found") unless activity

      if activity.complete!(outcome: get_arg(args, :outcome))
        success_response(
          activity: activity_summary(activity),
          message: "Task '#{activity.subject}' marked as complete"
        )
      else
        error_response("Failed to complete task: #{activity.errors.full_messages.join(', ')}")
      end
    end

    def assign_contact(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      if get_arg(args, :assign_to_user_id).present?
        user = @entity.users.find_by(id: get_arg(args, :assign_to_user_id))
        return error_response("User not found") unless user
        contact.assign_to_user!(user)
        success_response(message: "Assigned #{contact.full_name} to #{user.full_name}")
      elsif get_arg(args, :assign_to_agent_id).present?
        agent = AgentPlugin.for_entity(@entity).find_by(id: get_arg(args, :assign_to_agent_id))
        return error_response("Agent not found") unless agent
        contact.assign_to_agent!(agent)
        success_response(message: "Assigned #{contact.full_name} to AI Agent: #{agent.name}")
      else
        error_response("assign_to_user_id or assign_to_agent_id is required")
      end
    end

    def get_contact_timeline(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      activities = contact.timeline.limit(20)

      success_response(
        contact: {
          id: contact.id,
          name: contact.full_name,
          email: contact.email,
          lifecycle_stage: contact.lifecycle_stage_label,
          lead_score: contact.lead_score,
          assigned_to: contact.assigned_name
        },
        timeline: activities.map { |a| activity_summary(a) },
        open_tasks: contact.open_tasks.count,
        open_opportunities: contact.open_opportunities.count,
        message: "Timeline for #{contact.full_name}: #{activities.count} recent activities"
      )
    end

    def get_tasks(args)
      tasks = @entity.activities.tasks.open.includes(:contact, :opportunity, :assigned_user, :assigned_agent)

      # Filter by assignee if provided
      if get_arg(args, :assign_to_user_id).present?
        tasks = tasks.assigned_to_user(get_arg(args, :assign_to_user_id))
      elsif get_arg(args, :assign_to_agent_id).present?
        tasks = tasks.assigned_to_agent(get_arg(args, :assign_to_agent_id))
      end

      overdue = tasks.overdue.limit(10)
      due_today = tasks.due_today.limit(10)
      upcoming = tasks.due_this_week.where.not(id: due_today.select(:id)).limit(10)

      success_response(
        overdue: overdue.map { |t| task_summary(t) },
        due_today: due_today.map { |t| task_summary(t) },
        upcoming: upcoming.map { |t| task_summary(t) },
        counts: {
          overdue: tasks.overdue.count,
          due_today: tasks.due_today.count,
          total_open: tasks.count
        },
        message: "#{tasks.overdue.count} overdue, #{tasks.due_today.count} due today, #{tasks.count} total open tasks"
      )
    end

    def update_lead_score(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      delta = get_arg(args, :score_delta)
      return error_response("score_delta is required") unless delta

      new_score = contact.adjust_lead_score!(delta.to_i, reason: get_arg(args, :description))

      success_response(
        contact: {
          id: contact.id,
          name: contact.full_name,
          lead_score: new_score,
          lifecycle_stage: contact.lifecycle_stage_label
        },
        message: "#{contact.full_name}'s lead score #{delta.to_i > 0 ? 'increased' : 'decreased'} to #{new_score}"
      )
    end

    def promote_lifecycle(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      new_stage = get_arg(args, :new_lifecycle_stage)
      return error_response("new_lifecycle_stage is required") unless new_stage

      if contact.promote_lifecycle!(new_stage, source: 'manual')
        success_response(
          contact: {
            id: contact.id,
            name: contact.full_name,
            lifecycle_stage: contact.lifecycle_stage_label
          },
          message: "#{contact.full_name} promoted to #{contact.lifecycle_stage_label}"
        )
      else
        error_response("Cannot promote to #{new_stage} - invalid stage or backwards progression")
      end
    end

    def schedule_follow_up(args)
      contact = find_contact(args)
      return contact if contact.is_a?(Hash)

      follow_up_at = get_arg(args, :follow_up_at)
      return error_response("follow_up_at is required") unless follow_up_at

      task = contact.schedule_follow_up!(
        at: Time.parse(follow_up_at),
        user: @user,
        subject: get_arg(args, :name) || "Follow up with #{contact.full_name}"
      )

      success_response(
        task: activity_summary(task),
        message: "Follow-up scheduled with #{contact.full_name} for #{Time.parse(follow_up_at).strftime('%b %d, %Y at %I:%M %p')}"
      )
    end

    # Helper methods
    def find_opportunity(args)
      opportunity_id = get_arg(args, :opportunity_id)
      return error_response("opportunity_id is required") unless opportunity_id
      
      opportunity = @entity.opportunities.find_by(id: opportunity_id)
      return error_response("Opportunity not found") unless opportunity
      
      opportunity
    end

    def find_contact(args)
      contact_id = get_arg(args, :contact_id)
      return error_response("contact_id is required") unless contact_id
      
      contact = @entity.contacts.find_by(id: contact_id)
      return error_response("Contact not found") unless contact
      
      contact
    end

    def opportunity_summary(opp)
      {
        id: opp.id,
        name: opp.name,
        stage: opp.stage,
        stage_label: opp.stage_label,
        value: opp.value,
        weighted_value: opp.weighted_value,
        probability: opp.probability,
        contact_name: opp.contact.full_name,
        assigned_to: opp.assigned_name,
        days_in_stage: opp.days_in_stage
      }
    end

    def activity_summary(activity)
      {
        id: activity.id,
        type: activity.activity_type,
        type_label: activity.type_label,
        subject: activity.subject,
        status: activity.status,
        performer: activity.performer_name,
        created_at: activity.created_at.strftime('%b %d, %Y %I:%M %p')
      }
    end

    def task_summary(task)
      {
        id: task.id,
        subject: task.subject,
        due_at: task.due_at&.strftime('%b %d, %Y'),
        overdue: task.overdue?,
        priority: task.priority,
        contact_name: task.contact&.full_name,
        assigned_to: task.assigned_name
      }
    end

    def format_currency(amount)
      return "$0" unless amount
      "$#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end
  end
end
