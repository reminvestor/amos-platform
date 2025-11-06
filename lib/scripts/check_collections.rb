# Script to check existing collections and documents
# Run with: bin/rails runner lib/scripts/check_collections.rb

puts "📁 Checking Document Collections (RagStores)"
puts "=" * 60

entity = Entity.find(14) # Adjust entity ID as needed
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
