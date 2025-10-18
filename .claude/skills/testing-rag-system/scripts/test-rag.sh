#!/bin/bash
# Visual RAG System Test
# Usage: ./scripts/test-rag.sh

echo "🧪 Starting RAG Visual Test..."
echo ""
echo "This will:"
echo "  1. Check environment and API keys"
echo "  2. Create test RAG stores (entity + system)"
echo "  3. Query and display results"
echo "  4. Test multi-tenant isolation"
echo "  5. Show visual output with colors"
echo ""
echo "Prerequisites:"
echo "  ✓ Docker services running"
echo "  ✓ OPENAI_API_KEY set in .env"
echo "  ✓ PINECONE_API_KEY set in .env"
echo "  ✓ Pinecone indexes created"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

docker-compose exec web rails runner scripts/test_rag_visual.rb
