namespace :rag do
  desc "Load AMOS documentation from rag_sources/system/amos/"
  task load_amos_docs: :environment do
    puts "\n📚 Loading AMOS Documentation into System RAG...\n\n"

    docs_path = Rails.root.join("rag_sources", "system", "amos")

    unless Dir.exist?(docs_path)
      puts "❌ Directory not found: #{docs_path}"
      puts "   Create it with: mkdir -p #{docs_path}"
      exit 1
    end

    # Find all supported files
    files = Dir.glob(docs_path.join("**", "*")).select do |f|
      File.file?(f) && f.match?(/\.(md|pdf|docx|pptx|txt)$/i)
    end

    if files.empty?
      puts "⚠️  No documents found in #{docs_path}"
      puts "   Supported formats: .md, .pdf, .docx, .pptx, .txt"
      exit 0
    end

    puts "Found #{files.length} document(s)"
    puts ""

    # Process all files
    documents = files.map { |f| { type: 'file', content: f } }

    processor = DocumentProcessorService.new
    result = processor.process_documents(documents)

    if result[:success]
      puts "✅ Extracted #{result[:total_chunks]} chunks from #{files.length} files"

      # Create system RAG store
      rag_service = RagStoreService.new
      rag_result = rag_service.create_rag_store(
        "AMOS",
        result[:chunks],
        {
          store_type: 'system',
          entity: nil,
          user: nil,
          name: "AMOS Platform Documentation (System)",
          source_files: files.map { |f| f.gsub(Rails.root.to_s, '') }
        }
      )

      if rag_result[:success]
        puts "✅ Created RAG store: #{rag_result[:rag_store_id]}"
        puts "   Index: #{rag_result[:index_name]}"
        puts "   Namespace: #{rag_result[:namespace]}"
        puts "   Chunks: #{rag_result[:chunks_stored]}"
      else
        puts "❌ Failed to create RAG store: #{rag_result[:error]}"
      end
    else
      puts "❌ Document processing failed: #{result[:error]}"
    end
  end

  desc "Load integration docs from rag_sources/system/integrations/"
  task :load_integration_docs, [:integration_name] => :environment do |t, args|
    integration_name = args[:integration_name] || "all"

    puts "\n📚 Loading Integration Documentation...\n\n"

    base_path = Rails.root.join("rag_sources", "system", "integrations")

    unless Dir.exist?(base_path)
      puts "❌ Directory not found: #{base_path}"
      exit 1
    end

    # Determine which integrations to load
    if integration_name == "all"
      integration_dirs = Dir.glob(base_path.join("*")).select { |f| File.directory?(f) }
    else
      integration_dirs = [base_path.join(integration_name)]
    end

    integration_dirs.each do |int_dir|
      next unless Dir.exist?(int_dir)

      int_name = File.basename(int_dir).titleize
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "Processing: #{int_name}"
      puts ""

      # Find all files
      files = Dir.glob(File.join(int_dir, "**", "*")).select do |f|
        File.file?(f) && f.match?(/\.(md|pdf|docx|pptx|txt)$/i)
      end

      if files.empty?
        puts "⚠️  No documents found in #{int_dir}"
        next
      end

      puts "Found #{files.length} document(s)"

      # Process files
      documents = files.map { |f| { type: 'file', content: f } }

      processor = DocumentProcessorService.new
      result = processor.process_documents(documents)

      if result[:success]
        puts "✅ Extracted #{result[:total_chunks]} chunks"

        # Create system RAG store
        rag_service = RagStoreService.new
        rag_result = rag_service.create_rag_store(
          int_name,
          result[:chunks],
          {
            store_type: 'system',
            entity: nil,
            user: nil,
            name: "#{int_name} Integration Docs (System)",
            source_files: files.map { |f| f.gsub(Rails.root.to_s, '') }
          }
        )

        if rag_result[:success]
          puts "✅ Created RAG store: #{rag_result[:rag_store_id]}"
          puts "   Chunks: #{rag_result[:chunks_stored]}"
        else
          puts "❌ Failed to create RAG store: #{rag_result[:error]}"
        end
      else
        puts "❌ Processing failed: #{result[:error]}"
      end

      puts ""
    end

    puts "✅ Integration docs loading complete!"
  end

  desc "Populate system RAG with AMOS knowledge (from URLs)"
  task populate_system: :environment do
    puts "\n📚 Populating system RAG with AMOS knowledge...\n\n"

    # Integration documentation to index
    integrations = [
      {
        app_name: "Stripe",
        urls: [
          "https://stripe.com/docs/api",
          "https://stripe.com/docs/api/authentication",
          "https://stripe.com/docs/api/errors"
        ]
      },
      {
        app_name: "HubSpot",
        urls: [
          "https://developers.hubspot.com/docs/api/overview",
          "https://developers.hubspot.com/docs/api/crm/contacts"
        ]
      },
      {
        app_name: "Mailgun",
        urls: [
          "https://documentation.mailgun.com/en/latest/api_reference.html"
        ]
      }
    ]

    rag_service = RagStoreService.new
    success_count = 0
    error_count = 0

    integrations.each do |integration|
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "Processing: #{integration[:app_name]}"
      puts "URLs: #{integration[:urls].length}"
      puts ""

      begin
        # Process documents
        documents = integration[:urls].map { |url| { type: 'url', content: url } }

        processor = DocumentProcessorService.new
        result = processor.process_documents(documents)

        if result[:success]
          puts "✅ Extracted #{result[:total_chunks]} chunks"

          # Create system RAG store
          rag_result = rag_service.create_rag_store(
            integration[:app_name],
            result[:chunks],
            {
              store_type: 'system',  # System store (shared)
              entity: nil,           # No entity for system stores
              user: nil,
              name: "#{integration[:app_name]} Integration Docs (System)",
              source_urls: integration[:urls]
            }
          )

          if rag_result[:success]
            puts "✅ Created RAG store: #{rag_result[:rag_store_id]}"
            puts "   Index: #{rag_result[:index_name]}"
            puts "   Namespace: #{rag_result[:namespace]}"
            puts "   Chunks: #{rag_result[:chunks_stored]}"
            success_count += 1
          else
            puts "❌ Failed to create RAG store: #{rag_result[:error]}"
            error_count += 1
          end
        else
          puts "❌ Document processing failed: #{result[:error]}"
          error_count += 1
        end

      rescue => e
        puts "❌ Error: #{e.message}"
        puts e.backtrace.first(3).join("\n")
        error_count += 1
      end

      puts ""
    end

    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "\n📊 Summary:"
    puts "  ✅ Successfully indexed: #{success_count}"
    puts "  ❌ Failed: #{error_count}"
    puts "\n✅ System RAG population complete!"
  end

  desc "Check RAG store access for an entity"
  task :check_access, [:entity_id, :rag_store_id] => :environment do |t, args|
    unless args[:entity_id] && args[:rag_store_id]
      puts "Usage: rails rag:check_access[entity_id,rag_store_id]"
      exit 1
    end

    entity = Entity.find(args[:entity_id])
    rag_store = RagStore.find(args[:rag_store_id])

    puts "\n🔍 RAG Store Access Check\n\n"
    puts "Entity: #{entity.name} (ID: #{entity.id})"
    puts "RAG Store: #{rag_store.name} (ID: #{rag_store.id})"
    puts "Store Type: #{rag_store.store_type}"
    puts "Store Entity: #{rag_store.entity_id || 'system (no entity)'}"
    puts ""

    can_access = rag_store.accessible_by?(entity)

    if can_access
      puts "✅ Access: GRANTED"
      puts "   Entity #{entity.id} can access this RAG store"
    else
      puts "❌ Access: DENIED"
      puts "   Entity #{entity.id} cannot access this RAG store"
    end
  end

  desc "List all RAG stores with entity scoping"
  task list: :environment do
    puts "\n📚 All RAG Stores\n\n"

    RagStore.order(created_at: :desc).each do |store|
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "ID: #{store.id}"
      puts "Name: #{store.name}"
      puts "App: #{store.app_name}"
      puts "Type: #{store.store_type_system? ? '🌐 System' : '🏢 Entity'}"
      puts "Entity: #{store.entity_id ? "#{store.entity.name} (#{store.entity_id})" : 'N/A (system)'}" if store.entity_id || store.store_type_system?
      puts "Status: #{store.status}"
      puts "Chunks: #{store.chunk_count}"
      puts "Index: #{store.pinecone_index}"
      puts "Namespace: #{store.pinecone_namespace}"
      puts "Created: #{store.created_at.strftime('%Y-%m-%d %H:%M')}"
      puts ""
    end

    # Summary
    total = RagStore.count
    system_count = RagStore.system_stores.count
    entity_count = total - system_count

    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "\n📊 Summary:"
    puts "  Total: #{total}"
    puts "  🌐 System stores: #{system_count}"
    puts "  🏢 Entity stores: #{entity_count}"
  end

  desc "Test RAG query with entity scoping"
  task :test_query, [:entity_id, :app_name, :query] => :environment do |t, args|
    unless args[:entity_id] && args[:app_name] && args[:query]
      puts "Usage: rails rag:test_query[entity_id,app_name,'query text']"
      exit 1
    end

    entity = Entity.find(args[:entity_id])

    puts "\n🔍 Testing RAG Query\n\n"
    puts "Entity: #{entity.name} (ID: #{entity.id})"
    puts "App: #{args[:app_name]}"
    puts "Query: #{args[:query]}"
    puts ""

    # Find accessible RAG store
    rag_store = RagStore.accessible_by(entity)
                        .where(app_name: args[:app_name], status: "active")
                        .order(created_at: :desc)
                        .first

    if !rag_store
      puts "❌ No accessible RAG store found for #{args[:app_name]}"
      exit 1
    end

    puts "✅ Found RAG store: #{rag_store.name} (#{rag_store.store_type})"
    puts ""

    # Query
    rag_service = RagStoreService.new
    result = rag_service.query_rag_store(
      rag_store.id,
      args[:query],
      current_entity: entity,
      top_k: 3
    )

    if result[:success]
      puts "✅ Query successful!"
      puts "   Results: #{result[:results].length}"
      puts ""

      result[:results].each_with_index do |r, index|
        puts "━━━ Result #{index + 1} (Score: #{r[:score].round(4)}) ━━━"
        puts "Type: #{r[:type]}"
        puts "Source: #{r[:source]}"
        puts "Content:"
        puts r[:content][0..200] + "..."
        puts ""
      end
    else
      puts "❌ Query failed: #{result[:error]}"
    end
  end

  desc "Delete all RAG stores (use with caution!)"
  task :delete_all, [:confirm] => :environment do |t, args|
    if args[:confirm] != "YES"
      puts "\n⚠️  This will delete ALL RAG stores from the database and Pinecone!"
      puts "To confirm, run: rails rag:delete_all[YES]"
      exit 1
    end

    puts "\n🗑️  Deleting all RAG stores...\n\n"

    RagStore.find_each do |store|
      puts "Deleting: #{store.name} (#{store.id})"

      begin
        # TODO: Also delete from Pinecone namespace if needed
        store.destroy!
        puts "  ✅ Deleted"
      rescue => e
        puts "  ❌ Error: #{e.message}"
      end
    end

    puts "\n✅ All RAG stores deleted"
  end

  desc "Check RAG system health"
  task health: :environment do
    puts "\n🏥 RAG System Health Check\n\n"

    # Check Pinecone connection
    print "Pinecone: "
    begin
      client = Pinecone::Client.new
      client.list_indexes
      puts "✅ Connected"
    rescue => e
      puts "❌ Error: #{e.message}"
    end

    # Check OpenAI
    print "OpenAI: "
    begin
      openai = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
      puts "✅ Configured"
    rescue => e
      puts "❌ Error: #{e.message}"
    end

    # Check RAG stores
    puts "\nRAG Stores:"
    puts "  Total: #{RagStore.count}"
    puts "  Active: #{RagStore.active.count}"
    puts "  System: #{RagStore.system_stores.count}"
    puts "  Entity: #{RagStore.where(store_type: 'entity').count}"

    # Check Docling
    puts "\nDocling:"
    if DoclingBridgeService.available?
      puts "  ✅ Available"
    else
      puts "  ⚠️  Not installed (optional)"
    end

    # Check Embedding Cache
    puts "\nEmbedding Cache:"
    rag_service = RagStoreService.new
    cache_stats = rag_service.cache_stats

    if cache_stats[:enabled]
      puts "  ✅ Enabled (Redis connected)"
      puts "  Cached embeddings: #{cache_stats[:total_keys]}"
      puts "  Memory usage: #{cache_stats[:memory_usage]}"
      puts "  Hit rate: #{cache_stats[:hit_rate]}%"
      puts "  Total requests: #{cache_stats[:total_requests]}"
      puts "  Hits: #{cache_stats[:hits]} | Misses: #{cache_stats[:misses]}"
    else
      puts "  ⚠️  Disabled or Redis not available"
      puts "  Enable in .env: RAG_EMBEDDING_CACHE_ENABLED=true"
    end

    # Check RAG Configuration
    puts "\nRAG Configuration:"
    puts "  Chunking strategy: #{RagConfig.chunking_strategy}"
    puts "  Chunk size: #{RagConfig.chunk_size}"
    puts "  Chunk overlap: #{RagConfig.chunk_overlap}"
    puts "  Embedding model: #{RagConfig.embedding_model}"
    puts "  Embedding batch size: #{RagConfig.embedding_batch_size}"
    puts "  Cache enabled: #{RagConfig.embedding_cache_enabled?}"

    puts "\n✅ Health check complete"
  end

  desc "Show embedding cache statistics"
  task cache_stats: :environment do
    puts "\n📊 Embedding Cache Statistics\n\n"

    rag_service = RagStoreService.new
    stats = rag_service.cache_stats

    if stats[:enabled]
      puts "Status: ✅ Enabled"
      puts ""
      puts "Cache Performance:"
      puts "  Total requests: #{stats[:total_requests]}"
      puts "  Cache hits: #{stats[:hits]}"
      puts "  Cache misses: #{stats[:misses]}"
      puts "  Hit rate: #{stats[:hit_rate]}%"
      puts ""
      puts "Cache Storage:"
      puts "  Cached embeddings: #{stats[:total_keys]} / #{stats[:max_size]}"
      puts "  Memory usage: #{stats[:memory_usage]}"
      puts "  TTL: #{stats[:ttl_days]} days"
      puts ""

      # Calculate estimated savings
      if stats[:total_requests] > 0
        api_calls_saved = stats[:hits]
        cost_per_1k_tokens = 0.0001
        avg_tokens_per_chunk = 500
        estimated_savings = (api_calls_saved * avg_tokens_per_chunk / 1000.0) * cost_per_1k_tokens

        puts "Estimated Savings:"
        puts "  API calls avoided: #{api_calls_saved}"
        puts "  Cost savings: $#{estimated_savings.round(4)}"
      end
    else
      puts "Status: ❌ Disabled"
      puts ""
      puts "Reason: #{stats[:message]}"
      puts ""
      puts "To enable:"
      puts "  1. Ensure Redis is running"
      puts "  2. Set RAG_EMBEDDING_CACHE_ENABLED=true in .env"
      puts "  3. Restart application"
    end
  end

  desc "Clear embedding cache"
  task clear_cache: :environment do
    puts "\n🗑️  Clearing Embedding Cache...\n"

    rag_service = RagStoreService.new
    rag_service.clear_cache!

    puts "✅ Cache cleared successfully"
  end
end
