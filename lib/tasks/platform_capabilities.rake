# frozen_string_literal: true

namespace :platform do
  desc "Load/refresh PLATFORM_CAPABILITIES.md into the RAG knowledge base"
  task load_capabilities: :environment do
    load Rails.root.join('db/seeds/platform_capabilities.rb')
  end
  
  desc "Show platform capabilities summary"
  task capabilities_summary: :environment do
    puts "\n📚 PLATFORM CAPABILITIES SUMMARY"
    puts "=" * 50
    
    store = RagStore.find_by(name: 'platform_capabilities', store_type: 'system')
    
    if store
      chunks = RagChunk.where(rag_store: store)
      puts "✅ Platform capabilities loaded"
      puts "   Store ID: #{store.id}"
      puts "   Chunks: #{chunks.count}"
      puts "   Last updated: #{store.updated_at.strftime('%Y-%m-%d %H:%M')}"
      puts "\n📑 Sections:"
      chunks.order(:chunk_index).each do |chunk|
        title = chunk.metadata['title'] || "Section #{chunk.chunk_index}"
        has_embedding = chunk.embedding.present? ? '✅' : '⚠️'
        puts "   #{has_embedding} #{title}"
      end
    else
      puts "⚠️  Platform capabilities not loaded yet"
      puts "   Run: rake platform:load_capabilities"
    end
    
    puts "\n"
  end
end

