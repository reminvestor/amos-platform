# frozen_string_literal: true

module Api
  module V1
    class ActivitiesController < Api::BaseController
      before_action :authenticate_api_request
      before_action :set_activity, only: [:show, :update, :destroy, :complete, :cancel, :assign, :reschedule]

      # GET /api/v1/activities
      def index
        activities = current_entity.activities.includes(:contact, :opportunity, :user, :assigned_user, :assigned_agent, :performed_by_agent)

        # Filters
        activities = activities.by_type(params[:type]) if params[:type].present?
        activities = activities.by_status(params[:status]) if params[:status].present?
        activities = activities.for_contact(params[:contact_id]) if params[:contact_id].present?
        activities = activities.for_opportunity(params[:opportunity_id]) if params[:opportunity_id].present?
        activities = activities.assigned_to_user(params[:assigned_user_id]) if params[:assigned_user_id].present?
        activities = activities.assigned_to_agent(params[:assigned_agent_id]) if params[:assigned_agent_id].present?
        activities = activities.unassigned if params[:unassigned] == 'true'
        activities = activities.ai_activities if params[:ai_only] == 'true'
        activities = activities.human_activities if params[:human_only] == 'true'

        # Task-specific filters
        if params[:tasks_only] == 'true'
          activities = activities.tasks
          activities = activities.overdue if params[:overdue] == 'true'
          activities = activities.due_today if params[:due_today] == 'true'
          activities = activities.due_this_week if params[:due_this_week] == 'true'
        end

        # Date range
        if params[:start_date].present?
          activities = activities.where('created_at >= ?', Date.parse(params[:start_date]).beginning_of_day)
        end
        if params[:end_date].present?
          activities = activities.where('created_at <= ?', Date.parse(params[:end_date]).end_of_day)
        end

        # Ordering
        activities = case params[:order]
                     when 'oldest'
                       activities.order(created_at: :asc)
                     when 'due_date'
                       activities.order(due_at: :asc)
                     when 'scheduled'
                       activities.order(scheduled_at: :asc)
                     else
                       activities.recent
                     end

        # Pagination
        page = params[:page]&.to_i || 1
        per_page = [params[:per_page]&.to_i || 25, 100].min

        render json: {
          success: true,
          activities: activities.offset((page - 1) * per_page).limit(per_page).map { |a| activity_json(a) },
          total_count: activities.count,
          page: page,
          per_page: per_page,
          stats: Activity.activity_stats(current_entity)
        }
      end

      # GET /api/v1/activities/tasks
      def tasks
        tasks = current_entity.activities.tasks.includes(:contact, :opportunity, :assigned_user, :assigned_agent)

        # Group by status
        grouped = {
          overdue: tasks.overdue.map { |t| task_json(t) },
          due_today: tasks.due_today.where.not(id: tasks.overdue.select(:id)).map { |t| task_json(t) },
          upcoming: tasks.due_this_week.where.not(id: tasks.due_today.select(:id)).where.not(id: tasks.overdue.select(:id)).map { |t| task_json(t) },
          pending: tasks.pending.where(due_at: nil).or(tasks.pending.where('due_at > ?', 1.week.from_now)).map { |t| task_json(t) },
          completed_recently: tasks.completed.where('completed_at >= ?', 7.days.ago).recent.limit(10).map { |t| task_json(t) }
        }

        render json: {
          success: true,
          tasks: grouped,
          counts: {
            overdue: tasks.overdue.count,
            due_today: tasks.due_today.count,
            open: tasks.open.count,
            completed_this_week: tasks.completed.where('completed_at >= ?', 1.week.ago).count
          }
        }
      end

      # GET /api/v1/activities/timeline
      def timeline
        # Get activities for a contact or opportunity
        if params[:contact_id].present?
          contact = current_entity.contacts.find(params[:contact_id])
          activities = contact.activities
        elsif params[:opportunity_id].present?
          opportunity = current_entity.opportunities.find(params[:opportunity_id])
          activities = opportunity.activities
        else
          activities = current_entity.activities
        end

        activities = activities.includes(:user, :performed_by_agent, :assigned_user, :assigned_agent)
                               .timeline
                               .limit(params[:limit]&.to_i || 50)

        render json: {
          success: true,
          timeline: activities.map { |a| timeline_entry_json(a) }
        }
      end

      # GET /api/v1/activities/:id
      def show
        render json: {
          success: true,
          activity: activity_json(@activity)
        }
      end

      # POST /api/v1/activities
      def create
        @activity = current_entity.activities.new(activity_params)
        @activity.user ||= current_user

        if @activity.save
          render json: {
            success: true,
            message: 'Activity created successfully',
            activity: activity_json(@activity)
          }, status: :created
        else
          render json: {
            success: false,
            message: 'Failed to create activity',
            errors: @activity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/activities/log_note
      def log_note
        contact = current_entity.contacts.find(params[:contact_id])
        opportunity = params[:opportunity_id].present? ? current_entity.opportunities.find(params[:opportunity_id]) : nil

        activity = Activity.log_note(
          contact: contact,
          entity: current_entity,
          description: params[:description],
          user: current_user,
          opportunity: opportunity
        )

        render json: {
          success: true,
          message: 'Note logged',
          activity: activity_json(activity)
        }
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, message: 'Contact not found' }, status: :not_found
      end

      # POST /api/v1/activities/log_call
      def log_call
        contact = current_entity.contacts.find(params[:contact_id])
        opportunity = params[:opportunity_id].present? ? current_entity.opportunities.find(params[:opportunity_id]) : nil

        activity = Activity.log_call(
          contact: contact,
          entity: current_entity,
          outcome: params[:outcome],
          description: params[:description],
          user: current_user,
          opportunity: opportunity,
          duration_minutes: params[:duration_minutes]
        )

        render json: {
          success: true,
          message: 'Call logged',
          activity: activity_json(activity)
        }
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, message: 'Contact not found' }, status: :not_found
      end

      # POST /api/v1/activities/log_email
      def log_email
        contact = current_entity.contacts.find(params[:contact_id])
        opportunity = params[:opportunity_id].present? ? current_entity.opportunities.find(params[:opportunity_id]) : nil

        activity = Activity.log_email(
          contact: contact,
          entity: current_entity,
          subject: params[:subject],
          description: params[:description],
          user: current_user,
          opportunity: opportunity
        )

        render json: {
          success: true,
          message: 'Email logged',
          activity: activity_json(activity)
        }
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, message: 'Contact not found' }, status: :not_found
      end

      # POST /api/v1/activities/create_task
      def create_task
        contact = params[:contact_id].present? ? current_entity.contacts.find(params[:contact_id]) : nil
        opportunity = params[:opportunity_id].present? ? current_entity.opportunities.find(params[:opportunity_id]) : nil

        # Determine assignee
        assigned_user = params[:assigned_user_id].present? ? current_entity.users.find(params[:assigned_user_id]) : nil
        assigned_agent = params[:assigned_agent_id].present? ? AgentPlugin.for_entity(current_entity).find(params[:assigned_agent_id]) : nil

        activity = Activity.create_task(
          contact: contact,
          entity: current_entity,
          subject: params[:subject],
          description: params[:description],
          due_at: params[:due_at].present? ? Time.parse(params[:due_at]) : nil,
          priority: params[:priority] || 'normal',
          assigned_user: assigned_user,
          assigned_agent: assigned_agent,
          opportunity: opportunity,
          user: current_user
        )

        render json: {
          success: true,
          message: 'Task created',
          activity: activity_json(activity)
        }
      rescue ActiveRecord::RecordNotFound => e
        render json: { success: false, message: e.message }, status: :not_found
      end

      # POST /api/v1/activities/schedule_meeting
      def schedule_meeting
        contact = current_entity.contacts.find(params[:contact_id])
        opportunity = params[:opportunity_id].present? ? current_entity.opportunities.find(params[:opportunity_id]) : nil

        assigned_user = params[:assigned_user_id].present? ? current_entity.users.find(params[:assigned_user_id]) : current_user
        assigned_agent = params[:assigned_agent_id].present? ? AgentPlugin.for_entity(current_entity).find(params[:assigned_agent_id]) : nil

        activity = Activity.schedule_meeting(
          contact: contact,
          entity: current_entity,
          subject: params[:subject],
          scheduled_at: Time.parse(params[:scheduled_at]),
          description: params[:description],
          assigned_user: assigned_user,
          assigned_agent: assigned_agent,
          opportunity: opportunity,
          user: current_user
        )

        render json: {
          success: true,
          message: 'Meeting scheduled',
          activity: activity_json(activity)
        }
      rescue ActiveRecord::RecordNotFound => e
        render json: { success: false, message: e.message }, status: :not_found
      end

      # PATCH/PUT /api/v1/activities/:id
      def update
        if @activity.update(activity_params)
          render json: {
            success: true,
            message: 'Activity updated successfully',
            activity: activity_json(@activity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to update activity',
            errors: @activity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/activities/:id
      def destroy
        @activity.destroy
        render json: {
          success: true,
          message: 'Activity deleted successfully'
        }
      end

      # POST /api/v1/activities/:id/complete
      def complete
        if @activity.complete!(outcome: params[:outcome])
          render json: {
            success: true,
            message: 'Activity marked as complete',
            activity: activity_json(@activity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to complete activity',
            errors: @activity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/activities/:id/cancel
      def cancel
        if @activity.cancel!(reason: params[:reason])
          render json: {
            success: true,
            message: 'Activity cancelled',
            activity: activity_json(@activity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to cancel activity',
            errors: @activity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/activities/:id/assign
      def assign
        if params[:user_id].present?
          user = current_entity.users.find(params[:user_id])
          @activity.assign_to_user!(user)
          render json: {
            success: true,
            message: "Assigned to #{user.full_name}",
            activity: activity_json(@activity)
          }
        elsif params[:agent_id].present?
          agent = AgentPlugin.for_entity(current_entity).find(params[:agent_id])
          @activity.assign_to_agent!(agent)
          render json: {
            success: true,
            message: "Assigned to AI Agent: #{agent.name}",
            activity: activity_json(@activity)
          }
        else
          render json: {
            success: false,
            message: 'Must provide user_id or agent_id'
          }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, message: 'User or agent not found' }, status: :not_found
      end

      # POST /api/v1/activities/:id/reschedule
      def reschedule
        unless params[:scheduled_at].present?
          return render json: { success: false, message: 'scheduled_at is required' }, status: :unprocessable_entity
        end

        if @activity.reschedule!(Time.parse(params[:scheduled_at]))
          render json: {
            success: true,
            message: 'Activity rescheduled',
            activity: activity_json(@activity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to reschedule activity',
            errors: @activity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def set_activity
        @activity = current_entity.activities.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, message: 'Activity not found' }, status: :not_found
      end

      def activity_params
        params.require(:activity).permit(
          :contact_id, :opportunity_id, :activity_type, :subject, :description,
          :scheduled_at, :due_at, :outcome, :status, :priority,
          :assigned_user_id, :assigned_agent_id
        )
      end

      def activity_json(activity)
        {
          id: activity.id,
          activity_type: activity.activity_type,
          type_icon: activity.type_icon,
          type_color: activity.type_color,
          type_label: activity.type_label,
          subject: activity.subject,
          description: activity.description,
          status: activity.status,
          priority: activity.priority,
          outcome: activity.outcome,
          scheduled_at: activity.scheduled_at,
          due_at: activity.due_at,
          completed_at: activity.completed_at,
          overdue: activity.overdue?,
          contact: activity.contact ? {
            id: activity.contact.id,
            name: activity.contact.full_name,
            email: activity.contact.email
          } : nil,
          opportunity: activity.opportunity ? {
            id: activity.opportunity.id,
            name: activity.opportunity.name
          } : nil,
          performer: {
            name: activity.performer_name,
            type: activity.ai_performed? ? 'agent' : 'user',
            id: activity.performed_by&.id
          },
          assigned_to: activity.assigned? ? {
            name: activity.assigned_name,
            type: activity.assigned_user_id ? 'user' : 'agent',
            id: activity.assigned_to&.id
          } : nil,
          created_at: activity.created_at,
          updated_at: activity.updated_at,
          metadata: activity.metadata
        }
      end

      def task_json(task)
        {
          id: task.id,
          subject: task.subject,
          description: task.description,
          status: task.status,
          priority: task.priority,
          due_at: task.due_at,
          overdue: task.overdue?,
          contact: task.contact ? { id: task.contact.id, name: task.contact.full_name } : nil,
          opportunity: task.opportunity ? { id: task.opportunity.id, name: task.opportunity.name } : nil,
          assigned_name: task.assigned_name,
          assigned_type: task.assigned_user_id ? 'user' : (task.assigned_agent_id ? 'agent' : nil),
          created_at: task.created_at
        }
      end

      def timeline_entry_json(activity)
        {
          id: activity.id,
          type: activity.activity_type,
          icon: activity.type_icon,
          color: activity.type_color,
          label: activity.type_label,
          subject: activity.subject,
          description: activity.description&.truncate(200),
          performer: activity.performer_name,
          ai_performed: activity.ai_performed?,
          status: activity.status,
          outcome: activity.outcome,
          timestamp: activity.completed_at || activity.created_at
        }
      end

      def authenticate_api_request
        token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

        unless token.present?
          render json: { success: false, message: "Authorization token required" }, status: :unauthorized
          return
        end

        @current_user = User.find_by(api_key: token)

        unless @current_user
          render json: { success: false, message: "Invalid token" }, status: :unauthorized
          return
        end
      end

      def current_entity
        @current_user&.entity
      end
    end
  end
end
