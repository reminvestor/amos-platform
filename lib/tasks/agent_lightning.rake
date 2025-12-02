namespace :agent_lightning do
  desc "Show Agent Lightning status for an entity"
  task :status, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id
    raise "Usage: rake agent_lightning:status[entity_id]" unless entity_id

    entity = Entity.find(entity_id)
    config = entity.agent_lightning_config

    puts "\n" + "="*70
    puts "🔬 AGENT LIGHTNING STATUS - #{entity.name}"
    puts "="*70

    # Configuration
    puts "\n📋 CONFIGURATION:"
    puts "  Enabled:               #{config.enabled? ? '✅ Yes' : '❌ No'}"
    puts "  Mode:                  #{config.mode}"
    puts "  Training Strategy:     #{config.training_strategy}"
    puts "  Retrain Every:         #{config.retrain_frequency_hours} hours"
    puts "  Last Training:         #{config.last_training_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never'}"
    puts "  Next Training:         #{config.should_retrain? ? 'Ready now!' : (config.last_training_at + config.retrain_frequency_hours.hours).strftime('%Y-%m-%d %H:%M:%S')}"

    # Trace Data
    traces = entity.agent_lightning_traces
    puts "\n📊 TRACE DATA:"
    puts "  Total Traces:          #{traces.count}"
    puts "  Completed:             #{traces.where(status: 'completed').count}"
    puts "  Failed:                #{traces.where(status: 'failed').count}"
    puts "  With Rewards:          #{traces.with_reward.count}"
    puts "  Ready for Training:    #{traces.where(included_in_training: false).with_reward.count}"

    # Recent Metrics
    recent = traces.recent.limit(100)
    if recent.any?
      puts "\n📈 RECENT METRICS (Last 100 traces):"
      puts "  Avg Success Rate:      #{(recent.count { |t| t.reward_signal > 0.7 }.to_f / recent.count * 100).round(1)}%"
      puts "  Avg Tokens/Trace:      #{recent.average(:token_count).round(0)}"
      puts "  Avg Cost/Trace:        $#{recent.average(:cost_estimate).round(4)}"
      puts "  Avg Duration:          #{recent.average(:duration_ms).round(0)}ms"
      puts "  Total Cost:            $#{recent.sum(:cost_estimate).round(2)}"
    end

    # Training Jobs
    puts "\n🚀 TRAINING HISTORY:"
    jobs = entity.agent_training_jobs.completed.recent.limit(5)
    if jobs.any?
      jobs.each do |job|
        puts "  #{job.completed_at.strftime('%Y-%m-%d %H:%M')} - #{job.job_type}: +#{job.improvement_score}% improvement (#{job.traces_used} traces)"
      end
    else
      puts "  No training jobs completed yet"
    end

    # Readiness Check
    puts "\n✅ TRAINING READINESS:"
    puts "  Enough Traces?         #{traces.with_reward.count >= config.min_traces_for_training ? '✅ Yes' : "❌ Need #{config.min_traces_for_training - traces.with_reward.count} more"}"
    puts "  Retrain Due?           #{config.should_retrain? ? '✅ Yes' : '⏳ Not yet'}"
    puts "  Can Train Now?         #{config.ready_for_training? ? '✅ Yes' : '❌ No'}"

    puts "\n" + "="*70 + "\n"
  end

  desc "Run Agent Lightning training for an entity"
  task :train, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id
    raise "Usage: rake agent_lightning:train[entity_id]" unless entity_id

    entity = Entity.find(entity_id)
    puts "\n🚀 Starting Agent Lightning training for #{entity.name}..."

    service = AgentLightningTrainingService.new(entity)

    unless service.config.ready_for_training?
      puts "❌ Not ready for training:"
      puts "   - Available traces with rewards: #{entity.agent_lightning_traces.with_reward.count}"
      puts "   - Minimum required: #{service.config.min_traces_for_training}"
      return
    end

    start_time = Time.current
    result = service.execute_training

    if result[:success]
      duration = (Time.current - start_time).round(1)
      puts "✅ Training completed successfully!"
      puts "   Job ID:         #{result[:job_id]}"
      puts "   Traces Used:    #{result[:traces_used]}"
      puts "   Improvement:    +#{result[:improvement]}%"
      puts "   Duration:       #{duration}s"
      puts "   Metrics:"
      result[:metrics].each do |key, value|
        puts "     - #{key}: #{value}"
      end
    else
      puts "❌ Training failed: #{result[:error]}"
    end
    puts ""
  end

  desc "Show Agent Lightning metrics for an entity"
  task :metrics, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id
    days = ENV['days']&.to_i || 30
    raise "Usage: rake agent_lightning:metrics[entity_id]" unless entity_id

    entity = Entity.find(entity_id)
    traces = entity.agent_lightning_traces.where("created_at > ?", days.days.ago)

    puts "\n" + "="*70
    puts "📊 AGENT LIGHTNING METRICS - #{entity.name} (Last #{days} days)"
    puts "="*70

    if traces.empty?
      puts "\nNo traces found in the last #{days} days"
      puts "="*70 + "\n"
      return
    end

    # Overall Stats
    puts "\n📈 OVERALL STATISTICS:"
    puts "  Total Traces:          #{traces.count}"
    puts "  Success Rate:          #{(traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / traces.count * 100).round(1)}%"
    puts "  Avg Reward Signal:     #{traces.average(:reward_signal).round(2)}"

    # Token & Cost Analysis
    puts "\n💰 TOKEN & COST ANALYSIS:"
    puts "  Total Tokens Used:     #{traces.sum(:token_count)}"
    puts "  Avg Tokens/Trace:      #{traces.average(:token_count).round(0)}"
    puts "  Total Cost:            $#{traces.sum(:cost_estimate).round(2)}"
    puts "  Avg Cost/Trace:        $#{traces.average(:cost_estimate).round(4)}"

    # Performance Analysis
    puts "\n⚡ PERFORMANCE ANALYSIS:"
    puts "  Total Duration:        #{(traces.sum(:duration_ms) / 1000 / 60).round(1)} minutes"
    puts "  Avg Duration/Trace:    #{traces.average(:duration_ms).round(0)}ms"
    puts "  Min Duration:          #{traces.minimum(:duration_ms)}ms"
    puts "  Max Duration:          #{traces.maximum(:duration_ms)}ms"

    # LLM Call Analysis
    llm_calls = entity.agent_llm_calls.where("called_at > ?", days.days.ago)
    if llm_calls.any?
      puts "\n🤖 LLM CALL ANALYSIS:"
      puts "  Total Calls:           #{llm_calls.count}"
      puts "  Success Rate:          #{(llm_calls.count { |c| c.status == 'success' }.to_f / llm_calls.count * 100).round(1)}%"
      puts "  Avg Latency:           #{llm_calls.average(:latency_ms).round(0)}ms"

      by_role = llm_calls.group_by(&:agent_role)
      puts "\n  By Agent Role:"
      by_role.each do |role, calls|
        puts "    #{role.capitalize}:"
        puts "      - Count:      #{calls.count}"
        puts "      - Avg Tokens: #{calls.average(:total_tokens).round(0)}"
        puts "      - Total Cost: $#{calls.sum(:cost).round(4)}"
      end
    end

    # Tool Analysis
    tool_execs = entity.agent_tool_executions.where("started_at > ?", days.days.ago)
    if tool_execs.any?
      puts "\n🔧 TOOL EXECUTION ANALYSIS:"
      puts "  Total Executions:      #{tool_execs.count}"
      puts "  Success Rate:          #{(tool_execs.count { |e| e.status == 'success' }.to_f / tool_execs.count * 100).round(1)}%"
      puts "  Avg Execution Time:    #{tool_execs.average(:execution_time_ms).round(0)}ms"

      by_tool = tool_execs.group_by(&:tool_name).sort_by { |_, execs| execs.count }.reverse.first(5)
      puts "\n  Top 5 Tools:"
      by_tool.each do |tool_name, execs|
        success_rate = (execs.count { |e| e.status == 'success' }.to_f / execs.count * 100).round(1)
        puts "    #{tool_name}: #{execs.count} calls, #{success_rate}% success"
      end
    end

    # Reward Analysis
    rewards = entity.agent_rewards.where("assigned_at > ?", days.days.ago)
    if rewards.any?
      puts "\n🏆 REWARD ANALYSIS:"
      by_type = rewards.group_by(&:reward_type)
      by_type.each do |type, type_rewards|
        puts "  #{type.capitalize}:"
        puts "    - Count:     #{type_rewards.count}"
        puts "    - Avg Value: #{type_rewards.average(:reward_value).round(2)}"
        puts "    - Min:       #{type_rewards.minimum(:reward_value).round(2)}"
        puts "    - Max:       #{type_rewards.maximum(:reward_value).round(2)}"
      end
    end

    puts "\n" + "="*70 + "\n"
  end

  desc "Export Agent Lightning training data for an entity"
  task :export_training_data, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id
    output_file = ENV['output'] || "agent_lightning_training_data_#{entity_id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    raise "Usage: rake agent_lightning:export_training_data[entity_id]" unless entity_id

    entity = Entity.find(entity_id)
    puts "\n📤 Exporting Agent Lightning training data for #{entity.name}..."

    service = AgentLightningTrainingService.new(entity)
    training_data = service.get_training_data

    export = {
      entity_name: entity.name,
      entity_id: entity.id,
      exported_at: Time.current.iso8601,
      total_traces: training_data.count,
      traces: training_data
    }

    File.write(output_file, JSON.pretty_generate(export))
    puts "✅ Exported #{training_data.count} traces to #{output_file}"
    puts "   File size: #{File.size(output_file) / 1024.0 / 1024.0}MB"
    puts ""
  end

  desc "Setup Agent Lightning for an entity (interactive)"
  task :setup_entity, [:entity_id] => :environment do |t, args|
    entity_id = args.entity_id
    raise "Usage: rake agent_lightning:setup_entity[entity_id]" unless entity_id

    entity = Entity.find(entity_id)

    puts "\n" + "="*70
    puts "🔧 AGENT LIGHTNING SETUP - #{entity.name}"
    puts "="*70

    if entity.agent_lightning_config
      puts "\n⚠️  Agent Lightning already configured for this entity"
      puts "Current settings:"
      puts "  - Enabled: #{entity.agent_lightning_config.enabled}"
      puts "  - Mode: #{entity.agent_lightning_config.mode}"
      puts "\nTo reconfigure, delete the existing config first."
      return
    end

    puts "\nConfiguring Agent Lightning for #{entity.name}..."

    config = entity.create_agent_lightning_config!(
      enabled: true,
      mode: "optimizing",
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

    puts "\n✅ Agent Lightning configured successfully!"
    puts "\nConfiguration:"
    puts "  - Enabled:              #{config.enabled}"
    puts "  - Mode:                 #{config.mode}"
    puts "  - Training Strategy:    #{config.training_strategy}"
    puts "  - Retrain Every:        #{config.retrain_frequency_hours} hours"
    puts "  - Trace Retention:      #{config.trace_retention_days} days"
    puts "  - Min Traces Required:  #{config.min_traces_for_training}"
    puts "\n📌 Next Steps:"
    puts "  1. Ensure BedrockService receives user and entity parameters"
    puts "  2. Deploy your application"
    puts "  3. Monitor status: rake agent_lightning:status[#{entity_id}]"
    puts "  4. Check metrics: rake agent_lightning:metrics[#{entity_id}]"
    puts "\n" + "="*70 + "\n"
  end

  desc "Cleanup old Agent Lightning traces"
  task :cleanup, [:days] => :environment do |t, args|
    days = (args.days || 90).to_i
    puts "\n🧹 Cleaning up Agent Lightning traces older than #{days} days..."

    deleted = AgentLightningTrace.where("created_at < ?", days.days.ago).delete_all
    puts "✅ Deleted #{deleted} old traces"
    puts ""
  end
end
