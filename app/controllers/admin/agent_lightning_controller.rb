module Admin
  class AgentLightningController < ApplicationController
    before_action :check_admin_access

    def dashboard
      # Platform-wide stats across all entities
      all_entities = Entity.includes(:agent_lightning_config).all

      # Overall platform stats
      @total_traces = AgentLightningTrace.count
      @total_entities = all_entities.count
      @entities_with_lightning = all_entities.select { |e| e.agent_lightning_config.present? }.count

      # Aggregate metrics
      all_traces = AgentLightningTrace.where("created_at > ?", 30.days.ago)
      if all_traces.any?
        @success_rate = ((all_traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / all_traces.count) * 100).round(1)
        @avg_tokens = all_traces.average(:token_count)&.round(0) || 0
        @avg_cost = all_traces.average(:cost_estimate)&.round(4) || 0.0
        @total_cost = all_traces.sum(:cost_estimate).round(2)
      else
        @success_rate = 0
        @avg_tokens = 0
        @avg_cost = 0.0
        @total_cost = 0.0
      end

      # Per-entity breakdown (calculate for all entities for totals)
      all_entity_stats = all_entities.map do |entity|
        config = entity.agent_lightning_config
        traces = entity.agent_lightning_traces.where("created_at > ?", 30.days.ago)
        cost_savings = config&.cost_savings

        {
          entity: entity,
          config: config,
          total_traces: traces.count,
          success_rate: traces.any? ? ((traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / traces.count) * 100).round(1) : 0,
          total_cost: traces.sum(:cost_estimate).round(2),
          total_tokens: traces.sum(:token_count),
          last_trace_at: traces.maximum(:created_at),
          enabled: config&.enabled? || false,
          ready_for_training: config&.ready_for_training? || false,
          cost_savings: cost_savings
        }
      end.sort_by { |s| s[:total_traces] }.reverse

      # Platform-wide cost savings
      @total_monthly_savings = all_entity_stats.sum { |s| s[:cost_savings]&.dig(:estimated_monthly_savings) || 0 }
      @entities_with_savings = all_entity_stats.count { |s| s[:cost_savings].present? }

      # Platform-wide trace analysis (using traces since detailed LLM calls don't exist yet)
      recent_traces = AgentLightningTrace.where("created_at > ?", 30.days.ago)
      if recent_traces.any?
        @llm_success_rate = ((recent_traces.where(status: 'completed').count.to_f / recent_traces.count) * 100).round(1)
        @avg_latency = recent_traces.average(:duration_ms)&.round(0) || 0

        # Get model breakdown for latency
        @model_latencies = recent_traces
          .where.not(model_used: nil)
          .group(:model_used)
          .average(:duration_ms)
          .transform_values { |v| v&.round(0) || 0 }
          .sort_by { |k, v| v }
          .reverse
      else
        @llm_success_rate = 0
        @avg_latency = 0
        @model_latencies = {}
      end

      # Paginate entity stats for table display (15 per page)
      page = params[:page].to_i
      page = 1 if page < 1
      per_page = 15
      start_index = (page - 1) * per_page
      end_index = start_index + per_page - 1

      paginated_stats = all_entity_stats[start_index..end_index] || []

      # Create a paginated array wrapper for Kaminari
      @entity_stats = Kaminari.paginate_array(all_entity_stats, total_count: all_entity_stats.length)
                              .page(page)
                              .per(per_page)

      # Recent training jobs across all entities
      @recent_training_jobs = AgentTrainingJob.includes(:entity).completed.order(completed_at: :desc).limit(10)
    end

    def train_now
      @entity = Entity.find(params[:entity_id])
      service = AgentLightningTrainingService.new(@entity)

      unless service.config&.ready_for_training?
        redirect_to dashboard_admin_agent_lightning_index_path, alert: "Entity not ready for training. Check status page."
        return
      end

      result = service.execute_training

      if result[:success]
        redirect_to dashboard_admin_agent_lightning_index_path, notice: "✅ Training completed for #{@entity.name}! Improvement: +#{result[:improvement]}%"
      else
        redirect_to dashboard_admin_agent_lightning_index_path, alert: "❌ Training failed for #{@entity.name}: #{result[:error]}"
      end
    end

    def train_all
      # Find all entities ready for training
      ready_entities = Entity.includes(:agent_lightning_config).select do |entity|
        entity.agent_lightning_config&.ready_for_training?
      end

      if ready_entities.empty?
        redirect_to dashboard_admin_agent_lightning_index_path, alert: "No entities are ready for training yet."
        return
      end

      # Train each entity and collect results
      results = ready_entities.map do |entity|
        service = AgentLightningTrainingService.new(entity)
        result = service.execute_training
        { entity: entity, result: result }
      end

      # Build summary message
      successes = results.count { |r| r[:result][:success] }
      failures = results.count { |r| !r[:result][:success] }
      total_improvement = results.select { |r| r[:result][:success] }.sum { |r| r[:result][:improvement] || 0 }
      avg_improvement = successes > 0 ? (total_improvement / successes).round(1) : 0

      if successes > 0 && failures == 0
        redirect_to dashboard_admin_agent_lightning_index_path,
                    notice: "✅ Successfully trained #{successes} #{successes == 1 ? 'entity' : 'entities'}! Average improvement: +#{avg_improvement}%"
      elsif successes > 0 && failures > 0
        redirect_to dashboard_admin_agent_lightning_index_path,
                    notice: "⚡ Trained #{successes} entities (+#{avg_improvement}% avg), #{failures} failed. Check logs for details."
      else
        redirect_to dashboard_admin_agent_lightning_index_path,
                    alert: "❌ Training failed for all #{failures} entities. Check system logs."
      end
    end

    def metrics
      # Platform-wide metrics if no entity specified
      @days = (params[:days] || 30).to_i

      if params[:entity_id]
        # Entity-specific metrics
        @entity = Entity.find(params[:entity_id])
        @config = @entity.agent_lightning_config
        @traces = @entity.agent_lightning_traces.where("created_at > ?", @days.days.ago)
      else
        # Platform-wide metrics
        @entity = nil
        @traces = AgentLightningTrace.where("created_at > ?", @days.days.ago)
      end

      if @traces.empty?
        redirect_to dashboard_admin_agent_lightning_index_path, alert: "No traces found in the last #{@days} days"
        return
      end

      # Overall Stats
      @total_traces = @traces.count
      @success_rate = ((@traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / @traces.count) * 100).round(1)
      @avg_reward = @traces.average(:reward_signal)&.round(2) || 0
      @completed_traces_count = @traces.where(status: 'completed').count

      # Token & Cost
      @total_tokens = @traces.sum(:token_count)
      @avg_tokens = @traces.average(:token_count)&.round(0) || 0
      @total_cost = @traces.sum(:cost_estimate).round(2)
      @avg_cost = @traces.average(:cost_estimate)&.round(4) || 0.0

      # Performance
      @total_duration_minutes = (@traces.sum(:duration_ms) / 1000 / 60).round(1)
      @avg_duration = @traces.average(:duration_ms)&.round(0) || 0
      @min_duration = @traces.minimum(:duration_ms) || 0
      @max_duration = @traces.maximum(:duration_ms) || 0

      # Performance Distribution (for progress bar)
      @duration_distribution = {
        fast: (@traces.where('duration_ms < 1000').count.to_f / @total_traces * 100).round,
        medium: (@traces.where('duration_ms >= 1000 AND duration_ms < 5000').count.to_f / @total_traces * 100).round,
        slow: (@traces.where('duration_ms >= 5000 AND duration_ms < 10000').count.to_f / @total_traces * 100).round,
        very_slow: (@traces.where('duration_ms >= 10000').count.to_f / @total_traces * 100).round
      }

      # LLM Analysis (from trace-level data)
      completed_traces = @traces.where(status: 'completed')
      if completed_traces.any?
        @llm_success_rate = ((completed_traces.count.to_f / @traces.count) * 100).round(1)
        @avg_latency = @traces.average(:duration_ms)&.round(0) || 0
      else
        @llm_success_rate = 0
        @avg_latency = 0
      end

      # Tool Analysis (extract from intermediate_steps JSON)
      tool_data = {}
      @traces.each do |trace|
        next unless trace.intermediate_steps.is_a?(Array)

        trace.intermediate_steps.each do |step|
          tool_name = step['tool'] || step[:tool]
          next unless tool_name

          tool_data[tool_name] ||= { count: 0, successes: 0, total_time: 0 }
          tool_data[tool_name][:count] += 1
          tool_data[tool_name][:successes] += 1 if step['status'] == 'success' || step[:status] == 'success'
          tool_data[tool_name][:total_time] += (step['latency_ms'] || step[:latency_ms] || 0)
        end
      end

      if tool_data.any?
        @top_tools = tool_data.map do |name, data|
          {
            name: name,
            count: data[:count],
            success_rate: ((data[:successes].to_f / data[:count]) * 100).round(1),
            avg_time: (data[:total_time].to_f / data[:count]).round(0)
          }
        end.sort_by { |t| t[:count] }.reverse.first(10)

        total_tool_calls = tool_data.values.sum { |d| d[:count] }
        total_successes = tool_data.values.sum { |d| d[:successes] }
        @tool_success_rate = ((total_successes.to_f / total_tool_calls) * 100).round(1)
        @failed_tool_executions = total_tool_calls - total_successes
      else
        @top_tools = []
        @tool_success_rate = 0
        @failed_tool_executions = 0
      end
    end

    def training_history
      # Show all training jobs across all entities
      @training_jobs = AgentTrainingJob.includes(:entity).order(completed_at: :desc).page(params[:page]).per(20)
    end

    def export_data
      # Export platform-wide or entity-specific data
      if params[:entity_id]
        @entity = Entity.find(params[:entity_id])
        service = AgentLightningTrainingService.new(@entity)
        training_data = service.get_training_data

        export = {
          entity_name: @entity.name,
          entity_id: @entity.id,
          exported_at: Time.current.iso8601,
          total_traces: training_data.count,
          traces: training_data
        }

        filename = "agent_lightning_training_data_#{@entity.id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      else
        # Platform-wide export
        export = {
          platform: "all_entities",
          exported_at: Time.current.iso8601,
          entities: Entity.includes(:agent_lightning_traces).map do |entity|
            {
              entity_id: entity.id,
              entity_name: entity.name,
              total_traces: entity.agent_lightning_traces.count,
              config: entity.agent_lightning_config&.as_json
            }
          end
        }

        filename = "agent_lightning_platform_data_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      end

      send_data JSON.pretty_generate(export),
        filename: filename,
        type: 'application/json'
    end

    private

    def check_admin_access
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied"
      end
    end
  end
end
