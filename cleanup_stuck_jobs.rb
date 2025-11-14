# Clean up stuck jobs from SolidQueue
# Run this in Rails console on production

puts "=== Cleaning up stuck jobs ==="

# Find the specific job IDs from your list
job_ids = [5751, 5750, 5749]

# Clean up the specific jobs
job_ids.each do |job_id|
  job = SolidQueue::Job.find_by(id: job_id)
  if job
    puts "Deleting job #{job_id} - #{job.class_name}"
    
    # Delete associated executions first
    SolidQueue::ReadyExecution.where(job_id: job_id).destroy_all
    SolidQueue::ClaimedExecution.where(job_id: job_id).destroy_all
    SolidQueue::FailedExecution.where(job_id: job_id).destroy_all
    
    # Then delete the job itself
    job.destroy
  else
    puts "Job #{job_id} not found"
  end
end

# Also clean up related Amos job records if they exist
amos_job_ids = ["542436cd-311d-42d9-86f2-80f1107ab52f", "bbfd08c7-1353-410f-9771-cdbe52f0e7cf"]

amos_job_ids.each do |job_id|
  amos_job = Amos::JobRecord.find_by(id: job_id)
  if amos_job
    puts "Updating Amos job #{job_id} to cancelled status"
    amos_job.update!(status: 'cancelled', completed_at: Time.current)
  end
end

# Alternative: Clean up ALL agent jobs that are stuck
puts "\n=== Cleaning up all stuck agent jobs ==="
stuck_agent_jobs = SolidQueue::Job.joins(:ready_executions)
                                  .where(queue_name: 'agents')
                                  .where('solid_queue_jobs.created_at < ?', 1.hour.ago)

puts "Found #{stuck_agent_jobs.count} stuck agent jobs"
stuck_agent_jobs.destroy_all

# Clean up failed docling jobs
puts "\n=== Cleaning up failed docling jobs ==="
failed_docling = SolidQueue::Job.joins(:failed_executions)
                                .where(queue_name: 'docling')

puts "Found #{failed_docling.count} failed docling jobs"
failed_docling.destroy_all

puts "\nCleanup complete!"
