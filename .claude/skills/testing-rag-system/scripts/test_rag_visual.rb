#!/usr/bin/env ruby
# Visual RAG Testing Script
# Run with: docker-compose exec web rails runner scripts/test_rag_visual.rb

require 'colorize'

puts "\n" + "="*80
puts "🧪 AMOS RAG SYSTEM - VISUAL TEST".center(80).colorize(:cyan).bold
puts "="*80 + "\n"

# Step 1: Environment Check
puts "\n📋 STEP 1: Environment Check".colorize(:yellow).bold
puts "-" * 80

api_keys = {
  "OpenAI" => ENV['OPENAI_API_KEY'],
  "Pinecone" => ENV['PINECONE_API_KEY'],
  "Redis" => ENV['REDIS_URL']
}

api_keys.each do |name, value|
  if value && !value.empty?
    masked = value.length > 20 ? "#{value[0..15]}..." : "#{value[0..7]}..."
    puts "  ✅ #{name.ljust(12)} #{masked}".colorize(:green)
  else
    puts "  ❌ #{name.ljust(12)} Not set".colorize(:red)
  end
end

# Check if we can proceed
can_test = api_keys.values.all? { |v| v && !v.empty? }

unless can_test
  puts "\n⚠️  Missing API keys. Set them in .env and restart Docker.".colorize(:red)
  puts "   See: docs/RAG_TESTING_GUIDE.md"
  exit 1
end

# Step 2: Database Check
puts "\n📊 STEP 2: Database Check".colorize(:yellow).bold
puts "-" * 80

begin
  entity_count = Entity.count
  user_count = User.count
  rag_count = RagStore.count

  puts "  Entities: #{entity_count}".colorize(:green)
  puts "  Users: #{user_count}".colorize(:green)
  puts "  Existing RAG Stores: #{rag_count}".colorize(:green)

  if entity_count == 0
    puts "\n  ❌ No entities found! Run: rails db:seed".colorize(:red)
    exit 1
  end
rescue => e
  puts "  ❌ Database error: #{e.message}".colorize(:red)
  exit 1
end

# Step 3: Initialize RAG Service
puts "\n🔧 STEP 3: Initialize RAG Service".colorize(:yellow).bold
puts "-" * 80

begin
  service = RagStoreService.new
  puts "  ✅ RagStoreService initialized".colorize(:green)
  puts "  ✅ Pinecone client: #{service.instance_variable_get(:@pinecone).class}".colorize(:green)
  puts "  ✅ OpenAI client: #{service.instance_variable_get(:@openai_client).class}".colorize(:green)
  puts "  ✅ Cache enabled: #{service.instance_variable_get(:@cache_enabled)}".colorize(:green)
rescue => e
  puts "  ❌ Service initialization failed: #{e.message}".colorize(:red)
  exit 1
end

# Step 4: Create Test RAG Store (Entity-Scoped)
puts "\n📝 STEP 4: Create Entity-Scoped RAG Store".colorize(:yellow).bold
puts "-" * 80

entity = Entity.first
user = entity.users.first || entity.users.create!(email: "test@example.com", password: "password123")

puts "  Using Entity: ##{entity.id} - #{entity.name || 'Unnamed'}"
puts "  Using User: ##{user.id} - #{user.email}"
puts ""

test_chunks = [
  {
    content: "AMOS is a conversational AI platform that uses AWS Bedrock and Claude for intelligent marketing automation.",
    metadata: {
      source: "docs/introduction.md",
      page: 1,
      type: "documentation",
      heading: "What is AMOS?"
    }
  },
  {
    content: "The RAG (Retrieval-Augmented Generation) system in AMOS uses Pinecone for vector storage with multi-tenant namespace isolation.",
    metadata: {
      source: "docs/rag-architecture.md",
      page: 1,
      type: "documentation",
      heading: "RAG Architecture"
    }
  },
  {
    content: "Each entity gets isolated namespaces in the format: entity_{id}_{app_name}_{timestamp}. This ensures complete data separation.",
    metadata: {
      source: "docs/rag-architecture.md",
      page: 2,
      type: "documentation",
      heading: "Multi-Tenant Isolation"
    }
  }
]

