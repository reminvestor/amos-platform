module Admin
  class AgentLightningController < ApplicationController
    include EntityScoped
    before_action :check_admin_access

    def dashboard
      @entity = current_entity
      @config = @entity.agent_lightning_config || create_default_config

      # Current Status
      @traces = @entity.agent_lightning_traces
      @total_traces = @traces.count
      @completed_traces = @traces.where(status: 'completed').count
      @failed_traces = @traces.where(status: 'failed').count
      @traces_with_rewards = @traces.with_reward.count
      @traces_ready_for_training = @traces.where(included_in_training: false).with_reward.count

      # Recent Metrics (Last 100 traces)
      @recent_traces = @traces.recent.limit(100)
      if @recent_traces.any?
        @success_rate = ((@recent_traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / @recent_traces.count) * 100).round(1)
        @avg_tokens = @recent_traces.average(:token_count).round(0)
        @avg_cost = @recent_traces.average(:cost_estimate).round(4)
        @avg_duration = @recent_traces.average(:duration_ms).round(0)
        @total_cost = @recent_traces.sum(:cost_estimate).round(2)
      else
        @success_rate = 0
        @avg_tokens = 0
        @avg_cost = 0.0
        @avg_duration = 0
        @total_cost = 0.0
      end

      # Training Status
      @last_training_job = @entity.agent_training_jobs.completed.recent.first
      @training_history = @entity.agent_training_jobs.completed.recent.limit(10)

      # Next Training
      @next_training_at = if @config.last_training_at
        @config.last_training_at + @config.retrain_frequency_hours.hours
      else
        "Not scheduled yet"
      end

      @ready_for_training = @config.ready_for_training?

      # Recent Recommendations
      if @last_training_job && @last_training_job.training_results['recommended_changes']
        @recommendations = @last_training_job.training_results['recommended_changes']
      else
        @recommendations = []
      end

      # LLM Call Analysis
      @llm_calls = @entity.agent_llm_calls.recent.limit(500)
      if @llm_calls.any?
        @llm_success_rate = ((@llm_calls.count { |c| c.status == 'success' }.to_f / @llm_calls.count) * 100).round(1)
        @avg_latency = @llm_calls.average(:latency_ms).round(0)
        @llm_by_role = @llm_calls.group_by(&:agent_role).map do |role, calls|
          {
            role: role,
            count: calls.count,
            success_rate: ((calls.count { |c| c.status == 'success' }.to_f / calls.count) * 100).round(1),
            avg_tokens: calls.average(:total_tokens).round(0),
            total_cost: calls.sum(:cost).round(4)
          }
        end
      end

      # Tool Analysis
      @tool_executions = @entity.agent_tool_executions.recent.limit(500)
      if @tool_executions.any?
        @tool_success_rate = ((@tool_executions.count { |e| e.status == 'success' }.to_f / @tool_executions.count) * 100).round(1)
        @top_tools = @tool_executions.group_by(&:tool_name)
          .map { |tool, execs|
            {
              name: tool,
              count: execs.count,
              success_rate: ((execs.count { |e| e.status == 'success' }.to_f / execs.count) * 100).round(1)
            }
          }
          .sort_by { |t| t[:count] }
          .reverse
          .first(5)
      end

      # Training Ready Check
      @training_checks = {
        enabled: @config.enabled?,
        enough_traces: @traces_ready_for_training >= @config.min_traces_for_training,
        retrain_due: @config.should_retrain?
      }
      @can_train_now = @training_checks[:enabled] && @training_checks[:enough_traces] && @training_checks[:retrain_due]
    end

    def train_now
      @entity = current_entity
      service = AgentLightningTrainingService.new(@entity)

      unless service.config.ready_for_training?
        redirect_to admin_agent_lightning_dashboard_path, alert: "Entity not ready for training. Check status page."
        return
      end

      result = service.execute_training

      if result[:success]
        redirect_to admin_agent_lightning_dashboard_path, notice: "✅ Training completed! Improvement: +#{result[:improvement]}%"
      else
        redirect_to admin_agent_lightning_dashboard_path, alert: "❌ Training failed: #{result[:error]}"
      end
    end

    def metrics
      @entity = current_entity
      @days = (params[:days] || 30).to_i
      @config = @entity.agent_lightning_config

      @traces = @entity.agent_lightning_traces.where("created_at > ?", @days.days.ago)

      if @traces.empty?
        redirect_to admin_agent_lightning_dashboard_path, alert: "No traces found in the last #{@days} days"
        return
      end

      # Overall Stats
      @total_traces = @traces.count
      @success_rate = ((@traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / @traces.count) * 100).round(1)
      @avg_reward = @traces.average(:reward_signal).round(2)

      # Token & Cost
      @total_tokens = @traces.sum(:token_count)
      @avg_tokens = @traces.average(:token_count).round(0)
      @total_cost = @traces.sum(:cost_estimate).round(2)
      @avg_cost = @traces.average(:cost_estimate).round(4)

      # Performance
      @total_duration_minutes = (@traces.sum(:duration_ms) / 1000 / 60).round(1)
      @avg_duration = @traces.average(:duration_ms).round(0)
      @min_duration = @traces.minimum(:duration_ms)
      @max_duration = @traces.maximum(:duration_ms)

      # LLM Analysis
      @llm_calls = @entity.agent_llm_calls.where("called_at > ?", @days.days.ago)
      if @llm_calls.any?
        @llm_success_rate = ((@llm_calls.count { |c| c.status == 'success' }.to_f / @llm_calls.count) * 100).round(1)
        @avg_latency = @llm_calls.average(:latency_ms).round(0)
        @llm_by_role = @llm_calls.group_by(&:agent_role).map do |role, calls|
          {
            role: role,
            count: calls.count,
            success_rate: ((calls.count { |c| c.status == 'success' }.to_f / calls.count) * 100).round(1),
            avg_tokens: calls.average(:total_tokens).round(0),
            total_cost: calls.sum(:cost).round(4)
          }
        end
      end

      # Tool Analysis
      @tool_executions = @entity.agent_tool_executions.where("started_at > ?", @days.days.ago)
      if @tool_executions.any?
        @tool_success_rate = ((@tool_executions.count { |e| e.status == 'success' }.to_f / @tool_executions.count) * 100).round(1)
        @top_tools = @tool_executions.group_by(&:tool_name)
          .map { |tool, execs|
            {
              name: tool,
              count: execs.count,
              success_rate: ((execs.count { |e| e.status == 'success' }.to_f / execs.count) * 100).round(1),
              avg_time: execs.average(:execution_time_ms).round(0)
            }
          }
          .sort_by { |t| t[:count] }
          .reverse
          .first(10)
      end
    end

    def training_history
      @entity = current_entity
      @training_jobs = @entity.agent_training_jobs.order(completed_at: :desc).page(params[:page]).per(20)
    end

    def export_data
      @entity = current_entity
      service = AgentLightningTrainingService.new(@entity)
      training_data = service.get_training_data

      export = {
        entity_name: @entity.name,
        entity_id: @entity.id,
        exported_at: Time.current.iso8601,
        total_traces: training_data.count,
        traces: training_data
      }

      send_data JSON.pretty_generate(export),
        filename: "agent_lightning_training_data_#{@entity.id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json",
        type: 'application/json'
    end

    private

    def check_admin_access
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied"
      end
    end

    def create_default_config
      current_entity.create_agent_lightning_config!(
        enabled: true,
        mode: "observing",
        training_strategy: "prompt_optimization",
        retrain_frequency_hours: 24,
        trace_retention_days: 90,
        min_traces_for_training: 100,
        optimization_targets: {
          "reduce_token_usage" => 0.3,
          "improve_success_rate" => 0.5,
          "reduce_latency" => 0.2
        },
        learning_parameters: {
          "learning_rate" => 0.001,
          "batch_size" => 32,
          "num_epochs" => 3
        }
      )
    end
  end
end
