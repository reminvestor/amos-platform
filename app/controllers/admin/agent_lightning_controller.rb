# frozen_string_literal: true

module Admin
  class AgentLightningController < Admin::BaseController
    before_action :set_agent, only: [:agent_detail]

    # GET /admin/agent_lightning
    def dashboard
      @service_status = check_service_status
      @recent_traces = AgentLightningTrace.includes(:entity, :user).order(created_at: :desc).limit(10)
      @recent_optimizations = AgentLightningOptimization.includes(:entity).order(created_at: :desc).limit(10)
      @training_jobs = AgentTrainingJob.order(created_at: :desc).limit(5)
      
      # Summary stats
      @stats = {
        total_traces: AgentLightningTrace.count,
        traces_today: AgentLightningTrace.where('created_at > ?', 24.hours.ago).count,
        total_optimizations: AgentLightningOptimization.count,
        active_training_jobs: AgentTrainingJob.where(status: 'running').count,
        entities_optimized: AgentLightningOptimization.select(:entity_id).distinct.count
      }

      # Performance metrics
      @performance = calculate_performance_metrics

      # Get agents for the agent selector
      @agents = AgentPlugin.where(is_active: true).order(:name)
    end

    # GET /admin/agent_lightning/training_jobs
    def training_jobs
      @training_jobs = AgentTrainingJob.includes(:entity).order(created_at: :desc).page(params[:page]).per(20)
    end

    # GET /admin/agent_lightning/optimizations
    def optimizations
      @optimizations = AgentLightningOptimization
        .includes(:entity, :agent_training_job)
        .order(created_at: :desc)
        .page(params[:page])
        .per(20)
    end

    # GET /admin/agent_lightning/traces
    def traces
      @traces = AgentLightningTrace
        .includes(:entity, :user)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)
    end

    # GET /admin/agent_lightning/agent/:agent_id
    def agent_detail
      @traces = AgentLightningTrace
        .joins(:agent_llm_calls)
        .where(agent_llm_calls: { agent_role: @agent.slug })
        .distinct
        .order(created_at: :desc)
        .limit(50)

      # Get optimizations for the agent's entity
      @optimizations = AgentLightningOptimization
        .where(entity: @agent.entity)
        .order(created_at: :desc)
        .limit(20)

      @performance_history = calculate_agent_performance_history(@agent)
    end

    # POST /admin/agent_lightning/start_training
    def start_training
      entity_id = params[:entity_id]
      config = training_config_params

      begin
        # Call the Python service to start training
        result = PythonAgentLightningClient.start_training(entity_id, config)
        
        if result[:success]
          redirect_to admin_agent_lightning_path, notice: "Training job started: #{result[:job_id]}"
        else
          redirect_to admin_agent_lightning_path, alert: "Failed to start training: #{result[:error]}"
        end
      rescue => e
        redirect_to admin_agent_lightning_path, alert: "Error starting training: #{e.message}"
      end
    end

    # POST /admin/agent_lightning/stop_training
    def stop_training
      job_id = params[:job_id]

      begin
        result = PythonAgentLightningClient.stop_training(job_id)
        
        if result[:success]
          redirect_to admin_agent_lightning_path, notice: "Training job stopped"
        else
          redirect_to admin_agent_lightning_path, alert: "Failed to stop training: #{result[:error]}"
        end
      rescue => e
        redirect_to admin_agent_lightning_path, alert: "Error stopping training: #{e.message}"
      end
    end

    # POST /admin/agent_lightning/rollback/:optimization_id
    def rollback
      optimization = AgentLightningOptimization.find(params[:optimization_id])
      
      begin
        unless optimization.can_rollback?
          redirect_to admin_agent_lightning_path, alert: "Cannot rollback optimization - status is #{optimization.status}"
          return
        end

        # Restore the previous prompts
        # The before_prompts field contains the prompts before optimization
        if optimization.before_prompts.present?
          # Apply the rollback via the Python service
          result = PythonAgentLightningClient.rollback_optimization(optimization.optimization_id)
          
          if result[:success]
            optimization.mark_rolled_back!
            redirect_to admin_agent_lightning_path, notice: "Successfully rolled back optimization #{optimization.optimization_id[0..7]}"
          else
            redirect_to admin_agent_lightning_path, alert: "Failed to rollback: #{result[:error]}"
          end
        else
          optimization.mark_rolled_back!
          redirect_to admin_agent_lightning_path, notice: "Optimization marked as rolled back (no previous prompts to restore)"
        end
      rescue => e
        redirect_to admin_agent_lightning_path, alert: "Error during rollback: #{e.message}"
      end
    end

    # GET /admin/agent_lightning/service_status
    def service_status
      @status = check_service_status
      render json: @status
    end

    private

    def set_agent
      @agent = AgentPlugin.find(params[:agent_id])
    end

    def training_config_params
      params.permit(:learning_rate, :batch_size, :num_epochs, :agent_ids => [])
    end

    def check_service_status
      begin
        response = PythonAgentLightningClient.health_check
        {
          online: response[:status] == 'healthy',
          version: response[:version],
          agent_lightning_available: response[:agent_lightning_available],
          last_check: Time.current
        }
      rescue => e
        {
          online: false,
          error: e.message,
          last_check: Time.current
        }
      end
    end

    def calculate_performance_metrics
      # Calculate overall performance metrics
      recent_traces = AgentLightningTrace.where('created_at > ?', 7.days.ago)
      total_count = recent_traces.count
      
      {
        avg_success_rate: total_count > 0 ? (recent_traces.where(status: 'completed').count.to_f / total_count * 100).round(1) : 0,
        avg_duration_ms: recent_traces.average(:duration_ms)&.round(0) || 0,
        total_traces: total_count,
        completed_traces: recent_traces.where(status: 'completed').count
      }
    end

    def calculate_agent_performance_history(agent)
      # Get performance over time for this agent
      traces = AgentLightningTrace
        .joins(:agent_llm_calls)
        .where(agent_llm_calls: { agent_role: agent.slug })
        .where('agent_lightning_traces.created_at > ?', 30.days.ago)
        .group("DATE(agent_lightning_traces.created_at)")
        .count

      optimizations = AgentLightningOptimization
        .where(entity: agent.entity)
        .where('created_at > ?', 30.days.ago)
        .pluck(:created_at, :improvement_percentage)

      {
        daily_traces: traces,
        optimizations: optimizations.map do |opt|
          {
            date: opt[0],
            improvement: opt[1]&.to_f
          }
        end
      }
    end
  end
end

