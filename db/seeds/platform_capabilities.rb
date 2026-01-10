# frozen_string_literal: true

# Seeds the PLATFORM_CAPABILITIES.md document into the RAG system
# This makes platform knowledge queryable by all agents.

puts "📚 Loading Platform Capabilities into knowledge base..."

# Read the capabilities document
capabilities_path = Rails.root.join('PLATFORM_CAPABILITIES.md')

unless File.exist?(capabilities_path)
  puts "  ⚠️  PLATFORM_CAPABILITIES.md not found at #{capabilities_path}"
  return
end

content = File.read(capabilities_path)
puts "  📄 Read #{content.length} bytes from PLATFORM_CAPABILITIES.md"

# Find or create a system-level RagStore for platform documentation
system_rag_store = RagStore.find_or_create_by!(
  store_type: 'system',
  name: 'platform_capabilities',
  entity: nil # System-level, not entity-specific
) do |store|
  store.description = 'AMOS Platform Capabilities - documentation for what the platform can do'
  store.metadata = {
    source: 'PLATFORM_CAPABILITIES.md',
    category: 'amos_platform',
    auto_loaded: true
  }
  puts "  ✅ Created RagStore: platform_capabilities"
end

# Delete existing chunks for this store (to refresh)
existing_chunks = RagChunk.where(rag_store: system_rag_store)
if existing_chunks.any?
  puts "  🔄 Removing #{existing_chunks.count} existing chunks..."
  existing_chunks.destroy_all
end

# Split content into logical sections
sections = content.split(/^## /).reject(&:blank?)

# First section is intro (before first ##)
intro = sections.shift
sections.unshift("Introduction\n#{intro}") if intro.present?

chunks_created = 0

sections.each_with_index do |section, index|
  # Clean up the section
  section_content = section.strip
  next if section_content.blank?
  
  # Extract title from first line
  lines = section_content.lines
  title = lines.first&.strip&.gsub(/^#+\s*/, '') || "Section #{index + 1}"
  body = lines.drop(1).join
  
  # Create chunk
  RagChunk.create!(
    rag_store: system_rag_store,
    content: section_content,
    chunk_type: 'section',
    chunk_index: index,
    metadata: {
      title: title,
      source: 'PLATFORM_CAPABILITIES.md',
      section_number: index
    }
  )
  chunks_created += 1
end

# Generate embeddings for the chunks (if embedding service is available)
begin
  if defined?(EmbeddingService)
    puts "  🧠 Generating embeddings..."
    RagChunk.where(rag_store: system_rag_store).find_each do |chunk|
      next if chunk.embedding.present?
      
      embedding = EmbeddingService.new.generate_embedding(chunk.content)
      chunk.update!(embedding: embedding) if embedding
    end
    puts "  ✅ Embeddings generated"
  end
rescue => e
  puts "  ⚠️  Embedding generation skipped: #{e.message}"
end

puts "✅ Platform Capabilities loaded: #{chunks_created} sections indexed"
puts "   Agents can now query platform knowledge via RAG"

