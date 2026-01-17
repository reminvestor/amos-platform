# lib/tasks/integration_knowledge.rake
#
# Tasks for managing integration expert knowledge in RAG

namespace :integrations do
  desc "Load all integration documentation into RAG knowledge base"
  task load_knowledge: :environment do
    puts "📚 Loading integration documentation into RAG..."
    
    service = IntegrationKnowledgeLoaderService.new
    count = service.load_all_integration_docs
    
    puts "\n✅ Loaded #{count} integration documentation files"
    
    # Show what's available
    store = RagStore.find_by(app_name: 'integration_knowledge', store_type: 'system')
    if store
      puts "\n📊 Integration Knowledge Store:"
      puts "   Documents: #{store.rag_documents.count}"
      puts "   Chunks: #{store.rag_chunks.count}"
      puts "   Embedded: #{store.rag_chunks.where.not(embedding: nil).count}"
      
      puts "\n📄 Documents loaded:"
      store.rag_documents.each do |doc|
        puts "   - #{doc.title} (#{doc.rag_chunks.count} chunks)"
      end
    end
  end

  desc "Reload a specific integration's documentation"
  task :reload_knowledge, [:integration_name] => :environment do |_t, args|
    integration_name = args[:integration_name]
    
    if integration_name.blank?
      puts "❌ Please specify an integration name:"
      puts "   rails integrations:reload_knowledge[quickbooks]"
      exit 1
    end
    
    puts "📚 Reloading #{integration_name} documentation..."
    
    service = IntegrationKnowledgeLoaderService.new
    if service.load_integration_doc(integration_name)
      puts "✅ Reloaded #{integration_name} documentation"
    else
      puts "❌ Failed to reload #{integration_name} documentation"
    end
  end

  desc "Test querying the integration knowledge base"
  task :query_knowledge, [:question] => :environment do |_t, args|
    question = args[:question] || "How do I list open invoices in QuickBooks?"
    
    puts "🔍 Querying: #{question}\n\n"
    
    service = IntegrationKnowledgeLoaderService.new
    results = service.query_integration_knowledge(question)
    
    if results.empty?
      puts "No results found. Make sure to run 'rails integrations:load_knowledge' first."
    else
      results.each_with_index do |result, i|
        puts "=" * 60
        puts "Result #{i + 1} (#{result[:integration]} - #{result[:section]})"
        puts "-" * 60
        puts result[:content].truncate(500)
        puts
      end
    end
  end

  desc "List available integration documentation files"
  task list_docs: :environment do
    docs_path = Rails.root.join('docs', 'integrations')
    
    puts "📂 Available integration documentation:"
    puts
    
    Dir.glob(docs_path.join('*.md')).each do |file_path|
      name = File.basename(file_path, '.md')
      size = File.size(file_path)
      lines = File.readlines(file_path).count
      
      puts "   #{name.titleize}"
      puts "     File: #{File.basename(file_path)}"
      puts "     Size: #{(size / 1024.0).round(1)} KB (#{lines} lines)"
      puts
    end
  end
end

