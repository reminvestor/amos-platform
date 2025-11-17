namespace :amos do
  desc "Test Amos orchestration with all agents"
  task test: :environment do
    puts "🧪 Testing Amos Orchestration System"
    puts "=" * 50
    
    # Find a test user
    user = User.first
    unless user
      puts "❌ No users found. Please create a user first."
      exit 1
    end
    
    entity = user.entity
    unless entity
      puts "❌ User has no entity. Please set up an entity first."
      exit 1
    end
    
    puts "✅ Using user: #{user.email}"
    puts "✅ Using entity: #{entity.name}"
    
    # Test cases for each agent
    test_cases = [
      {
        message: "Hello Amos",
        expected_agent: nil, # Should be handled directly
        description: "Simple greeting (no agent needed)"
      },
      {
        message: "Show me my email campaigns",
        expected_agent: nil, # Scout should handle with tools
        description: "Query email campaigns (Scout with tools)"
      },
      {
        message: "List all my landing pages",
        expected_agent: nil, # Scout should handle with tools
        description: "List landing pages (Scout with tools)"
      },
      {
        message: "How many contacts do I have?",
        expected_agent: nil, # Scout should handle with tools
        description: "Count contacts (Scout with tools)"
      },
      {
        message: "Show me revenue analytics for last month",
        expected_agent: nil, # Scout should handle with tools
        description: "View analytics (Scout with tools)"
      },
      {
        message: "Create a landing page for my new product launch",
        expected_agent: :landing_page_agent,
        description: "Landing Page Agent test"
      },
      {
        message: "Send an email campaign to all customers",
        expected_agent: :email_agent,
        description: "Email Agent test"
      },
      {
        message: "Import customers from Stripe",
        expected_agent: :integration_agent,
        description: "Integration Agent test"
      },
      {
        message: "Import contacts from the attached CSV file",
        expected_agent: :data_agent,
        description: "Data Agent test"
      },
      {
        message: "Generate a comprehensive analytics report",
        expected_agent: :analytics_agent,
        description: "Analytics Agent test (complex report)"
      },
      {
        message: "Help me optimize my SEO strategy",
        expected_agent: :general_agent,
        description: "General Agent test"
      }
    ]
    
    # Create orchestrator
    session_id = SecureRandom.uuid
    orchestrator = Amos::Orchestrator.new(user, entity, session_id)
    
    # Set up callback to see responses
    responses = []
    orchestrator.on_stream do |response|
      responses << response
      puts "  📨 Response: #{response[:type]} - #{response[:content]&.truncate(100)}"
    end
    
    # Test each case
    test_cases.each_with_index do |test_case, index|
      puts "\n📝 Test #{index + 1}: #{test_case[:description]}"
      puts "  Message: \"#{test_case[:message]}\""
      puts "  Expected: #{test_case[:expected_agent] || 'Direct response'}"
      
      # Clear responses
      responses.clear
      
      # Process message
      begin
        orchestrator.process_message(test_case[:message], source: :user)
        
        # Check if job was created
        jobs = orchestrator.query_job_status
        
        if test_case[:expected_agent]
          if jobs.any?
            created_job = jobs.last
            puts "  ✅ Job created: #{created_job[:agent]}"
            
            # Check if correct agent was selected
            if created_job[:agent] == test_case[:expected_agent]
              puts "  ✅ Correct agent selected!"
            else
              puts "  ⚠️  Wrong agent: expected #{test_case[:expected_agent]}, got #{created_job[:agent]}"
            end
          else
            puts "  ❌ No job created (expected #{test_case[:expected_agent]})"
          end
        else
          # Should have direct response
          if responses.any? { |r| r[:type] == 'amos_response' }
            puts "  ✅ Direct response received"
          else
            puts "  ❌ No direct response"
          end
        end
        
      rescue => e
        puts "  ❌ Error: #{e.message}"
        puts "     #{e.backtrace.first}"
      end
      
      # Small delay between tests
      sleep 0.5
    end
    
    puts "\n" + "=" * 50
    puts "✅ Amos orchestration test complete!"
    
    # Show active jobs
    active_jobs = Amos::JobRecord.where(status: ['queued', 'running'])
    if active_jobs.any?
      puts "\n⏳ Active Jobs:"
      active_jobs.each do |job|
        puts "  • #{job.agent_type}: #{job.status} (#{job.job_id})"
      end
    end
  end
  
  desc "Clean up Amos test data"
  task cleanup: :environment do
    puts "🧹 Cleaning up Amos test data..."
    
    # Cancel all active jobs
    active_jobs = Amos::JobRecord.where(status: ['queued', 'running', 'waiting_for_input'])
    active_jobs.each do |job|
      job.update!(status: 'cancelled', completed_at: Time.current)
      puts "  ❌ Cancelled job: #{job.job_id}"
    end
    
    # Clean up old test jobs (older than 1 hour)
    old_jobs = Amos::JobRecord.where("created_at < ?", 1.hour.ago)
    count = old_jobs.count
    old_jobs.destroy_all
    puts "  🗑️  Removed #{count} old job records"
    
    puts "✅ Cleanup complete!"
  end
  
  desc "Monitor Amos jobs in real-time"
  task monitor: :environment do
    puts "👁️  Monitoring Amos Jobs (Press Ctrl+C to stop)"
    puts "=" * 80
    
    loop do
      system("clear") || system("cls") # Clear screen
      
      puts "🤖 AMOS JOB MONITOR - #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "=" * 80
      
      # Group jobs by status
      statuses = ['queued', 'running', 'waiting_for_input', 'completed', 'failed', 'cancelled']
      
      statuses.each do |status|
        jobs = Amos::JobRecord.where(status: status).order(created_at: :desc).limit(5)
        
        if jobs.any?
          puts "\n#{status_emoji(status)} #{status.upcase} (#{jobs.count})"
          puts "-" * 40
          
          jobs.each do |job|
            time_info = case status
            when 'completed', 'failed', 'cancelled'
              "completed #{time_ago_in_words(job.completed_at)} ago" if job.completed_at
            else
              "started #{time_ago_in_words(job.created_at)} ago"
            end
            
            puts "  #{job.agent_type.to_s.ljust(20)} | #{job.job_id[0..7]}... | #{time_info}"
            puts "    └─ #{job.status_message || 'No message'}" if job.status_message
          end
        end
      end
      
      # Show summary
      puts "\n" + "=" * 80
      total = Amos::JobRecord.count
      active = Amos::JobRecord.where(status: ['queued', 'running', 'waiting_for_input']).count
      puts "Total Jobs: #{total} | Active: #{active}"
      
      # Refresh every 2 seconds
      sleep 2
    end
  end
  
  private
  
  def status_emoji(status)
    case status
    when 'queued' then '⏳'
    when 'running' then '🔄'
    when 'waiting_for_input' then '❓'
    when 'completed' then '✅'
    when 'failed' then '❌'
    when 'cancelled' then '🚫'
    else '•'
    end
  end
  
  def time_ago_in_words(time)
    return 'unknown' unless time
    
    seconds = Time.current - time
    
    case seconds
    when 0..59 then "#{seconds.to_i}s"
    when 60..3599 then "#{(seconds / 60).to_i}m"
    when 3600..86399 then "#{(seconds / 3600).to_i}h"
    else "#{(seconds / 86400).to_i}d"
    end
  end
end
