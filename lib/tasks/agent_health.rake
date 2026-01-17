# frozen_string_literal: true

namespace :agents do
  desc "Check for stale/stuck agent executions and clean them up"
  task check_stale: :environment do
    puts "🔍 Checking for stale agent executions..."
    
    # Stale running executions (running > 30 min)
    stale_running = AgentPluginExecution.where(status: 'running')
      .where('started_at < ?', 30.minutes.ago)
    
    puts "Found #{stale_running.count} stale running executions"
    
    stale_running.find_each do |exec|
      puts "  ⚠️ Marking stale: #{exec.id} (agent: #{exec.agent_plugin&.slug})"
      
      # Mark as failed
      exec.mark_failed!("Execution timed out after 30 minutes")
      
      # Create work item for user visibility
      if exec.user && exec.agent_plugin
        AgentWorkItem.create!(
          entity: exec.agent_plugin.entity,
          user: exec.user,
          agent_plugin: exec.agent_plugin,
          agent_plugin_execution: exec,
          work_type: 'error',
          title: "Task timed out: #{exec.input_context&.dig('task')&.truncate(50) || 'Unknown task'}",
          description: "This task was running for too long and was automatically stopped. You may need to retry or break it into smaller steps.",
          priority: 'high',
          status: 'pending'
        )
      end
    end
    
    # Stale waiting_for_input (waiting > 24 hours)
    stale_waiting = AgentPluginExecution.where(status: 'waiting_for_input')
      .where('updated_at < ?', 24.hours.ago)
    
    puts "Found #{stale_waiting.count} stale waiting-for-input executions"
    
    stale_waiting.find_each do |exec|
      puts "  ⚠️ Expiring wait: #{exec.id}"
      
      # Expire any pending input requests
      exec.agent_input_requests.pending.each do |req|
        req.expire!
      end
      
      exec.mark_failed!("User response timeout after 24 hours")
    end
    
    # Cleanup stuck scheduled task runs
    stuck_count = ScheduledTaskRun.cleanup_stuck_runs!
    puts "Cleaned up #{stuck_count} stuck scheduled task runs"
    
    # Check for orphaned collaboration requests
    orphaned = AgentCollaborationRequest.pending
      .where('timeout_at < ?', Time.current)
    
    puts "Found #{orphaned.count} expired collaboration requests"
    
    orphaned.find_each do |req|
      puts "  ⚠️ Expiring collaboration: #{req.id}"
      req.expire!
    end
    
    puts "✅ Agent health check complete"
  end
  
  desc "Show agent execution health dashboard"
  task health_dashboard: :environment do
    puts "\n" + "=" * 60
    puts "🤖 AGENT HEALTH DASHBOARD"
    puts "=" * 60
    
    # Execution stats (last 24h)
    executions = AgentPluginExecution.where('created_at > ?', 24.hours.ago)
    
    puts "\n📊 Last 24 Hours:"
    puts "  Total executions: #{executions.count}"
    puts "  Completed: #{executions.where(status: 'completed').count}"
    puts "  Failed: #{executions.where(status: 'failed').count}"
    puts "  Running: #{executions.where(status: 'running').count}"
    puts "  Waiting for input: #{executions.where(status: 'waiting_for_input').count}"
    
    # Success rate
    completed = executions.where(status: %w[completed failed])
    if completed.any?
      success_rate = (executions.where(status: 'completed').count.to_f / completed.count * 100).round(1)
      puts "  Success rate: #{success_rate}%"
    end
    
    # Avg execution time
    completed_with_duration = executions.where(status: 'completed').where.not(duration_ms: nil)
    if completed_with_duration.any?
      avg_duration = completed_with_duration.average(:duration_ms).to_f / 1000
      puts "  Avg execution time: #{avg_duration.round(1)}s"
    end
    
    # Task proposals
    puts "\n🤝 Task Proposals (last 24h):"
    proposals = AgentTaskProposal.where('created_at > ?', 24.hours.ago)
    puts "  Total: #{proposals.count}"
    puts "  Accepted: #{proposals.accepted.count}"
    puts "  Rejected: #{proposals.rejected.count}"
    
    if proposals.any?
      acceptance_rate = (proposals.accepted.count.to_f / proposals.count * 100).round(1)
      puts "  Acceptance rate: #{acceptance_rate}%"
    end
    
    # Collaboration requests
    puts "\n🔄 Collaboration Requests (last 24h):"
    collabs = AgentCollaborationRequest.where('created_at > ?', 24.hours.ago)
    puts "  Total: #{collabs.count}"
    puts "  Completed: #{collabs.completed.count}"
    puts "  Pending: #{collabs.pending.count}"
    
    # Pending work items
    puts "\n📋 Pending Work Items:"
    pending_work = AgentWorkItem.where(status: 'pending')
    puts "  Total pending: #{pending_work.count}"
    puts "  High priority: #{pending_work.where(priority: %w[high urgent]).count}"
    
    # Pending questions
    puts "\n❓ Pending Agent Questions:"
    pending_questions = AgentInputRequest.where(status: 'pending')
    puts "  Total pending: #{pending_questions.count}"
    puts "  Expired: #{pending_questions.where('expires_at < ?', Time.current).count}"
    
    puts "\n" + "=" * 60
  end
  
  desc "Ensure all running executions have Hub threads"
  task ensure_hub_threads: :environment do
    puts "🔗 Ensuring Hub threads for running executions..."
    
    running = AgentPluginExecution.where(status: %w[running waiting_for_input])
      .where(hub_thread_id: nil)
    
    puts "Found #{running.count} executions without Hub threads"
    
    running.find_each do |exec|
      next unless exec.agent_plugin && exec.user
      
      thread = HubThread.find_or_create_dm(
        entity: exec.agent_plugin.entity,
        participants: [exec.user, exec.agent_plugin]
      )
      
      exec.update!(hub_thread_id: thread.id)
      puts "  ✅ Created thread #{thread.id} for execution #{exec.id}"
    end
    
    puts "✅ Hub thread check complete"
  end
end