puts "  Creating RAG store with #{test_chunks.length} chunks..."

begin
  result = service.create_rag_store(
    "amos-visual-test",
    test_chunks,
    {
      entity: entity,
      user: user,
      name: "AMOS Visual Test Documentation",
      store_type: "entity"
    }
  )

  if result[:success]
    rag_store = result[:rag_store]
    puts "\n  ✅ RAG Store Created Successfully!".colorize(:green).bold
    puts ""
    puts "  📦 Store Details:".colorize(:cyan)
    puts "     ID: #{rag_store.id}"
    puts "     Name: #{rag_store.name}"
    puts "     Type: #{rag_store.store_type}"
    puts "     Entity ID: #{rag_store.entity_id}"
    puts "     Chunk Count: #{rag_store.chunk_count}"
    puts "     Pinecone Index: #{rag_store.pinecone_index}"
    puts "     Namespace: #{rag_store.pinecone_namespace}".colorize(:yellow)
    puts ""
    puts "  📊 Metadata:".colorize(:cyan)
    puts "     Page filtering: #{rag_store.supports_page_filtering ? '✅' : '❌'}"
    puts "     Heading search: #{rag_store.supports_heading_search ? '✅' : '❌'}"
    puts "     Chunks with pages: #{rag_store.chunks_with_pages}"
    puts "     Chunks with headings: #{rag_store.chunks_with_headings}"
  else
    puts "\n  ❌ Failed to create RAG store: #{result[:error]}".colorize(:red)
    exit 1
  end
rescue => e
  puts "\n  ❌ Error: #{e.message}".colorize(:red)
  puts "  #{e.class}".colorize(:red)
  puts "\n  This likely means:"
  if e.message.include?("quota") || e.message.include?("429")
    puts "    - OpenAI quota exceeded. Add credits at platform.openai.com"
  elsif e.message.include?("401") || e.message.include?("Invalid API Key")
    puts "    - API key is invalid. Get new key from:"
    puts "      OpenAI: https://platform.openai.com/api-keys"
    puts "      Pinecone: https://app.pinecone.io"
  elsif e.message.include?("Index") && e.message.include?("not found")
    puts "    - Pinecone indexes not created. Create at app.pinecone.io:"
    puts "      • amos-system-knowledge (1536 dims, cosine)"
    puts "      • amos-entity-knowledge (1536 dims, cosine)"
  end
  exit 1
end

# Step 5: Query the RAG Store
puts "\n🔍 STEP 5: Query RAG Store".colorize(:yellow).bold
puts "-" * 80

test_queries = [
  "What is AMOS?",
  "How does RAG work in AMOS?",
  "Explain multi-tenant isolation"
]

test_queries.each_with_index do |query, i|
  puts "\n  Query #{i + 1}: \"#{query}\"".colorize(:cyan).bold

  begin
    results = service.query_rag_store(
      rag_store.id,
      query,
      current_entity: entity,
      top_k: 2
    )

    puts "  Found #{results.length} result(s):".colorize(:green)

    results.each_with_index do |result, j|
      puts ""
      puts "  #{j + 1}. Score: #{(result[:score] * 100).round(1)}%".colorize(:yellow)
      puts "     Content: #{result[:content][0..120]}...".colorize(:white)
      puts "     Source: #{result[:source]}".colorize(:light_black)
      puts "     Type: #{result[:type]}".colorize(:light_black)
    end
  rescue => e
    puts "  ❌ Query failed: #{e.message}".colorize(:red)
  end
end

# Step 6: Test Access Control (Multi-Tenant Isolation)
puts "\n🔐 STEP 6: Test Multi-Tenant Isolation".colorize(:yellow).bold
puts "-" * 80

