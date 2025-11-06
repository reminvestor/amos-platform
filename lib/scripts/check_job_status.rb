# Script to check job status for document processing
# Run with: bin/rails runner lib/scripts/check_job_status.rb

puts "🔍 Checking SolidQueue job status..."
puts "=" * 60

# Check for ready jobs
ready_jobs = SolidQueue::ReadyExecution.joins(:job).includes(:job)
puts "\n📋 Ready Jobs (waiting to execute):"
ready_jobs.each do |execution|
  job = execution.job
  puts "  • #{job.class_name} (ID: #{job.id}, Queue: #{job.queue_name})"
  if job.arguments.dig('arguments')&.any?
    args = job.arguments['arguments']
    if args.first.is_a?(Integer) && defined?(RagDocument)
      begin
        doc = RagDocument.find_by(id: args.first)
        puts "    Document: #{doc&.display_title || 'Not found'}" if doc
      rescue
        # Ignore
      end
    end
  end
end
puts "  Total: #{ready_jobs.count} jobs waiting"

# Check for blocked/errored jobs
blocked_jobs = SolidQueue::BlockedExecution.joins(:job).includes(:job)
puts "\n🚫 Blocked Jobs:"
blocked_jobs.each do |execution|
  job = execution.job
  puts "  • #{job.class_name} (ID: #{job.id}, Queue: #{job.queue_name})"
end
puts "  Total: #{blocked_jobs.count} jobs blocked"

# Check for claimed jobs
claimed_jobs = SolidQueue::ClaimedExecution.joins(:job).includes(:job)
puts "\n⚙️  Currently Running Jobs:"
claimed_jobs.each do |execution|
  job = execution.job
  puts "  • #{job.class_name} (ID: #{job.id}, Queue: #{job.queue_name})"
  puts "    Running since: #{execution.created_at}"
end
puts "  Total: #{claimed_jobs.count} jobs running"

# Check for failed jobs
failed_jobs = SolidQueue::FailedExecution.joins(:job).includes(:job).limit(10)
puts "\n❌ Failed Jobs (last 10):"
failed_jobs.each do |execution|
  job = execution.job
  puts "  • #{job.class_name} (ID: #{job.id}, Queue: #{job.queue_name})"
  puts "    Failed at: #{execution.created_at}"
  puts "    Error: #{execution.error['exception_class']}: #{execution.error['message']}"
end
puts "  Total recent failures: #{failed_jobs.count}"

# Check recent document processing jobs
puts "\n📄 Recent Document Processing Jobs:"
recent_jobs = SolidQueue::Job.where("created_at > ?", 10.minutes.ago)
                            .where("class_name LIKE ?", "%DocumentPipelineJob%")
                            .or(SolidQueue::Job.where("created_at > ?", 10.minutes.ago)
                                              .where("class_name LIKE ?", "%DoclingExtractionJob%"))
                            .or(SolidQueue::Job.where("created_at > ?", 10.minutes.ago)
                                              .where("class_name LIKE ?", "%FallbackProcessorJob%"))
                            .order(created_at: :desc)
                            .limit(5)

recent_jobs.each do |job|
  puts "  • #{job.class_name}"
  puts "    Created: #{job.created_at}"
  puts "    Status: #{job.finished_at ? 'Finished' : 'Pending/Running'}"
end

# Check workers
puts "\n👷 Worker Processes:"
processes = SolidQueue::Process.all
processes.each do |process|
  puts "  • #{process.kind} (PID: #{process.pid || 'N/A'})"
  puts "    Last heartbeat: #{process.last_heartbeat_at}"
  puts "    Metadata: #{process.metadata}"
end
puts "  Total: #{processes.count} processes"

puts "\n✅ Diagnostics complete!"
