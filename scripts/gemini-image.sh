#!/bin/bash
# Generate images using Gemini API
# Usage: ./scripts/gemini-image.sh "prompt" [output_filename]

set -e

if [ -z "$GEMINI_API_KEY" ]; then
  echo "Error: GEMINI_API_KEY environment variable not set"
  echo "Get your API key from: https://aistudio.google.com/apikey"
  echo "Then run: export GEMINI_API_KEY='your-key-here'"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: ./scripts/gemini-image.sh \"prompt\" [output_filename]"
  echo ""
  echo "Examples:"
  echo "  ./scripts/gemini-image.sh \"A modern fish hook logo, teal color\""
  echo "  ./scripts/gemini-image.sh \"Sailfish jumping, ocean blue\" sailfish.png"
  exit 1
fi

PROMPT="$1"
OUTPUT="${2:-gemini_$(date +%Y%m%d_%H%M%S).png}"

echo "Generating image..."
echo "Prompt: $PROMPT"
echo "Output: $OUTPUT"

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

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error from API:"
  echo "$RESPONSE" | jq '.error'
  exit 1
fi

# Extract and save image
IMAGE_DATA=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[] | select(.inlineData) | .inlineData.data')

if [ -z "$IMAGE_DATA" ] || [ "$IMAGE_DATA" = "null" ]; then
  echo "No image in response. Text response:"
  echo "$RESPONSE" | jq -r '.candidates[0].content.parts[] | select(.text) | .text'
  exit 1
fi

echo "$IMAGE_DATA" | base64 -d > "$OUTPUT"
echo "Saved to: $OUTPUT"

# Show file info
if command -v file &> /dev/null; then
  file "$OUTPUT"
fi
