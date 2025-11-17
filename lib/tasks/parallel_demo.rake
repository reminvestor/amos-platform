namespace :parallel do
  desc "Demonstrate parallel task processing"
  task demo: :environment do
    puts "\n🚀 Parallel Processing Demo\n"
    
    # Ensure database connection
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
    rescue => e
      puts "❌ Database connection error: #{e.message}"
      puts "Make sure your Rails server is running with: foreman start -f Procfile.dev"
      exit
    end
    
    # Find or create demo user
    user = User.find_by(email: 'demo@example.com') || User.first
    unless user
      puts "❌ No users found. Please create a user first."
      exit
    end
    
    entity = user.entity
    session_id = SecureRandom.uuid
    
    # Create orchestrator
    orchestrator = ParallelTaskOrchestrator.new(user, entity, session_id)
    
    # Demo 1: Simple parallel request
    puts "📝 Demo 1: Analyzing campaigns in parallel"
    puts "Request: 'Analyze my top 3 campaigns and create a comparison report'"
    
    tasks = orchestrator.process_request(
      "Analyze my top 3 campaigns and create a comparison report",
      {
        voice_mode: false,
        current_canvas: 'conversation'
      }
    )
    
    puts "\n✅ Created #{tasks.length} tasks:"
    tasks.each do |task|
      puts "  - Task ##{task.id}: #{task.task_type} - #{task.metadata['description']}"
    end
    
    # Demo 2: Voice mode with immediate response
    puts "\n📝 Demo 2: Voice mode request with immediate response"
    puts "Request: 'Schedule a meeting with the top performing campaign managers'"
    
    voice_tasks = orchestrator.process_request(
      "Schedule a meeting with the top performing campaign managers",
      {
        voice_mode: true,
        current_canvas: 'conversation'
      }
    )
    
    immediate_task = voice_tasks.find { |t| t.task_type == 'voice_immediate' }
    if immediate_task
      puts "\n⚡ Immediate response delivered in #{immediate_task.metadata['immediate_processing_time_ms']}ms"
    end
    
    # Monitor progress
    puts "\n📊 Monitoring task progress..."
    puts "(Press Ctrl+C to stop monitoring)\n"
    
    begin
      loop do
        all_tasks = TaskSession.where(id: (tasks + voice_tasks).map(&:id))
        
        system('clear') || system('cls')
        puts "🚀 Parallel Task Monitor\n"
        puts "=" * 60
        
        all_tasks.each do |task|
          status_icon = case task.status
                       when 'completed' then '✅'
                       when 'failed' then '❌'
                       when 'active' then '⚡'
                       else '⏳'
                       end
          
          progress_bar = if task.progress
                          filled = (task.progress / 5).to_i
                          empty = 20 - filled
                          "[#{'█' * filled}#{'░' * empty}] #{task.progress}%"
                        else
                          "[░░░░░░░░░░░░░░░░░░░░] 0%"
                        end
          
          puts "#{status_icon} Task ##{task.id} (#{task.task_type})"
          puts "   #{task.metadata['description']}"
          puts "   #{progress_bar}"
          puts "   Status: #{task.status}"
          
          if task.started_at && task.status == 'completed'
            duration = (task.updated_at - task.started_at).round(2)
            puts "   Duration: #{duration}s"
          end
          
          puts ""
        end
        
        # Check if all completed
        if all_tasks.all? { |t| t.status.in?(['completed', 'failed']) }
          puts "\n✅ All tasks completed!"
          break
        end
        
        sleep 1
      end
    rescue Interrupt
      puts "\n\n👋 Demo stopped by user"
    end
    
    # Show results
    puts "\n📊 Final Results:"
    all_tasks = TaskSession.where(id: (tasks + voice_tasks).map(&:id))
    
    all_tasks.each do |task|
      if task.state['result']
        puts "\nTask ##{task.id} Result:"
        puts task.state['result']['summary'] || task.state['result']['response']
      end
    end
    
    puts "\n✨ Demo complete!"
  end
  
  desc "Clean up demo tasks"
  task cleanup: :environment do
    count = TaskSession.where("metadata->>'description' LIKE '%Demo%'").destroy_all.count
    puts "🧹 Cleaned up #{count} demo tasks"
  end
end
