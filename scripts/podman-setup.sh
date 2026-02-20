#!/bin/bash

# Container setup script for AMOS
# Works with both Podman and Docker

set -e

echo "AMOS Container Setup"
echo "=============================="
echo ""

# Detect container engine
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/bin/detect-container-engine"

echo "Using: $CONTAINER_CMD"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "No .env file found. Creating from .env.example..."
    cp .env.example .env
    echo "Created .env file"
    echo ""
    echo "Please edit .env and add your credentials:"
    echo "   - AWS_ACCESS_KEY_ID"
    echo "   - AWS_SECRET_ACCESS_KEY"
    echo "   - OPENAI_API_KEY (for RAG embeddings)"
    echo "   - PINECONE_API_KEY (for RAG vector store)"
    echo "   - PINECONE_ENVIRONMENT (e.g., us-east-1)"
    echo ""
    read -p "Press Enter after updating .env to continue..."
fi

echo "Building containers..."
$COMPOSE_CMD build

echo ""
echo "Starting services..."
$COMPOSE_CMD up -d db redis

echo "Waiting for database to be ready..."
sleep 5

echo ""
echo "Setting up database..."
$COMPOSE_CMD run --rm web rails db:create db:migrate

echo ""
echo "Seeding database..."
$COMPOSE_CMD run --rm web rails db:seed

echo ""
echo "Checking Docling installation..."
$COMPOSE_CMD run --rm web python3 -c "import docling; print(f'Docling v{docling.__version__} installed')" || echo "Docling not installed - RAG will use standard processing"

echo ""
echo "Setup complete!"
echo ""
echo "To start AMOS:"
echo "  $COMPOSE_CMD up"
echo ""
echo "To populate system RAG:"
echo "  $COMPOSE_CMD run --rm web rails rag:populate_system"
echo ""
echo "To check RAG health:"
echo "  $COMPOSE_CMD run --rm web rails rag:health"
echo ""
echo "AMOS will be available at: http://localhost:3000"
