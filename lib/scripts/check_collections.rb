# Script to check existing collections and documents
# Run with: bin/rails runner lib/scripts/check_collections.rb

# Only execute when run directly (not during eager loading)
# Note: lib/scripts is in the autoload ignore list, but we add this check as a safety measure
if __FILE__ == $0 || (defined?(Rails::Runner) && ARGV.any? { |arg| arg.include?('check_collections') })
  entity_id = ARGV[0]&.to_i || 14
  
  puts "📁 Checking Document Collections (RagStores)"
  puts "=" * 60

  entity = Entity.find_by(id: entity_id)
  unless entity
    puts "❌ Entity with ID #{entity_id} not found"
    puts "Available entities:"
    Entity.limit(10).each do |e|
      puts "  - ID: #{e.id}, Name: #{e.name}"
    end
    exit 1
  end

  stores = entity.rag_stores.where(app_name: 'documents', store_type: 'entity').includes(:rag_documents)

  puts "\nCollections for Entity: #{entity.name}"
  stores.each do |store|
    puts "\n📂 Collection: '#{store.name}' (ID: #{store.id})"
    puts "   Created: #{store.created_at}"
    puts "   Documents: #{store.rag_documents.count}"
    
    if store.rag_documents.any?
      puts "   Recent documents:"
      store.rag_documents.order(created_at: :desc).limit(3).each do |doc|
        puts "     - #{doc.display_title} (#{doc.processing_status})"
      end
    end
  end

  puts "\n\n📊 Collection Summary:"
  puts "Total collections: #{stores.count}"
  puts "Total documents: #{stores.sum { |s| s.rag_documents.count }}"

  # Check for any orphaned documents
  all_docs = RagDocument.joins(:rag_store).where(rag_stores: { entity_id: entity.id })
  orphaned = all_docs.where.not(rag_store_id: stores.pluck(:id))
  if orphaned.any?
    puts "\n⚠️  Found #{orphaned.count} orphaned documents!"
  end
end
