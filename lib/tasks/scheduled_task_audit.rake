# frozen_string_literal: true

namespace :billing do
  desc "Audit all users for runaway scheduled tasks and abnormal token usage"
  task audit_runaway_tasks: :environment do
    puts "=" * 80
    puts "🔍 SCHEDULED TASK AUDIT - Checking for runaway tasks and token leaks"
    puts "=" * 80
    puts ""

    issues_found = 0

    # 1. Users with excessive scheduled tasks (more than 50)
    puts "📋 Checking for users with excessive scheduled tasks..."
    excessive_tasks = ScheduledAgentTask
      .where(status: %w[active paused])
      .group(:user_id)
      .having("COUNT(*) > 50")
      .count

    if excessive_tasks.any?
      puts "⚠️  Found #{excessive_tasks.count} users with >50 scheduled tasks:"
      excessive_tasks.sort_by { |_, count| -count }.each do |user_id, count|
        user = User.find_by(id: user_id)
        puts "   - User #{user_id} (#{user&.email}): #{count} tasks"
        issues_found += 1
      end
    else
      puts "   ✅ No users with excessive scheduled tasks"
    end
    puts ""

    # 2. Users with duplicate-looking task names
    puts "📋 Checking for users with duplicate task names..."
    users_with_duplicates = []
    
    User.joins(:scheduled_agent_tasks)
        .where(scheduled_agent_tasks: { status: %w[active paused] })
        .distinct
        .find_each do |user|
      
      task_names = ScheduledAgentTask
        .where(user: user, status: %w[active paused])
        .pluck(:name)
      
      # Check for similar names (using first 20 chars)
      normalized_names = task_names.map { |n| n.downcase.gsub(/[^a-z0-9\s]/, '').first(30) }
      duplicates = normalized_names.group_by(&:itself).select { |_, v| v.count > 3 }
      
      if duplicates.any?
        users_with_duplicates << {
          user: user,
          duplicates: duplicates.map { |name, instances| { name: name, count: instances.count } }
        }
      end
    end

    if users_with_duplicates.any?
      puts "⚠️  Found #{users_with_duplicates.count} users with duplicate task names:"
      users_with_duplicates.each do |entry|
        puts "   - User #{entry[:user].id} (#{entry[:user].email}):"
        entry[:duplicates].first(5).each do |dup|
          puts "     • '#{dup[:name]}...' x#{dup[:count]}"
        end
        issues_found += 1
      end
    else
      puts "   ✅ No users with duplicate task names"
    end
    puts ""

    # 3. Users with high recent token usage
    puts "📋 Checking for users with abnormally high token usage (last 6 hours)..."
    high_usage_threshold = 10000  # More than 10k tokens in 6 hours is suspicious
    
    high_usage_users = WorkTokenTransaction
      .where("created_at > ?", 6.hours.ago)
      .where("token_amount < 0")
      .group(:user_id)
      .having("COUNT(*) > ?", high_usage_threshold)
      .count

    if high_usage_users.any?
      puts "⚠️  Found #{high_usage_users.count} users with >#{high_usage_threshold} transactions in 6 hours:"
      high_usage_users.sort_by { |_, count| -count }.each do |user_id, count|
        user = User.find_by(id: user_id)
        total_tokens = WorkTokenTransaction
          .where(user_id: user_id)
          .where("created_at > ?", 6.hours.ago)
          .where("token_amount < 0")
          .sum(:token_amount)
          .abs
        puts "   - User #{user_id} (#{user&.email}): #{count} transactions, #{total_tokens.to_i} tokens"
        issues_found += 1
      end
    else
      puts "   ✅ No users with abnormally high token usage"
    end
    puts ""

    # 4. Check for running agent executions that are stuck
    puts "📋 Checking for stuck agent executions (running for >1 hour)..."
    stuck_executions = AgentPluginExecution
      .where(status: 'running')
      .where("started_at < ?", 1.hour.ago)

    if stuck_executions.any?
      puts "⚠️  Found #{stuck_executions.count} stuck agent executions:"
      stuck_executions.includes(:user, :agent_plugin).each do |exec|
        duration = ((Time.current - exec.started_at) / 60).round
        puts "   - Execution #{exec.id}: #{exec.agent_plugin&.name} for user #{exec.user_id} (#{exec.user&.email}) - running for #{duration} minutes"
        issues_found += 1
      end
    else
      puts "   ✅ No stuck agent executions"
    end
    puts ""

    # 5. Rapid-fire token usage patterns (more than 20 charges per minute for any user in last hour)
    puts "📋 Checking for rapid-fire token usage patterns..."
    one_hour_ago = 1.hour.ago
    
    rapid_fire_users = []
    WorkTokenTransaction
      .where("created_at > ?", one_hour_ago)
      .where("token_amount < 0")
      .select(:user_id)
      .distinct
      .pluck(:user_id)
      .each do |user_id|
        
      by_minute = WorkTokenTransaction
        .where(user_id: user_id)
        .where("created_at > ?", one_hour_ago)
        .where("token_amount < 0")
        .group_by { |t| t.created_at.strftime("%H:%M") }
      
      max_per_minute = by_minute.values.map(&:count).max || 0
      
      if max_per_minute > 20
        user = User.find_by(id: user_id)
        rapid_fire_users << { user_id: user_id, email: user&.email, max_per_minute: max_per_minute }
      end
    end

    if rapid_fire_users.any?
      puts "🚨 Found #{rapid_fire_users.count} users with rapid-fire token usage (>20/minute):"
      rapid_fire_users.sort_by { |u| -u[:max_per_minute] }.each do |entry|
        puts "   - User #{entry[:user_id]} (#{entry[:email]}): #{entry[:max_per_minute]} charges/minute"
        issues_found += 1
      end
    else
      puts "   ✅ No users with rapid-fire token usage"
    end
    puts ""

    # Summary
    puts "=" * 80
    if issues_found > 0
      puts "🚨 AUDIT COMPLETE: Found #{issues_found} potential issues"
      puts ""
      puts "To fix issues, you can run:"
      puts "  rails billing:pause_user[user@example.com]     # Pause a specific user"
      puts "  rails billing:cleanup_duplicate_tasks[email]   # Remove duplicate tasks for a user"
    else
      puts "✅ AUDIT COMPLETE: No issues found"
    end
    puts "=" * 80
  end

  desc "Cleanup duplicate scheduled tasks for a user"
  task :cleanup_duplicate_tasks, [:email] => :environment do |_, args|
    email = args[:email]
    user = User.find_by(email: email)

    unless user
      puts "User with email '#{email}' not found."
      exit 1
    end

    puts "--- Cleaning up duplicate scheduled tasks for #{user.email} (ID: #{user.id}) ---"

    # Get all active/paused tasks
    tasks = ScheduledAgentTask.where(user: user, status: %w[active paused]).order(:created_at)
    puts "Found #{tasks.count} active/paused scheduled tasks"

    # Group by normalized name
    stop_words = %w[remind reminder to set up create a an the for my me about please]
    
    grouped = tasks.group_by do |t|
      t.name.downcase.gsub(/[^a-z0-9\s]/, '').split.reject { |w| stop_words.include?(w) }.first(5).join(' ')
    end

    duplicates_removed = 0
    kept_tasks = []

    grouped.each do |key, task_group|
      if task_group.count > 1
        # Keep the oldest one, mark others for deletion
        keeper = task_group.first
        kept_tasks << keeper.id
        
        duplicates = task_group[1..]
        duplicates.each do |dup|
          puts "   Cancelling duplicate: '#{dup.name}' (ID: #{dup.id})"
          dup.update(status: 'cancelled', enabled: false)
          duplicates_removed += 1
        end
      else
        kept_tasks << task_group.first.id
      end
    end

    puts ""
    puts "--- Summary ---"
    puts "Kept: #{kept_tasks.count} unique tasks"
    puts "Removed: #{duplicates_removed} duplicate tasks"
    puts "Remaining active: #{ScheduledAgentTask.where(user: user, status: %w[active paused]).count}"
  end
end

