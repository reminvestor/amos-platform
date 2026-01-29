#!/bin/bash
# Batch logo generation for ReelBooker
# Usage: ./scripts/generate_logo_batch.sh [count]
# Generates multiple logo variations using preset prompts

set -e

# Load API key from .env if not set
if [ -z "$GEMINI_API_KEY" ]; then
  if [ -f ".env" ]; then
    export $(grep GEMINI_API_KEY .env | xargs)
  fi
fi

if [ -z "$GEMINI_API_KEY" ]; then
  echo "Error: GEMINI_API_KEY not set"
  exit 1
fi

BATCH_DIR="assets/icons/batch_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BATCH_DIR"

# Preset prompts for ReelBooker logos
PROMPTS=(
  "Create a premium app icon for ReelBooker fishing charter booking. Sleek fish hook forming letter R, gradient from deep navy #0D2137 to teal #0d9488, subtle metallic shimmer, square with rounded corners, no text, App Store quality"
  "Design minimalist app icon for ReelBooker. Stylized marlin fish leaping in dynamic arc, ocean blue #1a365d and teal #0d9488 gradient, clean lines, modern aesthetic, square app icon, no text"
  "Create elegant RB monogram app icon for ReelBooker fishing charters. Letters interweave with subtle fish hook element, deep ocean gradient, luxurious premium travel brand feel, square rounded corners, no text"
  "Design circular badge app icon for ReelBooker. Fishing boat silhouette on calm waters at golden hour, warm sunset to deep teal transition, atmospheric inspiring premium aesthetic, no text"
  "Create modern geometric app icon for ReelBooker. Abstract fish made of clean geometric triangles and lines, teal #0d9488 and navy #1a365d, flat design with subtle gradients, minimalist tech aesthetic, no text"
  "Design app icon showing stylized fishing reel mechanism. Reel handle forms subtle R shape, metallic chrome on deep ocean blue #0D2137 with teal accents, premium mechanical precision aesthetic, no text"
  "Create underwater perspective app icon for ReelBooker. View looking up at surface with sun rays piercing through, fish silhouettes, deep blue to teal gradient, magical dreamy atmosphere, square format, no text"
  "Design wave-inspired app icon for ReelBooker. Stylized ocean wave forming fish tail shape, teal #0d9488 and deep blue, dynamic motion feeling, modern surf brand aesthetic, square rounded corners, no text"
  "Create night fishing app icon. Silhouette of fishing rod with taut line against starry sky and moon reflection on water, deep navy blue with silver accents, peaceful premium aesthetic, no text"
  "Design sportfishing trophy app icon for ReelBooker. Stylized sailfish in victory pose, chrome/gold metallic on deep ocean blue, premium championship quality feel, square format, no text"
)

COUNT=${1:-5}

echo "Generating $COUNT logo variations to $BATCH_DIR/"
echo ""

for ((i=0; i<COUNT && i<${#PROMPTS[@]}; i++)); do
  PROMPT="${PROMPTS[$i]}"
  OUTPUT="logo_$((i+1))"

  echo "[$((i+1))/$COUNT] Generating ${OUTPUT}..."

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

  IMAGE_DATA=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[] | select(.inlineData) | .inlineData.data')

  if [ -n "$IMAGE_DATA" ] && [ "$IMAGE_DATA" != "null" ]; then
    echo "$IMAGE_DATA" | base64 -d > "${BATCH_DIR}/${OUTPUT}.png"
    if [ -s "${BATCH_DIR}/${OUTPUT}.png" ]; then
      SIZE=$(ls -lh "${BATCH_DIR}/${OUTPUT}.png" | awk '{print $5}')
      echo "  ✓ Saved: ${BATCH_DIR}/${OUTPUT}.png ($SIZE)"
    else
      echo "  ✗ Failed: empty file"
    fi
  else
    echo "  ✗ Failed: no image in response"
  fi

  # Rate limiting
  if [ $((i+1)) -lt $COUNT ]; then
    sleep 2
  fi
done

echo ""
echo "Done! Check $BATCH_DIR/"
ls -la "${BATCH_DIR}/"*.png 2>/dev/null || echo "No files generated"
