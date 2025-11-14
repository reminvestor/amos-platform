#!/usr/bin/env ruby

# Script to clean up SolidQueue jobs
# Run this in Rails console on production

puts "=== SolidQueue Cleanup Script ==="
puts "Current time: #{Time.current}"
puts

# Show current job counts
puts "Current job counts:"
puts "- Ready jobs: #{SolidQueue::ReadyExecution.count}"
puts "- Claimed jobs: #{SolidQueue::ClaimedExecution.count}"  
puts "- Failed jobs: #{SolidQueue::FailedExecution.count}"
puts "- Scheduled jobs: #{SolidQueue::ScheduledExecution.count}"
puts "- Total jobs: #{SolidQueue::Job.count}"
puts

# Clean up specific queues if needed
queues_to_clean = ['agents', 'documents', 'embeddings', 'docling', 'default']

queues_to_clean.each do |queue_name|
  jobs_in_queue = SolidQueue::Job.joins(:ready_executions).where(queue_name: queue_name).count
  puts "Jobs in '#{queue_name}' queue: #{jobs_in_queue}"
end

puts "\n=== Cleanup Options ==="
puts "1. Delete all ready jobs:"
puts "   SolidQueue::ReadyExecution.destroy_all"
puts
puts "2. Delete all failed jobs:"
puts "   SolidQueue::FailedExecution.destroy_all"
puts
puts "3. Delete jobs from specific queue (e.g., 'agents'):"
puts "   SolidQueue::Job.joins(:ready_executions).where(queue_name: 'agents').destroy_all"
puts
puts "4. Delete all jobs (nuclear option):"
puts "   SolidQueue::Job.destroy_all"
puts
puts "5. Delete old completed jobs (> 7 days):"
puts "   SolidQueue::Job.where('finished_at < ?', 7.days.ago).destroy_all"
puts
puts "6. Delete stuck jobs (claimed but not finished after 1 hour):"
puts "   SolidQueue::ClaimedExecution.where('created_at < ?', 1.hour.ago).destroy_all"

# Example: Clean up old agent jobs
# Uncomment to run:
# old_agent_jobs = SolidQueue::Job.joins(:ready_executions)
#                                  .where(queue_name: 'agents')
#                                  .where('created_at < ?', 1.day.ago)
# puts "\nDeleting #{old_agent_jobs.count} old agent jobs..."
# old_agent_jobs.destroy_all
# puts "Done!"

# Also clean up Amos job records if needed
puts "\n=== Amos Job Records ==="
puts "Active Amos jobs: #{Amos::JobRecord.where(status: ['pending', 'processing']).count}"
puts "To clean up stuck Amos jobs older than 1 day:"
puts "  Amos::JobRecord.where(status: ['pending', 'processing']).where('created_at < ?', 1.day.ago).update_all(status: 'failed')"