if Entity.count > 1
  other_entity = Entity.where.not(id: entity.id).first

  puts "  Attempting to access Entity #{entity.id}'s store from Entity #{other_entity.id}..."

  begin
    service.query_rag_store(rag_store.id, "test", current_entity: other_entity)
    puts "  ❌ SECURITY FAILURE: Cross-entity access allowed!".colorize(:red).bold
  rescue SecurityError => e
    puts "  ✅ Access Denied (as expected)".colorize(:green).bold
    puts "     Error: #{e.message}".colorize(:light_black)
  end
else
  puts "  ⚠️  Only 1 entity exists - skipping cross-entity test".colorize(:yellow)
  puts "     Run: rails db:seed to create more entities"
end

# Step 7: Create System Store (Shared)
puts "\n🌍 STEP 7: Create System Store (Shared Knowledge)".colorize(:yellow).bold
puts "-" * 80

system_chunks = [
  {
    content: "Stripe API allows you to create customers, subscriptions, and process payments programmatically.",
    metadata: {
      source: "stripe.com/docs/api",
      type: "api_docs"
    }
  }
]

puts "  Creating system RAG store (accessible to all entities)..."

begin
  system_result = service.create_rag_store(
    "stripe-api-test",
    system_chunks,
    {
      name: "Stripe API Test Docs",
      store_type: "system"
    }
  )

  if system_result[:success]
    system_store = system_result[:rag_store]
    puts "\n  ✅ System Store Created!".colorize(:green).bold
    puts "     ID: #{system_store.id}"
    puts "     Type: #{system_store.store_type}"
    puts "     Entity ID: #{system_store.entity_id.inspect} (nil = shared)"
    puts "     Namespace: #{system_store.pinecone_namespace}".colorize(:yellow)

    # Test that both entities can access
    puts "\n  Testing system store access..."
    results1 = service.query_rag_store(system_store.id, "stripe API", current_entity: entity)
    puts "  ✅ Entity #{entity.id} can access (#{results1.length} results)".colorize(:green)

    if Entity.count > 1
      results2 = service.query_rag_store(system_store.id, "stripe API", current_entity: other_entity)
      puts "  ✅ Entity #{other_entity.id} can access (#{results2.length} results)".colorize(:green)
    end
  end
rescue => e
  puts "  ❌ System store creation failed: #{e.message}".colorize(:red)
end

# Step 8: Display Summary
puts "\n📊 STEP 8: Summary".colorize(:yellow).bold
puts "-" * 80

all_stores = RagStore.all
entity_stores = all_stores.where(store_type: 'entity')
system_stores = all_stores.where(store_type: 'system')

puts "\n  Total RAG Stores: #{all_stores.count}"
puts "    • Entity stores: #{entity_stores.count}"
puts "    • System stores: #{system_stores.count}"
puts ""

if all_stores.any?
  puts "  Recent RAG Stores:".colorize(:cyan)
  all_stores.order(created_at: :desc).limit(5).each do |store|
    icon = store.store_type == 'system' ? '🌍' : '🔒'
    entity_info = store.entity_id ? " (Entity ##{store.entity_id})" : " (Shared)"
    puts "    #{icon} #{store.name}#{entity_info}"
    puts "       Namespace: #{store.pinecone_namespace}".colorize(:light_black)
  end
end

# Step 9: Cleanup Prompt
puts "\n🧹 STEP 9: Cleanup".colorize(:yellow).bold
puts "-" * 80

puts "\n  Test stores created. To clean up, run in Rails console:"
puts "    RagStore.where(\"name LIKE '%Test%'\").destroy_all".colorize(:yellow)
puts ""
puts "  Or to keep them for manual testing, visit: http://localhost:3000"
puts ""

# Final Status
puts "\n" + "="*80
puts "✅ RAG SYSTEM TEST COMPLETE!".center(80).colorize(:green).bold
puts "="*80 + "\n"

puts "Next steps:".colorize(:cyan)
puts "  1. Visit http://localhost:3000 and try Scout chat"
puts "  2. Upload a PDF document in Scout"
puts "  3. Ask questions about the uploaded document"
puts "  4. Check Rails logs: docker-compose logs -f web"
puts ""
