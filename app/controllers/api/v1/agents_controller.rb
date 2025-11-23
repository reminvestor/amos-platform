class Api::V1::AgentsController < Api::BaseController
  before_action :authenticate_user!
  before_action :set_entity
  before_action :set_agent, only: [:show, :execute]

  # GET /api/v1/agents
  def index
    agents = @entity.custom_agent_definitions.active.select(:id, :name, :agent_type, :definition, :created_at)

    render json: {
      agents: agents.map { |a| agent_list_json(a) },
      total: agents.count
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
      job_record = @agent.execute(task, {
        session_id: SecureRandom.uuid,
        user_id: current_user.id,
        source: 'mobile_app'
      })

      render json: {
        job_id: job_record.job_id,
        status: job_record.status,
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

  # GET /api/v1/agents/types/list
  def agent_types
    types = CustomAgentDefinition::AGENT_TYPES.map { |type| { key: type, label: type.humanize } }
    render json: { types: types }
  end

  private

  def agent_list_json(agent)
    definition = agent.definition || {}
    {
      id: agent.id,
      name: agent.name,
      description: definition['description'],
      agent_type: agent.agent_type,
      interactive: definition['interactive'] || false,
      icon: icon_for_type(agent.agent_type),
      created_at: agent.created_at.iso8601
    }
  end

  def agent_detail_json(agent)
    definition = agent.definition || {}
    {
      id: agent.id,
      name: agent.name,
      description: definition['description'],
      agent_type: agent.agent_type,
      interactive: definition['interactive'] || false,
      icon: icon_for_type(agent.agent_type),
      fields: definition['fields'] || [],
      required_context: definition['required_context'] || [],
      capabilities: definition['capabilities'] || [],
      created_at: agent.created_at.iso8601,
      updated_at: agent.updated_at.iso8601
    }
  end

  def icon_for_type(type)
    case type
    when 'content_generator'
      'file-document-plus'
    when 'data_processor'
      'chart-line'
    when 'api_integration'
      'api'
    when 'workflow_automation'
      'workflow'
    else
      'robot'
    end
  end

  def set_agent
    @agent = @entity.custom_agent_definitions.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Agent not found' }, status: :not_found
  end

  def set_entity
    @entity = current_user.entity
  end
end
