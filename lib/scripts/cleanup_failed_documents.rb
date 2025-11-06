# Script to cleanup failed documents
# Run with: bin/rails runner lib/scripts/cleanup_failed_documents.rb

puts "🧹 Cleaning up failed/duplicate documents..."
puts "=" * 60

# Find documents by status
failed_docs = RagDocument.where(processing_status: ['failed', 'processing'])
                        .where('created_at < ?', 5.minutes.ago)

puts "\n📋 Found #{failed_docs.count} documents to clean up"

# Group by file hash to identify duplicates
by_hash = failed_docs.group_by(&:file_hash)

by_hash.each do |hash, docs|
  puts "\n📄 File hash: #{hash[0..15]}..."
  puts "  Found #{docs.count} documents:"
  
  # Check if there's a successful version
  successful = RagDocument.where(file_hash: hash, processing_status: 'completed').first
  
  if successful
    puts "  ✅ Successful version exists: #{successful.display_title} (ID: #{successful.id})"
    puts "  🗑️  Removing failed duplicates:"
  else
    puts "  ❌ No successful version found"
    puts "  🗑️  Removing all failed versions:"
  end
  
  docs.each do |doc|
    begin
      puts "     - #{doc.display_title} (ID: #{doc.id}, Status: #{doc.processing_status})"
      
      # Remove from Pinecone if needed
      if doc.rag_store.pinecone_namespace.present? && doc.rag_chunks.any?
        chunk_ids = doc.rag_chunks.pluck(:pinecone_vector_id).compact
        if chunk_ids.any?
          pinecone_service = PineconeService.new
          pinecone_service.delete_by_ids(doc.rag_store.pinecone_namespace, chunk_ids)
          puts "       Removed #{chunk_ids.count} vectors from Pinecone"
        end
      end
      
      # Delete the document
      doc.destroy!
      puts "       ✅ Deleted successfully"
      
    rescue => e
      puts "       ❌ Failed to delete: #{e.message}"
    end
  end
end

puts "\n✨ Cleanup complete!"

# Show remaining documents
remaining = RagDocument.group(:processing_status).count
puts "\n📊 Document status summary:"
remaining.each do |status, count|
  puts "  #{status}: #{count}"
end
