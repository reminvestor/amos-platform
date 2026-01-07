# frozen_string_literal: true

module Api
  module V1
    class OpportunitiesController < BaseController
      before_action :set_opportunity, only: [:show, :update, :destroy, :move_stage, :assign, :close_won, :close_lost, :reopen]

      # GET /api/v1/opportunities
      def index
        opportunities = current_entity.opportunities
                                      .includes(:contact, :user, :assigned_agent, :activities)

        # Filters
        opportunities = opportunities.by_stage(params[:stage]) if params[:stage].present?
        opportunities = opportunities.by_user(params[:user_id]) if params[:user_id].present?
        opportunities = opportunities.by_agent(params[:agent_id]) if params[:agent_id].present?
        opportunities = opportunities.unassigned if params[:unassigned] == 'true'
        opportunities = opportunities.stale(params[:stale_days]&.to_i || 7) if params[:stale] == 'true'
        opportunities = opportunities.closing_soon(params[:closing_days]&.to_i || 30) if params[:closing_soon] == 'true'
        
        # Status filter
        case params[:status]
        when 'open'
          opportunities = opportunities.open
        when 'closed'
          opportunities = opportunities.closed
        when 'won'
          opportunities = opportunities.won
        when 'lost'
          opportunities = opportunities.lost
        end

        # Ordering
        opportunities = case params[:order]
                        when 'value_desc'
                          opportunities.order(value: :desc)
                        when 'value_asc'
                          opportunities.order(value: :asc)
                        when 'close_date'
                          opportunities.order(expected_close_date: :asc)
                        when 'created'
                          opportunities.order(created_at: :desc)
                        else
                          opportunities.ordered_by_position
                        end

        # Pagination
        page = params[:page]&.to_i || 1
        per_page = [params[:per_page]&.to_i || 25, 100].min

        render json: {
          success: true,
          opportunities: opportunities.offset((page - 1) * per_page).limit(per_page).map { |o| opportunity_json(o) },
          total_count: opportunities.count,
          page: page,
          per_page: per_page,
          pipeline_stats: Opportunity.pipeline_stats(current_entity)
        }
      end

      # GET /api/v1/opportunities/pipeline
      def pipeline
        opportunities = current_entity.opportunities.open
                                      .includes(:contact, :user, :assigned_agent)
                                      .ordered_by_position

        # Group by stage
        pipeline = Opportunity::STAGES.keys.each_with_object({}) do |stage, hash|
          stage_opps = opportunities.select { |o| o.stage == stage }
          hash[stage] = {
            info: Opportunity::STAGES[stage],
            opportunities: stage_opps.map { |o| opportunity_card_json(o) },
            count: stage_opps.count,
            total_value: stage_opps.sum(&:value) || 0
          }
        end

        render json: {
          success: true,
          pipeline: pipeline,
          stats: Opportunity.pipeline_stats(current_entity)
        }
      end

      # GET /api/v1/opportunities/:id
      def show
        render json: {
          success: true,
          opportunity: opportunity_json(@opportunity, include_activities: true)
        }
      end

      # POST /api/v1/opportunities
      def create
        @opportunity = current_entity.opportunities.new(opportunity_params)
        @opportunity.user ||= current_user

        if @opportunity.save
          render json: {
            success: true,
            message: 'Opportunity created successfully',
            opportunity: opportunity_json(@opportunity)
          }, status: :created
        else
          render json: {
            success: false,
            message: 'Failed to create opportunity',
            errors: @opportunity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/opportunities/:id
      def update
        if @opportunity.update(opportunity_params)
          render json: {
            success: true,
            message: 'Opportunity updated successfully',
            opportunity: opportunity_json(@opportunity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to update opportunity',
            errors: @opportunity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/opportunities/:id
      def destroy
        @opportunity.destroy
        render json: {
          success: true,
          message: 'Opportunity deleted successfully'
        }
      end

      # POST /api/v1/opportunities/:id/move_stage
      def move_stage
        new_stage = params[:stage]
        
        unless Opportunity::STAGES.key?(new_stage)
          return render json: {
            success: false,
            message: "Invalid stage: #{new_stage}"
          }, status: :unprocessable_entity
        end

        if @opportunity.move_to_stage!(new_stage, user: current_user, notes: params[:notes])
          render json: {
            success: true,
            message: "Moved to #{Opportunity::STAGES[new_stage][:label]}",
            opportunity: opportunity_json(@opportunity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to move opportunity',
            errors: @opportunity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/opportunities/:id/assign
      def assign
        if params[:user_id].present?
          user = current_entity.users.find(params[:user_id])
          @opportunity.assign_to_user!(user)
          render json: {
            success: true,
            message: "Assigned to #{user.full_name}",
            opportunity: opportunity_json(@opportunity)
          }
        elsif params[:agent_id].present?
          agent = AgentPlugin.for_entity(current_entity).find(params[:agent_id])
          @opportunity.assign_to_agent!(agent)
          render json: {
            success: true,
            message: "Assigned to AI Agent: #{agent.name}",
            opportunity: opportunity_json(@opportunity)
          }
        else
          render json: {
            success: false,
            message: 'Must provide user_id or agent_id'
          }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound => e
        render json: { success: false, message: 'User or agent not found' }, status: :not_found
      end

      # POST /api/v1/opportunities/:id/close_won
      def close_won
        if @opportunity.close_won!(user: current_user, notes: params[:notes])
          render json: {
            success: true,
            message: 'Opportunity marked as won!',
            opportunity: opportunity_json(@opportunity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to close opportunity',
            errors: @opportunity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/opportunities/:id/close_lost
      def close_lost
        unless params[:reason].present?
          return render json: {
            success: false,
            message: 'Lost reason is required'
          }, status: :unprocessable_entity
        end

        if @opportunity.close_lost!(reason: params[:reason], user: current_user, notes: params[:notes])
          render json: {
            success: true,
            message: 'Opportunity marked as lost',
            opportunity: opportunity_json(@opportunity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to close opportunity',
            errors: @opportunity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/opportunities/:id/reopen
      def reopen
        if @opportunity.reopen!(user: current_user, notes: params[:notes])
          render json: {
            success: true,
            message: 'Opportunity reopened',
            opportunity: opportunity_json(@opportunity)
          }
        else
          render json: {
            success: false,
            message: 'Failed to reopen opportunity',
            errors: @opportunity.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/opportunities/reorder
      def reorder
        params[:positions].each do |item|
          opp = current_entity.opportunities.find_by(id: item[:id])
          opp&.update(position: item[:position], stage: item[:stage]) if opp
        end

        render json: { success: true, message: 'Positions updated' }
      end

      private

      def set_opportunity
        @opportunity = current_entity.opportunities.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, message: 'Opportunity not found' }, status: :not_found
      end

      def opportunity_params
        params.require(:opportunity).permit(
          :contact_id, :name, :stage, :value, :probability,
          :expected_close_date, :source, :notes, :user_id, :assigned_agent_id, :position
        )
      end

      def opportunity_json(opp, include_activities: false)
        json = {
          id: opp.id,
          name: opp.name,
          stage: opp.stage,
          stage_label: opp.stage_label,
          stage_color: opp.stage_color,
          value: opp.value,
          weighted_value: opp.weighted_value,
          probability: opp.probability,
          expected_close_date: opp.expected_close_date,
          actual_close_date: opp.actual_close_date,
          source: opp.source,
          lost_reason: opp.lost_reason,
          notes: opp.notes,
          position: opp.position,
          days_in_stage: opp.days_in_stage,
          days_open: opp.days_open,
          stale: opp.stale?,
          contact: {
            id: opp.contact.id,
            name: opp.contact.full_name,
            email: opp.contact.email,
            lifecycle_stage: opp.contact.lifecycle_stage
          },
          owner: opp.user ? {
            id: opp.user.id,
            name: opp.user.full_name,
            type: 'user'
          } : nil,
          assigned_agent: opp.assigned_agent ? {
            id: opp.assigned_agent.id,
            name: opp.assigned_agent.name,
            type: 'agent'
          } : nil,
          assigned_name: opp.assigned_name,
          created_at: opp.created_at,
          updated_at: opp.updated_at
        }

        if include_activities
          json[:activities] = opp.activities.timeline.limit(20).map { |a| activity_summary_json(a) }
          json[:activity_count] = opp.activities.count
        end

        json
      end

      def opportunity_card_json(opp)
        {
          id: opp.id,
          name: opp.name,
          value: opp.value,
          probability: opp.probability,
          expected_close_date: opp.expected_close_date,
          days_in_stage: opp.days_in_stage,
          stale: opp.stale?,
          position: opp.position,
          contact: {
            id: opp.contact.id,
            name: opp.contact.full_name
          },
          assigned_name: opp.assigned_name,
          assigned_type: opp.user_id ? 'user' : (opp.assigned_agent_id ? 'agent' : nil)
        }
      end

      def activity_summary_json(activity)
        {
          id: activity.id,
          type: activity.activity_type,
          type_icon: activity.type_icon,
          type_color: activity.type_color,
          subject: activity.subject,
          performer_name: activity.performer_name,
          created_at: activity.created_at
        }
      end
    end
  end
end
