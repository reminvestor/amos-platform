# frozen_string_literal: true

module Api
  module V1
    class AgentsController < BaseController
      # Entity required - agents are scoped to entity
      before_action :set_agent, only: [:show, :execute]

      # GET /api/v1/agents
      def index
        # Use AgentPlugin which is the existing agents table
        agents = AgentPlugin.for_entity(current_entity).active
        agents_data = agents.map { |a| agent_list_json(a) }

        render json: {
          agents: agents_data,
          total: agents_data.size
        }
      end

      # GET /api/v1/agents/:id
      def show
        render json: agent_detail_json(@agent)
      end

      # POST /api/v1/agents/:id/execute
      def execute
        task = params[:task]

        unless task.present?
          return render json: { error: 'Task is required' }, status: :bad_request
        end

        begin
          # Create execution record
          execution = @agent.agent_plugin_executions.create!(
            entity: current_entity,
            user: current_user,
            status: 'pending',
            input_data: { task: task, source: 'mobile_app' }
          )

          render json: {
            job_id: execution.id,
            status: execution.status,
            message: "Agent execution started"
          }, status: :accepted
        rescue => e
          Rails.logger.error("Agent execution error: #{e.message}")
          render json: {
            error: 'Failed to execute agent',
            message: e.message
          }, status: :service_unavailable
        end
      end

      # GET /api/v1/agents/agent_types
      def agent_types
        types = %w[executor planner analyst verifier fixer custom].map { |type| { key: type, label: type.humanize } }
        render json: { types: types }
      end

      private

      def agent_list_json(agent)
        config = agent.configuration || {}
        {
          id: agent.id,
          name: agent.name,
          description: agent.description,
          agent_type: agent.role,
          interactive: config['interactive'] || false,
          icon: icon_for_role(agent.role),
          created_at: agent.created_at.iso8601
        }
      end

      def agent_detail_json(agent)
        config = agent.configuration || {}
        {
          id: agent.id,
          name: agent.name,
          description: agent.description,
          agent_type: agent.role,
          interactive: config['interactive'] || false,
          icon: icon_for_role(agent.role),
          fields: config['fields'] || [],
          required_context: config['required_context'] || [],
          capabilities: agent.capability_names,
          tools: agent.agent_tools.map { |t| { name: t.tool_name, required: t.required } },
          created_at: agent.created_at.iso8601,
          updated_at: agent.updated_at.iso8601
        }
      end

      def icon_for_role(role)
        case role
        when 'executor'
          'play-circle'
        when 'planner'
          'clipboard-list'
        when 'analyst'
          'chart-line'
        when 'verifier'
          'check-circle'
        when 'fixer'
          'wrench'
        else
          'robot'
        end
      end

      def set_agent
        @agent = AgentPlugin.for_entity(current_entity).active.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Agent not found' }, status: :not_found
      end
    end
  end
end
