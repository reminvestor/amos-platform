# Voice Assistant Setup Guide

## Overview

The AMOS Voice Assistant provides natural voice interaction with Scout chat, enabling users to speak to the AI and receive spoken responses. This guide covers setup, configuration, and usage.

## Architecture

```
User Voice → Deepgram (STT) → Scout Chat → AI Agent → Polly (TTS) → User Hears Response
```

**Key Features**:
- < 1 second latency (target: 500-1000ms)
- Barge-in support (interrupt AI mid-sentence)
- Full Scout functionality via voice
- Keyword boosting for domain-specific terms
- Client-direct architecture for minimal latency

## Prerequisites

### 1. Deepgram Account
- Sign up at https://console.deepgram.com/
- Create an API key
- Note your project ID

### 2. AWS Account (for Polly)
- Already configured if using AWS Bedrock
- Ensure IAM user has `polly:SynthesizeSpeech` permission

### 3. HTTPS Required
- Voice assistant requires secure context (HTTPS)
- Works on localhost for development

## Installation

### Step 1: Install NPM Dependencies

```bash
# Add AWS SDK for Polly
yarn add @aws-sdk/client-polly
```

### Step 2: Configure Environment Variables

Add to your `.env` file:

```bash
# Deepgram
DEEPGRAM_API_KEY=your_deepgram_api_key_here
DEEPGRAM_WEBHOOK_SECRET=your_webhook_secret_here

# AWS (if not already configured)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key

# Optional
VOICE_ASSISTANT_ENABLED=true
POLLY_VOICE_ID=Matthew
POLLY_ENGINE=neural
```

### Step 3: Configure Deepgram Webhook

In Deepgram console, configure webhook URL:

```
https://your-domain.com/api/voice/webhooks/deepgram
```

**Metadata to send**:
```json
{
  "extra": {
    "session_id": "{{ session_id }}"
  }
}
```

### Step 4: Run Database Migration

```bash
docker compose exec web rails db:migrate
```

### Step 5: Add Voice Button to Scout UI

The voice toggle button is automatically available in Scout chat via the `voice_assistant_controller.js` Stimulus controller.

## Usage

### For Users

1. **Open Scout Chat** at `/scout`
2. **Click the 🎤 Voice button** in the chat interface
3. **Grant microphone permission** when browser prompts
4. **Speak your request** naturally
5. **AI responds** with voice and text
6. **Interrupt anytime** (barge-in) by speaking over the AI
7. **Click Stop** to end voice session

### Voice Commands

All Scout functionality works via voice:

**Examples**:
- "Create a landing page for my SaaS product"
- "Send an email campaign to my customers"
- "Show me my campaign analytics"
- "Add a new contact named John Smith"
- "What's my email open rate this month?"

## API Endpoints

### Create Voice Session
```http
POST /api/voice/sessions
```

**Response**:
```json
{
  "session_id": "uuid",
  "status": "active",
  "started_at": "2025-10-20T15:30:00Z",
  "websocket_channel": "VoiceChannel:uuid"
}
```

### Get Deepgram Credentials
```http
GET /api/voice/sessions/:session_id/deepgram_key
```

**Response**:
```json
{
  "api_key": "temp_key",
  "websocket_url": "wss://api.deepgram.com/v1/listen",
  "expires_at": "2025-10-20T15:45:00Z",
  "config": {
    "model": "nova-3",
    "language": "en-US",
    "keywords": ["contact_name", "product_name"]
  }
}
```

### Get Polly Credentials
```http
GET /api/voice/sessions/:session_id/polly_credentials
```

**Response**:
```json
{
  "access_key_id": "ASIA...",
  "secret_access_key": "...",
  "session_token": "...",
  "region": "us-east-1",
  "expiration": "2025-10-20T15:45:00Z",
  "voice_config": {
    "voice_id": "Matthew",
    "engine": "neural",
    "output_format": "pcm",
    "sample_rate": "16000"
  }
}
```

### Pause/Resume/End Session
```http
PATCH /api/voice/sessions/:session_id/pause
PATCH /api/voice/sessions/:session_id/resume
PATCH /api/voice/sessions/:session_id/end
```

## WebSocket Events (Action Cable)

### Subscribe to VoiceChannel

```javascript
const channel = consumer.subscriptions.create(
  { channel: "VoiceChannel", session_id: "uuid" },
  {
    received(data) {
      switch (data.type) {
        case "response":
          // AI response - synthesize with Polly
          break
        case "status":
          // Status update: thinking, idle, error
          break
        case "canvas":
          // Canvas data from Scout
          break
      }
    }
  }
)
```

### Event Types

| Type | Description | Payload |
|------|-------------|---------|
| `response` | Final AI response | `{ content, should_synthesize }` |
| `partial_response` | Streaming response chunk | `{ content }` |
| `status` | Status update | `{ status: "thinking" \| "idle" \| "error" }` |
| `error` | Error message | `{ message }` |
| `canvas` | Canvas update from Scout | `{ data }` |

## Integration with Scout

The voice assistant is fully integrated with Scout chat:

1. **Voice transcripts** are saved to Scout's Redis conversation history
2. **Agent responses** use Scout's `ScoutGenericToolsServiceV2`
3. **All Scout tools** are available (campaigns, landing pages, contacts, etc.)
4. **Canvas updates** work via voice (e.g., landing page editor loads)
5. **Conversation history** persists across voice and text sessions

## Architecture Details

