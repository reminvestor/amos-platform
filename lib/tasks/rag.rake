namespace :rag do
  desc "Populate system RAG with AMOS knowledge"
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

    puts "\n✅ Health check complete"
  end
end
