#!/bin/bash
# RAG system operations via Docker Compose

set -e

RAG_ACTION="${1:-health}"

echo "🔍 Running RAG operation: $RAG_ACTION"

case "$RAG_ACTION" in
  health)
    docker-compose exec web rails rag:health
    ;;

  verify)
    echo "Checking Docling..."
    docker-compose exec web python3 -c "import docling; print('✅ Docling v' + docling.__version__)"
    echo ""
    echo "Checking environment..."
    docker-compose exec web bash -c '
      [ -n "$OPENAI_API_KEY" ] && echo "✅ OPENAI_API_KEY set" || echo "❌ OPENAI_API_KEY missing"
      [ -n "$PINECONE_API_KEY" ] && echo "✅ PINECONE_API_KEY set" || echo "❌ PINECONE_API_KEY missing"
    '
    ;;

  seed)
    docker-compose exec web rails rag:populate_system
    ;;

  list)
    docker-compose exec web rails rag:list
    ;;

  test)
    docker-compose exec web rails runner '
      user = User.first || User.create!(
        email: "test@example.com",
        password: "password123",
        entity: Entity.first || Entity.create!(name: "Test Entity")
      )
      chunks = [{ content: "Test RAG content", metadata: { source: "test" } }]
      service = RagStoreService.new
      result = service.create_rag_store("test", chunks, { entity: user.entity, user: user, name: "Test" })
      puts "✅ RAG test successful! Store ID: #{result[:rag_store].id}"
    '
    ;;

  *)
    echo "❌ Unknown rag action: $RAG_ACTION"
    echo "Available: health, verify, seed, list, test"
    exit 1
    ;;
esac
