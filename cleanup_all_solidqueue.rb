# Quick cleanup script for SolidQueue
# Run in Rails console: rails runner cleanup_all_solidqueue.rb

puts "🧹 Cleaning up ALL SolidQueue jobs..."

# Delete all executions first
[
  SolidQueue::ReadyExecution,
  SolidQueue::ClaimedExecution,
  SolidQueue::FailedExecution,
  SolidQueue::ScheduledExecution,
  SolidQueue::RecurringExecution
].each do |klass|
  count = klass.count
  klass.destroy_all
  puts "  ✅ Deleted #{count} #{klass.name.demodulize}"
end

# Then delete all jobs
job_count = SolidQueue::Job.count
SolidQueue::Job.destroy_all
puts "  ✅ Deleted #{job_count} jobs"

# Clean up Amos job records too
amos_count = Amos::JobRecord.count
Amos::JobRecord.destroy_all
puts "  ✅ Deleted #{amos_count} Amos job records"

puts "\n✨ SolidQueue is now completely empty!"
puts "   Jobs: #{SolidQueue::Job.count}"
puts "   Amos Records: #{Amos::JobRecord.count}"
