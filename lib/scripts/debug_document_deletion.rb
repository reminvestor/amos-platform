# Script to debug document deletion issues
# Run with: bin/rails runner lib/scripts/debug_document_deletion.rb DOC_ID

doc_id = ARGV[0] || 11
puts "🔍 Debugging deletion for document ID: #{doc_id}"
puts "=" * 60

begin
  doc = RagDocument.find(doc_id)
  puts "\n📄 Document: #{doc.display_title}"
  puts "  Status: #{doc.processing_status}"
  puts "  Created: #{doc.created_at}"
  
  # Check all associations
  puts "\n📎 Associations:"
  puts "  - RagChunks: #{doc.rag_chunks.count}"
  puts "  - DocumentSubjectAssignments: #{doc.document_subject_assignments.count}"
  puts "  - DocumentTagAssignments: #{doc.document_tag_assignments.count}"
  puts "  - DocumentAnalytics: #{doc.document_analytics.count}"
  
  # Check if DocumentAnnotation model exists
  if defined?(DocumentAnnotation)
    puts "  - DocumentAnnotations: #{doc.document_annotations.count}"
  else
    puts "  - DocumentAnnotations: Model not defined!"
  end
  
  # Check for child documents
  puts "  - Child Documents: #{doc.child_documents.count}"
  
  # Try to find what's preventing deletion
  puts "\n🧪 Testing deletion..."
  
  # Clone to test
  test_doc = doc.dup
  test_doc.id = doc.id
  
  # Check each association
  doc.class.reflect_on_all_associations(:has_many).each do |assoc|
    begin
      count = doc.send(assoc.name).count
      if count > 0
        puts "  #{assoc.name}: #{count} records"
        if assoc.options[:dependent].nil?
          puts "    ⚠️  No dependent option set!"
        else
          puts "    ✅ Dependent: #{assoc.options[:dependent]}"
        end
      end
    rescue => e
      puts "  #{assoc.name}: ERROR - #{e.message}"
    end
  end
  
  # Try actual deletion in a transaction
  puts "\n💥 Attempting deletion in transaction..."
  ActiveRecord::Base.transaction do
    begin
      doc.destroy!
      puts "✅ Deletion would succeed!"
      raise ActiveRecord::Rollback # Don't actually delete
    rescue => e
      puts "❌ Deletion failed: #{e.class.name}"
      puts "   Message: #{e.message}"
      puts "   Backtrace:"
      puts e.backtrace.first(5).map { |line| "     #{line}" }
      
      if doc.errors.any?
        puts "\n   Validation errors:"
        doc.errors.full_messages.each do |msg|
          puts "     - #{msg}"
        end
      end
    end
  end
  
rescue ActiveRecord::RecordNotFound
  puts "❌ Document #{doc_id} not found!"
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end
