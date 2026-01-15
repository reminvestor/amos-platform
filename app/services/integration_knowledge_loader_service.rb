# IntegrationKnowledgeLoaderService
#
# Loads integration documentation from docs/integrations/*.md into a system RAG store.
# This knowledge base is used by integration agents and Amos to understand
# how to properly interact with external APIs.
#
# Usage:
#   IntegrationKnowledgeLoaderService.new.load_all_integration_docs
#   IntegrationKnowledgeLoaderService.new.load_integration_doc('quickbooks')
#
class IntegrationKnowledgeLoaderService
  DOCS_PATH = Rails.root.join('docs', 'integrations')
  STORE_NAME = 'Integration Expert Knowledge'
  APP_NAME = 'integration_knowledge'

  def initialize
    # No dependencies needed - works directly with RagStore
  end

  # Load all integration documentation into RAG
  def load_all_integration_docs
    Rails.logger.info "[IntegrationKnowledge] Starting to load all integration docs..."
    
    docs_loaded = 0
    
    Dir.glob(DOCS_PATH.join('*.md')).each do |file_path|
      integration_name = File.basename(file_path, '.md')
      
      if load_integration_doc(integration_name)
        docs_loaded += 1
      end
    end
    
    Rails.logger.info "[IntegrationKnowledge] ✅ Loaded #{docs_loaded} integration documentation files"
    docs_loaded
  end

  # Load a specific integration's documentation
  def load_integration_doc(integration_name)
    file_path = DOCS_PATH.join("#{integration_name}.md")
    
    unless File.exist?(file_path)
      Rails.logger.warn "[IntegrationKnowledge] ⚠️ No documentation found for #{integration_name}"
      return false
    end
    
    content = File.read(file_path)
    
    # Get or create the integration knowledge RAG store
    rag_store = find_or_create_system_store
    
    # Check if this doc already exists (by filename hash)
    file_hash = Digest::SHA256.hexdigest(content)
    existing_doc = rag_store.rag_documents.find_by(file_hash: file_hash)
    
    if existing_doc
      Rails.logger.info "[IntegrationKnowledge] 📄 #{integration_name}.md already up-to-date"
      return true
    end
    
    # Check if there's an older version and mark it for replacement
    old_doc = rag_store.rag_documents.find_by(original_filename: "#{integration_name}.md")
    old_doc&.destroy if old_doc
    
    # Create the new document
    doc = rag_store.rag_documents.create!(
      original_filename: "#{integration_name}.md",
      file_hash: file_hash,
      content_type: 'text/markdown',
      file_size_bytes: content.bytesize,
      processing_status: 'processing',
      title: "#{integration_name.titleize} Integration Expert Knowledge",
      summary: "Comprehensive documentation for the #{integration_name.titleize} API integration"
    )
    
    # Process into chunks
    chunks = chunk_markdown_content(content, integration_name)
    
    chunks.each_with_index do |chunk_content, index|
      chunk = doc.rag_chunks.create!(
        content: chunk_content[:content],
        chunk_type: chunk_content[:type],
        position: index,
        heading: chunk_content[:heading],
        metadata: {
          integration: integration_name,
          section: chunk_content[:section],
          source: 'integration_docs'
        }
      )
      
      # Generate embedding asynchronously (or inline if service available)
      generate_embedding_for_chunk(chunk)
    end
    
    doc.update!(processing_status: 'completed')
    
    Rails.logger.info "[IntegrationKnowledge] ✅ Loaded #{integration_name}.md with #{chunks.size} chunks"
    true
  rescue => e
    Rails.logger.error "[IntegrationKnowledge] ❌ Failed to load #{integration_name}: #{e.message}"
    false
  end

  # Query the integration knowledge base
  def query_integration_knowledge(question, integration_name: nil, top_k: 5)
    rag_store = find_system_store
    return [] unless rag_store
    
    # Get chunks from the integration knowledge store
    chunks = rag_store.rag_chunks.where.not(embedding: nil)
    
    # Filter by integration if specified
    if integration_name.present?
      chunks = chunks.where("metadata->>'integration' = ?", integration_name)
    end
    
    # Use pgvector similarity search
    query_embedding = generate_query_embedding(question)
    return [] unless query_embedding
    
    chunks.nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
          .limit(top_k)
          .map do |chunk|
            {
              content: chunk.content,
              integration: chunk.metadata['integration'],
              section: chunk.heading || chunk.metadata['section'],
              score: chunk.neighbor_distance
            }
          end
  end

  private

  def find_or_create_system_store
    RagStore.find_or_create_by!(
      name: STORE_NAME,
      app_name: APP_NAME,
      store_type: 'system'
    ) do |store|
      store.status = 'active'
      store.metadata = {
        description: 'Expert knowledge for external integrations (QuickBooks, Stripe, etc.)',
        source: 'integration_docs',
        auto_updated: true
      }
    end
  end

  def find_system_store
    RagStore.find_by(app_name: APP_NAME, store_type: 'system')
  end

  def chunk_markdown_content(content, integration_name)
    chunks = []
    current_section = nil
    current_heading = nil
    current_content = []
    
    content.lines.each do |line|
      # Check for headers (markdown # ## ###)
      if line.match?(/^\#{1,3}\s/)
        # Save previous chunk if any
        if current_content.any?
          chunks << {
            content: current_content.join.strip,
            type: 'section',
            heading: current_heading,
            section: current_section
          }
        end
        
        # Parse new header
        match = line.match(/^(\#{1,3})\s+(.+)$/)
        if match
          level = match[1].length
          heading = match[2].strip
          
          if level == 1
            current_section = heading
          elsif level == 2
            current_section = heading
          end
          
          current_heading = heading
          current_content = [line]
        end
      else
        current_content << line
      end
    end
    
    # Don't forget the last chunk
    if current_content.any?
      chunks << {
        content: current_content.join.strip,
        type: 'section',
        heading: current_heading,
        section: current_section
      }
    end
    
    # Add a summary chunk combining key info
    chunks << {
      content: generate_summary_chunk(content, integration_name),
      type: 'summary',
      heading: "#{integration_name.titleize} Quick Reference",
      section: 'Summary'
    }
    
    chunks
  end

  def generate_summary_chunk(content, integration_name)
    # Extract key information for a quick-reference chunk
    summary = "Quick Reference for #{integration_name.titleize} Integration:\n\n"
    
    # Extract table content if any (these are especially useful)
    content.scan(/\|.+\|.+\|/m).first(10).each do |table_row|
      summary += "#{table_row}\n"
    end
    
    # Extract code examples
    content.scan(/```\w*\n(.+?)\n```/m).first(5).each do |code_block|
      summary += "\nExample: #{code_block[0].lines.first.strip}\n"
    end
    
    summary.truncate(2000)
  end

  def generate_embedding_for_chunk(chunk)
    embedding = generate_query_embedding(chunk.content)
    chunk.update!(embedding: embedding) if embedding
  rescue => e
    Rails.logger.warn "[IntegrationKnowledge] Failed to generate embedding: #{e.message}"
  end

  def generate_query_embedding(text)
    return nil if text.blank?
    
    # Use the configured embedding service
    embedding_service = EmbeddingService.new
    embedding_service.generate(text)
  rescue => e
    Rails.logger.warn "[IntegrationKnowledge] Embedding generation failed: #{e.message}"
    nil
  end
end

