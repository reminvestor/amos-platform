# frozen_string_literal: true

namespace :billing do
  desc "Diagnose token leaks for a specific user or entity"
  task :diagnose_leak, [:identifier] => :environment do |_, args|
    identifier = args[:identifier]
    
    unless identifier
      puts "Usage: rails billing:diagnose_leak[user_email_or_entity_id]"
      puts "Example: rails billing:diagnose_leak[user@example.com]"
      puts "Example: rails billing:diagnose_leak[123]"
      exit 1
    end
    
    # Find the user or entity
    user = User.find_by(email: identifier) || User.find_by(id: identifier)
    entity = Entity.find_by(id: identifier) if user.nil?
    
    if user
      puts "🔍 Analyzing billing for user: #{user.email} (ID: #{user.id})"
      billing_account = user.user_billing_account
      transactions = WorkTokenTransaction.where(user: user).order(created_at: :desc)
    elsif entity
      puts "🔍 Analyzing billing for entity: #{entity.name} (ID: #{entity.id})"
      billing_account = entity.entity_billing_account
      transactions = WorkTokenTransaction.where(entity: entity).order(created_at: :desc)
    else
      puts "❌ Could not find user or entity with identifier: #{identifier}"
      exit 1
    end
    
    puts "\n" + "=" * 80
    puts "BILLING ACCOUNT STATUS"
    puts "=" * 80
    if billing_account
      puts "Balance: #{billing_account.work_token_balance.to_i} tokens"
      puts "Lifetime used: #{billing_account.lifetime_tokens_used.to_i} tokens"
      puts "Last usage: #{billing_account.last_usage_at}"
    else
      puts "No billing account found!"
      exit 1
    end
    
    puts "\n" + "=" * 80
    puts "LAST 24 HOURS ANALYSIS"
    puts "=" * 80
    
    recent = transactions.where('created_at > ?', 24.hours.ago)
    puts "Total transactions: #{recent.count}"
    puts "Total tokens used: #{recent.debits.sum(:token_amount).abs.to_i}"
    
    # Group by hour
    puts "\n📊 Usage by hour:"
    hourly = recent.group_by { |t| t.created_at.beginning_of_hour }
    hourly.each do |hour, txs|
      count = txs.count
      tokens = txs.sum { |t| t.token_amount.abs }
      puts "  #{hour.strftime('%Y-%m-%d %H:00')}: #{count} transactions, #{tokens.to_i} tokens"
    end
    
    # Find rapid-fire transactions (same minute)
    puts "\n⚠️  Rapid-fire transactions (>5 per minute):"
    by_minute = recent.group_by { |t| t.created_at.beginning_of_minute }
    rapid_fire = by_minute.select { |_, txs| txs.count > 5 }
    if rapid_fire.empty?
      puts "  None found"
    else
      rapid_fire.each do |minute, txs|
        puts "  #{minute.strftime('%Y-%m-%d %H:%M')}: #{txs.count} transactions"
        # Show metadata of first few
        txs.first(3).each do |t|
          meta = t.metadata || {}
          puts "    - #{t.description}: model=#{meta['model']}, method=#{meta['method']}"
        end
      end
    end
    
    # Analyze by model
    puts "\n📊 Usage by model:"
    model_usage = recent.group_by { |t| t.metadata&.dig('model') || 'unknown' }
    model_usage.each do |model, txs|
      tokens = txs.sum { |t| t.token_amount.abs }
      puts "  #{model}: #{txs.count} calls, #{tokens.to_i} tokens"
    end
    
    # Analyze by method/source
    puts "\n📊 Usage by method:"
    method_usage = recent.group_by { |t| t.metadata&.dig('method') || 'unknown' }
    method_usage.each do |method, txs|
      tokens = txs.sum { |t| t.token_amount.abs }
      puts "  #{method}: #{txs.count} calls, #{tokens.to_i} tokens"
    end
    
    # Check for scheduled tasks
    puts "\n" + "=" * 80
    puts "SCHEDULED AGENT TASKS"
    puts "=" * 80
    
    tasks = if user
      ScheduledAgentTask.where(user: user).active
    else
      ScheduledAgentTask.where(entity: entity).active
    end
    
    if tasks.empty?
      puts "No active scheduled tasks"
    else
      puts "Active scheduled tasks:"
      tasks.each do |task|
        recent_runs = task.scheduled_task_runs.where('created_at > ?', 24.hours.ago).count
        puts "  - #{task.name} (#{task.schedule_type}): #{recent_runs} runs in last 24h"
        puts "    Next run: #{task.next_run_at}"
      end
    end
    
    # Check for agent plugin executions
    puts "\n" + "=" * 80
    puts "RECENT AGENT EXECUTIONS"
    puts "=" * 80
    
    executions = if user
      AgentPluginExecution.joins(:agent_plugin).where(user: user).where('agent_plugin_executions.created_at > ?', 24.hours.ago)
    else
      AgentPluginExecution.joins(:agent_plugin).where(entity: entity).where('agent_plugin_executions.created_at > ?', 24.hours.ago)
    end
    
    if executions.empty?
      puts "No agent executions in last 24 hours"
    else
      by_agent = executions.group_by(&:agent_plugin)
      by_agent.each do |agent, execs|
        puts "  #{agent&.name || 'Unknown'}: #{execs.count} executions"
        # Check for running ones
        running = execs.select { |e| e.status == 'running' }
        puts "    ⚠️  #{running.count} still running!" if running.any?
      end
    end
    
    # Check Living Platform activity
    puts "\n" + "=" * 80
    puts "LIVING PLATFORM ACTIVITY (last 24h)"
    puts "=" * 80
    
    lp_sources = %w[perception desire_engine metacognition evolution_cycle agent_reflection]
    lp_transactions = recent.select { |t| lp_sources.include?(t.metadata&.dig('source')) }
    
    if lp_transactions.empty?
      puts "No Living Platform activity detected"
    else
      by_source = lp_transactions.group_by { |t| t.metadata&.dig('source') }
      by_source.each do |source, txs|
        tokens = txs.sum { |t| t.token_amount.abs }
        puts "  #{source}: #{txs.count} calls, #{tokens.to_i} tokens"
      end
    end
    
    puts "\n" + "=" * 80
    puts "RECOMMENDATIONS"
    puts "=" * 80
    
    if rapid_fire.any?
      puts "⚠️  Rapid-fire transactions detected! Check for:"
      puts "   - Tool use loops (agent making many tool calls)"
      puts "   - Council Research (queries multiple models in parallel)"
      puts "   - WebSocket reconnection issues"
    end
    
    if method_usage['invoke_model_with_response_stream']&.count.to_i > 100
      puts "⚠️  High streaming request count - check for conversation loops"
    end
    
    if tasks.any? { |t| t.schedule_type == 'cron' }
      puts "⚠️  Cron-based scheduled tasks found - verify cron expressions"
    end
    
    puts "\nDone!"
  end
  
  desc "Pause all AI activity for a user (emergency stop)"
  task :pause_user, [:email] => :environment do |_, args|
    email = args[:email]
    user = User.find_by(email: email)
    
    unless user
      puts "User not found: #{email}"
      exit 1
    end
    
    puts "Pausing all AI activity for #{email}..."
    
    # Pause scheduled tasks
    paused_tasks = ScheduledAgentTask.where(user: user).active.update_all(enabled: false)
    puts "  Paused #{paused_tasks} scheduled tasks"
    
    # Cancel running agent executions
    running = AgentPluginExecution.where(user: user, status: 'running')
    running.each do |exec|
      exec.update(status: 'cancelled', error_message: 'Emergency pause by admin')
    end
    puts "  Cancelled #{running.count} running agent executions"
    
    puts "Done! User activity paused."
    puts "To resume, manually re-enable scheduled tasks or set enabled: true"
  end
end