### Client-Side Flow

```javascript
// 1. User clicks voice button
toggleVoice()
  → createVoiceSession()
  → getDeepgramCredentials()
  → getPollyCredentials()
  → startAudioCapture()  // WebRTC
  → connectDeepgram()    // WebSocket
  → connectVoiceChannel() // Action Cable

// 2. User speaks
MediaStream → ScriptProcessor → PCM conversion → Deepgram WebSocket

// 3. Deepgram processes
Deepgram → Interim transcripts (client-side only)
Deepgram → Final transcript → Webhook → Rails

// 4. Rails processes
Webhook → VoiceAgentService → Scout chat → ScoutGenericToolsServiceV2
  → AI response → Action Cable → Client

// 5. Client speaks response
Action Cable → Polly SynthesizeSpeech → MP3 → Audio element → Playback
```

### Server-Side Flow

```ruby
# Webhook receives final transcript
DeepgramWebhooksController
  → Verify signature
  → Find VoiceSession by session_id
  → Save to Scout Redis history
  → Broadcast via Action Cable
  → Enqueue VoiceAgentJob

# Background job processes
VoiceAgentJob
  → VoiceAgentService.new(voice_session, transcript).process
    → ScoutGenericToolsServiceV2 (main_chat loadout)
    → Stream response via Action Cable
    → Save assistant message to Scout history
```

## Security

### Ephemeral Credentials

- **Deepgram keys**: 15-minute TTL, scoped to `usage:write`
- **Polly credentials**: 15-minute TTL, scoped to `polly:SynthesizeSpeech`
- **Session-specific**: Tagged with session_id for audit trail

### Webhook Verification

```ruby
signature = request.headers["X-Deepgram-Signature"]
valid = DeepgramService.validate_webhook_signature(payload, signature)
```

Uses HMAC-SHA256 with `DEEPGRAM_WEBHOOK_SECRET`.

### Entity Scoping

- All voice sessions belong to entity
- Action Cable subscriptions verified against `current_user.entity_id`
- Scout tools respect entity boundaries

## Monitoring

### Key Metrics

```sql
-- Active voice sessions
SELECT COUNT(*) FROM voice_sessions WHERE status = 'active';

-- Average session duration
SELECT AVG(EXTRACT(EPOCH FROM (ended_at - started_at)))
FROM voice_sessions WHERE status = 'ended';

-- Transcripts per session
SELECT session_id, jsonb_array_length(transcript_history)
FROM voice_sessions;
```

### Logs

```ruby
Rails.logger.info({
  event: "voice_to_scout",
  session_id: voice_session.session_id,
  transcript: transcript
}.to_json)
```

## Troubleshooting

### Microphone Permission Denied

**Error**: `NotAllowedError: Permission denied`

**Solution**: User must grant microphone permission in browser. Requires HTTPS (or localhost).

### Deepgram Connection Failed

**Error**: `WebSocket connection failed`

**Solution**:
1. Check `DEEPGRAM_API_KEY` is set
2. Verify API key has credits
3. Check network/firewall allows WebSocket connections

### Polly Synthesis Failed

**Error**: `AccessDenied` or `InvalidSignature`

**Solution**:
1. Check AWS credentials are valid
2. Verify IAM user has `polly:SynthesizeSpeech` permission
3. Check AWS region matches configuration

### No Response from Agent

**Error**: VoiceChannel receives status "thinking" but no response

**Solution**:
1. Check `VoiceAgentJob` is processing (SolidQueue)
2. Review Rails logs for errors in `VoiceAgentService`
3. Verify Scout chat is working (test with text input)

### Audio Choppy or Delayed

**Issue**: High latency or audio stuttering

**Solution**:
1. Check network latency to AWS/Deepgram
2. Reduce audio buffer size in `ScriptProcessor`
3. Use `standard` engine instead of `neural` for Polly (faster but lower quality)

## Performance Optimization

### Reduce Latency

1. **Use Polly Standard Engine** (if < 200ms required):
   ```ruby
   # In PollyCredentialsService
   DEFAULT_ENGINE = "standard"  # vs "neural"
   ```

2. **Increase Audio Buffer Size** (if network is slow):
   ```javascript
   // In voice_assistant_controller.js
   const processor = this.audioContext.createScriptProcessor(8192, 1, 1)  // vs 4096
   ```

3. **Reduce Conversation History** (if Agent is slow):
   ```ruby
   # In VoiceAgentService
   conversation_history = load_scout_history(10)  # vs 20
   ```

### Cost Optimization

**Current costs per user**:
- Light (30 min/month): ~$0.50/month
- Medium (100 min/month): ~$1.50/month
- Heavy (500 min/month): ~$8/month

**To reduce**:
1. Use Polly Standard ($4/1M chars vs $16/1M for Neural)
2. Implement wake word to avoid 24/7 streaming
3. Use AWS Transcribe if already on full AWS stack (though 4x more expensive than Deepgram)

## Future Enhancements

- Wake word detection (Porcupine/OpenWakeWord)
- Multi-language support
- Voice biometrics for authentication
- Emotion detection
- Custom voice per entity (voice cloning)

## Support

For issues or questions:
- GitHub Issues: https://github.com/NuvolaNetworks/agent_marketing/issues
- Documentation: /docs/VOICE_ASSISTANT_ARCHITECTURE.md
- Architecture: /docs/VOICE_ASSISTANT_ARCHITECTURE.md

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
