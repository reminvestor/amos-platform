# Script to fix documents stuck in processing due to duplicate detection
# Run with: bin/rails runner lib/scripts/fix_duplicate_documents.rb

puts "🔍 Looking for stuck documents..."

# Find documents that are stuck in 'processing' status
stuck_docs = RagDocument.where(processing_status: 'processing')
                       .where('created_at < ?', 5.minutes.ago)

puts "Found #{stuck_docs.count} potentially stuck documents"

stuck_docs.each do |doc|
  puts "\n📄 Checking document #{doc.id}: #{doc.display_title}"
  
  # Check if there's an existing document with the same hash
  existing = RagDocument.where(file_hash: doc.file_hash)
                       .where.not(id: doc.id)
                       .first
  
  if existing
    puts "  ✅ Found duplicate of document #{existing.id}"
    
    # Update the stuck document
    doc.update!(
      processing_status: 'completed',
      docling_metadata: doc.docling_metadata.merge(
        'duplicate_of' => existing.id,
        'note' => 'Duplicate of existing document'
      )
    )
    
    # Broadcast the update
    doc.broadcast_progress_update if doc.respond_to?(:broadcast_progress_update)
    
    puts "  📋 Marked as duplicate"
  else
    # Check if document has S3 path but no chunks
    if doc.docling_metadata&.dig('s3_path').present? && doc.rag_chunks.count == 0
      puts "  ⚠️  Has S3 path but no chunks, may need reprocessing"
      
      # You could trigger reprocessing here if needed:
      # Rag::DoclingExtractionJob.perform_later(doc.id)
    else
      puts "  🔄 Document appears to be genuinely processing"
    end
  end
end

puts "\n✨ Done!"
