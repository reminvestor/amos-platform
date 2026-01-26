#!/bin/bash
# Logo generation script for ReelBooker using Gemini API
# Usage: ./scripts/generate_logo.sh "Your prompt here" output_filename
# Example: ./scripts/generate_logo.sh "Modern fish hook logo, teal colors" my_logo

set -e

# Load API key from .env if not set
if [ -z "$GEMINI_API_KEY" ]; then
  if [ -f ".env" ]; then
    export $(grep GEMINI_API_KEY .env | xargs)
  fi
fi

if [ -z "$GEMINI_API_KEY" ]; then
  echo "Error: GEMINI_API_KEY not set. Either export it or add to .env file"
  exit 1
fi

PROMPT="${1:-Create a modern app icon for ReelBooker fishing charter booking. Fish hook forming letter R, ocean blue to teal gradient, minimalist, square with rounded corners, no text.}"
OUTPUT="${2:-logo_$(date +%Y%m%d_%H%M%S)}"

# Ensure output directory exists
mkdir -p assets/icons

# Remove .png extension if provided
OUTPUT="${OUTPUT%.png}"

echo "Generating logo: assets/icons/$OUTPUT.png"
echo "Prompt: $PROMPT"
echo ""

RESPONSE=$(curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.0-pro:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"contents\": [{
      \"parts\": [{
        \"text\": \"$PROMPT\"
      }]
    }],
    \"generationConfig\": {
      \"responseModalities\": [\"TEXT\", \"IMAGE\"]
    }
  }")

# Extract and save image
IMAGE_DATA=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[] | select(.inlineData) | .inlineData.data')

if [ -z "$IMAGE_DATA" ] || [ "$IMAGE_DATA" = "null" ]; then
  echo "Error: No image generated. API response:"
  echo "$RESPONSE" | jq '.error // .candidates[0].content.parts[0].text // .'
  exit 1
fi

echo "$IMAGE_DATA" | base64 -d > "assets/icons/${OUTPUT}.png"

# Check if file was created successfully
if [ -s "assets/icons/${OUTPUT}.png" ]; then
  echo "✓ Successfully saved: assets/icons/${OUTPUT}.png"
  echo "  Size: $(ls -lh "assets/icons/${OUTPUT}.png" | awk '{print $5}')"
else
  echo "Error: Generated file is empty"
  exit 1
fi
