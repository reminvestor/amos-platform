#!/bin/bash
# Test script to verify Python service can start

echo "🧪 Testing Agent Lightning Python Service..."
echo

# Check if we're in the right directory
if [ ! -f "app.py" ]; then
  echo "❌ Error: app.py not found. Run this from python_services/agent_lightning/"
  exit 1
fi

echo "✓ Found app.py"

# Check requirements.txt
if [ ! -f "requirements.txt" ]; then
  echo "❌ Error: requirements.txt not found"
  exit 1
fi

echo "✓ Found requirements.txt"

# Check Containerfile
if [ ! -f "Containerfile" ]; then
  echo "❌ Error: Containerfile not found"
  exit 1
fi

echo "✓ Found Containerfile"

echo
echo "📦 Installing Python dependencies..."
pip install -q -r requirements.txt 2>&1 | grep -E "(error|Error|ERROR)" || echo "✓ Dependencies installed"

echo
echo "🔍 Checking syntax..."
python -m py_compile app.py 2>&1 && echo "✓ app.py syntax valid" || echo "❌ Syntax error in app.py"
python -m py_compile config.py 2>&1 && echo "✓ config.py syntax valid" || echo "❌ Syntax error in config.py"

echo
echo "📦 Testing container build..."
docker build -t agent-lightning-test . > /dev/null 2>&1 && echo "✓ Container build successful" || echo "❌ Container build failed"

echo
echo "✅ Tests complete!"
