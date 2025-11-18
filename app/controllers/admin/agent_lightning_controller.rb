module Admin
  class AgentLightningController < Admin::BaseController

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

        {
          entity: entity,
          config: config,
          total_traces: traces.count,
          success_rate: traces.any? ? ((traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / traces.count) * 100).round(1) : 0,
          total_cost: traces.sum(:cost_estimate).round(2),
          total_tokens: traces.sum(:token_count),
          last_trace_at: traces.maximum(:created_at),
          enabled: config&.enabled? || false,
          ready_for_training: config&.ready_for_training? || false
        }
      end.sort_by { |s| s[:total_traces] }.reverse

      # Platform-wide cost savings (placeholder - TODO: implement cost savings calculation)
      @total_monthly_savings = 0
      @entities_with_savings = 0

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

# Platform-wide training job health metrics
all_training_jobs = AgentTrainingJob.all
@total_training_jobs = all_training_jobs.count
@successful_training_jobs = all_training_jobs.where(status: 'completed').count
@failed_training_jobs = all_training_jobs.where(status: 'failed').count
@training_success_rate = @total_training_jobs > 0 ? ((@successful_training_jobs.to_f / @total_training_jobs) * 100).round(1) : 0

# Last training status
last_job = all_training_jobs.order(created_at: :desc).first
@last_training_status = last_job&.status
@last_training_at = last_job&.completed_at || last_job&.created_at

# Calculate platform-wide improvement trend (placeholder - TODO: implement)
@improvement_trend = nil
@last_improvement = recent_successful_jobs = all_training_jobs.where(status: 'completed').order(completed_at: :desc).limit(1).first&.improvement_score&.round(2)

# Calculate traces available for training (across all entities)
@total_available_traces = all_entities.sum do |entity|
  next 0 unless entity.agent_lightning_config&.enabled?
  traces = entity.agent_lightning_traces.where("created_at > ?", 30.days.ago)
  traces.where(status: ['completed', 'failed'], included_in_training: false)
        .where.not(reward_signal: nil).count
