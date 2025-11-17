#!/usr/bin/env ruby
# Run this in production console to diagnose stuck documents

puts "=== CHECKING STUCK DOCUMENTS ==="

# Find recent documents stuck in extracting
stuck_docs = RagDocument.where(processing_status: 'extracting')
                       .where('created_at > ?', 1.hour.ago)
                       .order(created_at: :desc)

puts "\nFound #{stuck_docs.count} documents stuck in 'extracting' status:"

stuck_docs.each do |doc|
  puts "\n📄 Document ##{doc.id}: #{doc.original_filename}"
  puts "   Created: #{doc.created_at}"
  puts "   Status: #{doc.processing_status}"
  puts "   Chunks: #{doc.rag_chunks.count}"
  puts "   Last Error: #{doc.last_error || 'None'}"
  
  # Check for related processing jobs
  jobs = ProcessingJob.where(processable: doc).order(created_at: :desc).limit(5)
  if jobs.any?
    puts "   Processing Jobs:"
    jobs.each do |job|
      puts "     - Type: #{job.job_type}, Status: #{job.status}, Created: #{job.created_at}"
      puts "       Error: #{job.error_message}" if job.error_message.present?
    end
  end
  
  # Check SolidQueue jobs
  solid_jobs = SolidQueue::Job.where("arguments LIKE ?", "%#{doc.id}%")
                              .where("created_at > ?", doc.created_at)
                              .order(created_at: :desc)
                              .limit(5)
  
  if solid_jobs.any?
    puts "   SolidQueue Jobs:"
    solid_jobs.each do |job|
      puts "     - Queue: #{job.queue_name}, Status: #{job.finished_at ? 'Finished' : 'Pending'}"
      puts "       Class: #{job.class_name}"
      puts "       Created: #{job.created_at}"
    end
  else
    puts "   ⚠️  NO SOLIDQUEUE JOBS FOUND!"
  end
end

puts "\n=== CHECKING QUEUE STATUS ==="
['documents', 'docling', 'embeddings'].each do |queue|
  pending = SolidQueue::Job.joins(:ready_execution)
                          .where(queue_name: queue, finished_at: nil)
                          .count
  puts "#{queue.ljust(15)}: #{pending} pending jobs"
end

puts "\n=== CHECKING FOR ERRORS ==="
recent_errors = ProcessingJob.where(status: 'failed')
                            .where('created_at > ?', 1.hour.ago)
                            .order(created_at: :desc)
                            .limit(10)

if recent_errors.any?
  puts "\nRecent failures:"
  recent_errors.each do |job|
    puts "- #{job.processable_type} ##{job.processable_id}: #{job.error_message}"
  end
else
  puts "No recent failures found"
end
