# Script to manually process stuck documents
# Run with: bin/rails runner lib/scripts/process_stuck_documents.rb

puts "🔍 Looking for documents stuck in processing..."

stuck_docs = RagDocument.where(processing_status: 'processing')
                       .where('created_at < ?', 2.minutes.ago)

puts "Found #{stuck_docs.count} stuck documents"

stuck_docs.each do |doc|
  puts "\n📄 Document #{doc.id}: #{doc.display_title}"
  puts "  Created: #{doc.created_at}"
  puts "  Stage: #{doc.processing_stage}"
  puts "  S3 Path: #{doc.docling_metadata&.dig('s3_path') || 'None'}"
  
  if doc.docling_metadata&.dig('s3_path').present?
    puts "  ➡️  Has S3 path, triggering extraction..."
    
    # Queue the extraction job directly
    Rag::DoclingExtractionJob.perform_later(doc.id)
    
    puts "  ✅ Queued extraction job"
  else
    puts "  ❌ No S3 path found - document needs re-upload"
  end
end

puts "\n✨ Done!"
