#!/bin/bash

# Docker Compose setup script for AMOS feature branch
# This script helps set up and run AMOS with Docker Compose

set -e

echo "🐳 AMOS Docker Compose Setup"
echo "=============================="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "⚠️  No .env file found. Creating from .env.example..."
    cp .env.example .env
    echo "✅ Created .env file"
    echo ""
    echo "📝 Please edit .env and add your credentials:"
    echo "   - AWS_ACCESS_KEY_ID"
    echo "   - AWS_SECRET_ACCESS_KEY"
    echo "   - OPENAI_API_KEY (for RAG embeddings)"
    echo "   - PINECONE_API_KEY (for RAG vector store)"
    echo "   - PINECONE_ENVIRONMENT (e.g., us-east-1)"
    echo ""
    read -p "Press Enter after updating .env to continue..."
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo "❌ Docker or docker-compose not found. Please install Docker Desktop."
    exit 1
fi

# Determine docker compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

echo "📦 Building Docker containers..."
$DOCKER_COMPOSE build

echo ""
echo "🚀 Starting services..."
$DOCKER_COMPOSE up -d db redis

echo "⏳ Waiting for database to be ready..."
sleep 5

echo ""
echo "🔧 Setting up database..."
$DOCKER_COMPOSE run --rm web rails db:create db:migrate

echo ""
echo "🌱 Seeding database..."
$DOCKER_COMPOSE run --rm web rails db:seed

echo ""
echo "📚 Checking Docling installation..."
$DOCKER_COMPOSE run --rm web python3 -c "import docling; print(f'✅ Docling v{docling.__version__} installed')" || echo "⚠️  Docling not installed - RAG will use standard processing"

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start AMOS:"
echo "  $DOCKER_COMPOSE up"
echo ""
echo "To populate system RAG:"
echo "  $DOCKER_COMPOSE run --rm web rails rag:populate_system"
echo ""
echo "To check RAG health:"
echo "  $DOCKER_COMPOSE run --rm web rails rag:health"
echo ""
echo "To check Docling:"
echo "  $DOCKER_COMPOSE run --rm web rails docling:check"
echo ""
echo "AMOS will be available at: http://localhost:3000"