end

      # Additional trace statistics
      @recent_traces = all_traces
      @completed_traces = AgentLightningTrace.where(status: 'completed').count
      @failed_traces = AgentLightningTrace.where(status: 'failed').count
      @traces_with_rewards = AgentLightningTrace.where.not(reward_signal: nil).count
      @avg_duration = all_traces.average(:duration_ms)&.round(0) || 0

      # Last training job details
      @last_training_job = all_training_jobs.where(status: 'completed').order(completed_at: :desc).first
      @recommendations = @last_training_job&.recommendations || []

      # Training history
      @training_history = all_training_jobs.where(status: 'completed').order(completed_at: :desc).limit(10)

      # LLM call analysis (platform-wide)
      @llm_calls = AgentLightningTrace.where("created_at > ?", 30.days.ago).limit(500)

      # Group by agent role (extract from context if available)
      @llm_by_role = []
      role_stats = {}

      @llm_calls.each do |trace|
        role = trace.agent_role || 'unknown'
        role_stats[role] ||= { count: 0, successful: 0, total_tokens: 0, total_cost: 0 }
        role_stats[role][:count] += 1
        role_stats[role][:successful] += 1 if trace.status == 'completed'
        role_stats[role][:total_tokens] += trace.token_count || 0
        role_stats[role][:total_cost] += trace.cost_estimate || 0
      end

      @llm_by_role = role_stats.map do |role, stats|
        {
          role: role,
          count: stats[:count],
          success_rate: ((stats[:successful].to_f / stats[:count]) * 100).round(1),
          avg_tokens: (stats[:total_tokens].to_f / stats[:count]).round(0),
          total_cost: stats[:total_cost].round(4)
        }
      end.sort_by { |r| r[:count] }.reverse

      # Tool execution analysis (extract from intermediate_steps)
      tool_data = {}
      @llm_calls.each do |trace|
        next unless trace.intermediate_steps.is_a?(Array)

        trace.intermediate_steps.each do |step|
          tool_name = step['tool'] || step[:tool]
          next unless tool_name

          tool_data[tool_name] ||= { count: 0, successes: 0 }
          tool_data[tool_name][:count] += 1
          tool_data[tool_name][:successes] += 1 if step['status'] == 'success' || step[:status] == 'success'
        end
      end

      if tool_data.any?
        @top_tools = tool_data.map do |name, data|
          {
            name: name,
            count: data[:count],
            success_rate: ((data[:successes].to_f / data[:count]) * 100).round(1)
          }
        end.sort_by { |t| t[:count] }.reverse.first(10)

        total_tool_calls = tool_data.values.sum { |d| d[:count] }
        total_successes = tool_data.values.sum { |d| d[:successes] }
        @tool_success_rate = ((total_successes.to_f / total_tool_calls) * 100).round(1)
      else
        @top_tools = []
        @tool_success_rate = 0
      end
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

    def models_performance
      # Analyze performance by AI model across all entities or for a specific entity
      entity_id = params[:entity_id]
      time_range = params[:time_range]&.to_i&.days&.ago || 30.days.ago

      # Get all LLM calls in the time range
      base_scope = AgentLlmCall.where("called_at > ?", time_range)
      base_scope = base_scope.where(entity_id: entity_id) if entity_id.present?

      # Group by model to get performance metrics
      model_stats = base_scope.group(:model).select(
        'model',
        'COUNT(*) as total_calls',
        'AVG(latency_ms) as avg_latency',
        'AVG(total_tokens) as avg_tokens',
        'SUM(cost) as total_cost',
        'AVG(cost) as avg_cost',
        'SUM(CASE WHEN status = \'success\' THEN 1 ELSE 0 END) as successful_calls'
      ).map do |stat|
        success_rate = stat.total_calls > 0 ? (stat.successful_calls.to_f / stat.total_calls * 100).round(1) : 0

        {
          model: stat.model,
          display_name: format_model_name(stat.model),
          total_calls: stat.total_calls,
          success_rate: success_rate,
          avg_latency: stat.avg_latency&.round(0) || 0,
          avg_tokens: stat.avg_tokens&.round(0) || 0,
          avg_cost: stat.avg_cost&.round(4) || 0.0,
          total_cost: stat.total_cost&.round(2) || 0.0
        }
      end.sort_by { |s| s[:total_calls] }.reverse

      @model_stats = model_stats

      # Per-entity breakdown for each model
      if entity_id.blank?
        @entity_breakdown = {}
        model_stats.each do |model_stat|
          model = model_stat[:model]

          entity_data = base_scope.where(model: model).group(:entity_id).select(
            'entity_id',
            'COUNT(*) as calls',
            'AVG(latency_ms) as latency',
            'SUM(cost) as cost'
          ).map do |ed|
            entity = Entity.find(ed.entity_id)
            {
              entity_name: entity.name,
              entity_id: ed.entity_id,
              calls: ed.calls,
              avg_latency: ed.latency&.round(0) || 0,
              total_cost: ed.cost&.round(2) || 0.0
            }
          end.sort_by { |e| e[:calls] }.reverse.first(10)

          @entity_breakdown[model] = entity_data
        end
      end

      # Overall platform stats
      @total_llm_calls = base_scope.count
      @overall_success_rate = base_scope.where(status: 'success').count.to_f / [@total_llm_calls, 1].max * 100
      @overall_success_rate = @overall_success_rate.round(1)
      @total_platform_cost = base_scope.sum(:cost).round(2)

      # Time range options for filter
      @time_range_days = (Time.current - time_range).to_i / 1.day.to_i

      # Entity options for filter
      @entities = Entity.joins(:agent_llm_calls).distinct.order(:name)
      @selected_entity_id = entity_id

      # Generate charts data
      @token_usage_chart = generate_token_usage_chart(base_scope, time_range)
      @cost_chart = generate_cost_chart(base_scope, time_range)
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

    def format_model_name(model_id)
      case model_id
      when /sonnet-4-5/
        'Claude Sonnet 4.5'
      when /opus-4/
        'Claude Opus 4'
      when /3-5-sonnet/
        'Claude 3.5 Sonnet'
      when /haiku/
        'Claude Haiku'
      when /gpt-4/
        'GPT-4'
      when /gpt-3/
        'GPT-3.5'
      else
        model_id.to_s.split('.').last&.titleize || 'Unknown Model'
      end
    end

    def generate_token_usage_chart(scope, time_range)
      # Determine grouping based on time range
      days_diff = (Time.current - time_range).to_i / 1.day.to_i
      group_by = days_diff <= 1 ? 'hour' : 'day'

      time_groups = case group_by
      when "hour"
        24.times.map { |h| h.hours.ago.beginning_of_hour }
      else
        days_diff.times.map { |d| d.days.ago.beginning_of_day }
      end

      # Use database aggregation
      input_tokens_by_time = scope
        .group("DATE_TRUNC('#{group_by}', called_at)")
        .sum(:input_tokens)

      output_tokens_by_time = scope
        .group("DATE_TRUNC('#{group_by}', called_at)")
        .sum(:output_tokens)

      {
        labels: time_groups.reverse.map { |t| format_time_label(t, group_by) },
        datasets: [
          {
            label: "Input Tokens",
            data: time_groups.reverse.map { |time| input_tokens_by_time[time] || 0 },
            backgroundColor: "rgba(59, 130, 246, 0.5)"
          },
          {
            label: "Output Tokens",
            data: time_groups.reverse.map { |time| output_tokens_by_time[time] || 0 },
            backgroundColor: "rgba(16, 185, 129, 0.5)"
          }
        ]
      }
    end

    def generate_cost_chart(scope, time_range)
      # Determine grouping based on time range
      days_diff = (Time.current - time_range).to_i / 1.day.to_i
      group_by = days_diff <= 1 ? 'hour' : 'day'

      time_groups = case group_by
      when "hour"
        24.times.map { |h| h.hours.ago.beginning_of_hour }
      else
        days_diff.times.map { |d| d.days.ago.beginning_of_day }
      end

      # Use database aggregation
      cost_by_time = scope
        .group("DATE_TRUNC('#{group_by}', called_at)")
        .sum(:cost)

      {
        labels: time_groups.reverse.map { |t| format_time_label(t, group_by) },
        datasets: [
          {
            label: "Cost ($)",
            data: time_groups.reverse.map { |time| (cost_by_time[time] || 0).round(2) },
            borderColor: "rgb(239, 68, 68)",
            backgroundColor: "rgba(239, 68, 68, 0.1)",
            fill: true
          }
        ]
      }
    end

    def format_time_label(time, group_by)
      case group_by
      when "hour"
        time.strftime("%-l %p")
      else
        time.strftime("%b %-d")
      end
    end

  end

end
