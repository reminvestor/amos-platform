# Voice Assistant Architecture

## Overview

AMOS Voice Assistant provides natural, conversational AI interactions with ultra-low latency (< 300ms) through direct client-to-vendor streaming. This document outlines the architecture, design decisions, and implementation guidelines.

## Core Philosophy

**"Useful, Not a Gimmick"** - We prioritize natural conversation feel over demo polish. The system must be production-ready with:
- Sub-300ms latency targets
- Seamless barge-in (interrupt AI mid-sentence)
- Multi-agent workflow support for complex operations
- Graceful handling of long-running tasks

## Architecture Diagram

```
┌─────────────┐
│   Client    │
│ (Web/Mobile)│
└──────┬──────┘
       │
       ├─────────────────────────────────────────┐
       │                                         │
       │ ① Fetch ephemeral                ② Audio Stream
       │    Deepgram key                     (WebSocket)
       ▼                                         ▼
┌─────────────┐                          ┌─────────────┐
│    Rails    │◄─── ③ Webhook ──────────│  Deepgram   │
│   Server    │    (Final Transcript)    │   API       │
└──────┬──────┘                          └─────────────┘
       │
       │ ④ Push updates
       │    (Action Cable)
       ▼
┌─────────────┐
│  Multi-Agent│
│  Workflow   │
│   Engine    │
└─────────────┘
```

## Design Decisions

### ✅ What Rails DOES (Control Plane)

1. **Mint ephemeral Deepgram API keys** for clients (15-30 minute TTL)
2. **Receive final transcripts** via Deepgram webhooks
3. **Push text updates** to UI via Action Cable/AnyCable
4. **Handle multi-agent workflows** and tool orchestration (email, calendar, CRM)
5. **Store session context** for keyword boosting (contact names, custom vocabulary)
6. **Synthesize speech with Amazon Polly Neural** and stream audio chunks, OR generate presigned AWS credentials for client-side synthesis

### ❌ What Rails Does NOT Do

1. **Stream raw audio through Action Cable** - This adds latency and complexity
2. **Process audio directly** - All audio flows client → Deepgram directly
3. **Block on long-running operations** - Use progressive/streaming responses

## Technology Stack

### Speech-to-Text (STT)

**Primary: Deepgram**
- **Model**: Nova-3 streaming with Flux for turn detection
- **Cost**: $0.0077/min
- **Features**:
  - Keyword/keyterm boosting for domain-specific terms
  - Semantic turn detection (not just silence timeout)
  - Clean WebSocket API
  - Best developer experience with Rails
- **Latency**: < 200-300ms first interim

**Secondary: AWS Transcribe** (feature flag)
- **Cost**: ~$0.03/min (T1, volume discounts available)
- **Features**:
  - Deep AWS integration
  - Diarization, language ID
  - Custom vocabularies
- **Use Case**: AWS-first organizations or when Deepgram is unavailable

**Offline Fallback: faster-whisper**
- **Use Case**: Tunnels, dead zones, offline mode
- **Latency**: ~1-3s (too slow for primary, acceptable for fallback)

### Text-to-Speech (TTS)

**Primary: Amazon Polly Neural (AWS-Native)**
- **Voices**: Neural voices (e.g., Matthew, Joanna, Ruth, Stephen)
- **Cost**: ~$16 per 1 million characters (Neural), ~$4 per 1 million characters (Standard)
- **Latency**: 200-500ms first-audio
- **Why Polly**:
  - Already in AWS ecosystem (same IAM, region, billing as Bedrock)
  - No cross-cloud complexity
  - Streaming synthesis with speech marks for word-level timing
  - Enables clean interruption at word boundaries
- **Features**:
  - Speech marks (word, sentence, viseme, SSML) for precise barge-in
  - Streaming synthesis - don't wait for complete generation
  - Keep connections warm to avoid cold-start latency

**Implementation Options**:

1. **Client synthesizes directly** (Option 2 - RECOMMENDED - Lower Latency)
   ```
   Rails → Generate presigned Polly credentials →
   → Client calls Polly directly → Client plays
   ```
   - **Pros**:
     - Same pattern as Deepgram STT (consistent architecture)
     - Lowest latency (direct to Polly, no Rails proxy)
     - Reduced server load
     - Better scalability
   - **Cons**:
     - More client-side complexity
     - Requires AWS SDK in browser

2. **Rails synthesizes and streams** (Option 1 - Alternative)
   ```
   Rails → Polly SynthesizeSpeech (streaming) →
   → Audio chunks via Action Cable → Client plays
   ```
   - Pros: Centralized control, easier monitoring
   - Cons: Higher latency through Action Cable, increased server load

**Recommendation**: Use Option 2 (client-direct) for consistency with Deepgram STT architecture and to minimize latency. Client already has AWS credential handling for Deepgram, so adding Polly is straightforward.

**Alternative: Full AWS Path** (Future Consideration)
- If Deepgram pricing/complexity becomes an issue, could switch to AWS Transcribe Streaming (~$0.03/min)
- Everything in one cloud: Transcribe + Bedrock + Polly
- Trade-off: Higher STT cost ($0.03/min vs $0.0077/min), more complex client auth
- Current recommendation: Stick with Deepgram (better DX, lower cost) + Polly

### Real-Time Communication

- **Action Cable** (or AnyCable for scale) for server → client updates
- **WebRTC** for client audio capture
- **WebSocket** for client ↔ Deepgram streaming

## Critical Requirements

### 1. Latency Targets (Make or Break UX)

| Component | Target | Notes |
|-----------|--------|-------|
| ASR first interim | < 200-300ms | Time to first word transcription |
| Agent intent processing | < 200ms | After end-of-turn detection |
| TTS first audio | < 200-500ms | Time to first audio chunk (Polly Neural) |
| Total round-trip | < 500-1000ms | User stops talking → AI starts speaking |

### 2. Barge-In (Non-Negotiable)

**Requirement**: System must stop speaking instantly when user talks

**Implementation**:
- Deepgram Flux model provides semantic turn detection (not just silence timeout)
- Client implements Voice Activity Detection (VAD)
- Polly speech marks enable word-level timing for clean interruption
- TTS playback stops immediately on VAD trigger at word boundary
- Cancels pending TTS requests and clears audio buffer

**Why Critical**: Without barge-in, conversations feel robotic and frustrating. Speech marks allow interrupting mid-sentence at natural word boundaries.

### 3. Multi-Agent Workflow Support

**Challenge**: Some workflows take time (e.g., "Send email to all customers who bought in Q4")

**Solution**: Streaming/Progressive Responses
- Keep user informed with status updates via Action Cable
- Use "thinking" indicators or partial results
- Agent remains interruptible during long operations
- Break operations into speakable chunks

**Example Flow**:
```
User: "Send an email to everyone who bought last month"
AI: "Looking up customers from last month..." [streaming]
AI: "Found 47 customers. Drafting email..." [streaming]
AI: "Would you like to review the email before I send it?"
```

## Implementation Guide

### Phase 1: Core Infrastructure

1. **VoiceSession Model**
   ```ruby
   # Store conversation state
   - user_id, entity_id
   - session_id (UUID)
   - status (active, paused, ended)
   - context (JSON: keywords, contact names, etc.)
   - transcript_history (JSON array)
   ```

2. **DeepgramService**
   ```ruby
   # Handles Deepgram integration
   - generate_ephemeral_key(session_id, ttl_minutes: 15)
   - build_websocket_config(keywords: [], language: 'en-US')
   - validate_webhook_signature(payload, signature)
   ```

3. **API Endpoints**
   ```ruby
   POST /api/voice/sessions          # Start new session
   GET  /api/voice/sessions/:id/key  # Get ephemeral Deepgram key
   POST /api/voice/webhooks/deepgram # Receive final transcripts
   ```

4. **Webhooks Controller**
   ```ruby
   # Process Deepgram callbacks
   - Verify signature
   - Store final transcript
   - Trigger agent workflow
   - Broadcast via Action Cable
   ```

### Phase 2: Client Implementation

1. **WebRTC Audio Capture**
   ```javascript
   // 16kHz mono with echo cancellation
   const constraints = {
     audio: {
       sampleRate: 16000,
       channelCount: 1,
       echoCancellation: true,
       noiseSuppression: true,
       autoGainControl: true
     }
   };
   ```

2. **Deepgram WebSocket Client**
   ```javascript
   // Direct connection (NOT through Rails)
   const ws = new WebSocket('wss://api.deepgram.com/v1/listen', {
     headers: { Authorization: `Token ${ephemeralKey}` }
   });
   ```

3. **Voice Activity Detection (VAD)**
   ```javascript
   // Detect when user starts speaking
   // Stop TTS immediately
   // Signal barge-in to server
   ```

### Phase 3: Agent Integration

1. **VoiceAgentService**
   ```ruby
   # Process voice transcripts through existing agent system
   - Parse intent from transcript
   - Route to appropriate workflow
   - Stream responses back via Action Cable
   - Handle tool calls (email, calendar, CRM)
   ```

2. **Action Cable Channel**
   ```ruby
   # VoiceChannel
   - Subscribe to session
   - Broadcast transcript updates
   - Broadcast agent responses
   - Broadcast status updates
   ```

### Phase 4: TTS Integration (Client-Direct Option 2)

1. **PollyCredentialsService**
   ```ruby
   # Generate temporary AWS credentials for Polly access
   - generate_presigned_credentials(session_id, ttl_minutes: 15)
   - Scope credentials to Polly:SynthesizeSpeech only
   - Include session-specific IAM policy
   - Log credential usage for audit
   ```

2. **API Endpoint for Polly Credentials**
   ```ruby
   # POST /api/voice/sessions/:id/polly_credentials
   # Returns:
   {
     access_key_id: 'ASIA...',
     secret_access_key: '...',
     session_token: '...',
     region: 'us-east-1',
     voice_config: {
       voice_id: 'Matthew',
       engine: 'neural',
       output_format: 'pcm',
       sample_rate: '16000'
     }
   }
   ```

3. **Client-Side Polly Integration**
   ```javascript
   // Import AWS SDK for JavaScript v3
   import { PollyClient, SynthesizeSpeechCommand } from '@aws-sdk/client-polly';

   // Fetch credentials from Rails
   const creds = await fetch('/api/voice/sessions/123/polly_credentials');

   // Initialize Polly client
   const polly = new PollyClient({
     region: creds.region,
     credentials: {
       accessKeyId: creds.access_key_id,
       secretAccessKey: creds.secret_access_key,
       sessionToken: creds.session_token
     }
   });

   // Synthesize speech directly
   const command = new SynthesizeSpeechCommand({
     Text: agentResponse,
     VoiceId: 'Matthew',
     Engine: 'neural',
     OutputFormat: 'pcm',
     SampleRate: '16000'
   });

   const audioStream = await polly.send(command);
   // Play audio stream with Web Audio API
   ```

4. **Speech Marks for Barge-In**
   ```javascript
   // Request speech marks alongside audio
   const marksCommand = new SynthesizeSpeechCommand({
     Text: agentResponse,
     VoiceId: 'Matthew',
     Engine: 'neural',
     OutputFormat: 'json',  // Get speech marks
     SpeechMarkTypes: ['word', 'sentence']
   });

   // Parse marks for word-level timing
   const marks = await polly.send(marksCommand);
   // Use marks to interrupt at word boundaries on barge-in
   ```

5. **Polly Configuration**
   ```ruby
   # config/aws_polly.yml
   voice_id: 'Matthew'  # Or Joanna, Ruth, Stephen
   engine: 'neural'     # Neural for quality, standard for speed
   output_format: 'pcm' # For streaming
   sample_rate: '16000' # Match Deepgram
   speech_mark_types:
     - word
     - sentence
   ttl_minutes: 15      # Credential lifetime
   ```

### Phase 5: Production Features

1. **Feature Flags**
   - `voice_assistant_enabled` - Global enable/disable
   - `stt_provider` - deepgram (primary), aws_transcribe (secondary), whisper (offline)
   - `tts_provider` - polly (primary), google (fallback), azure (fallback)
   - `tts_implementation` - rails_streaming (Option 1), client_direct (Option 2)
   - `polly_voice_warming_enabled` - Keep Polly connections warm

2. **Wake Word Detection** (Optional)
   - Porcupine or OpenWakeWord
   - On-device processing
   - Avoids 24/7 streaming
   - Reduces bandwidth and cost

3. **Regional Fallbacks**
   - Handle Deepgram outages
   - Automatic provider switching (Deepgram → AWS Transcribe)
   - Graceful degradation
   - Alert monitoring team on failover

4. **Polly Voice Caching/Warming**
   - Keep connections warm to reduce cold-start latency
   - Pre-synthesize common phrases ("Hello", "One moment", "I'm looking that up")
   - Cache frequently used responses

## Security Considerations

### 1. Ephemeral Keys
- Short TTL (15-30 minutes)
- Single-use per session
- Scoped to specific user/entity
- Logged for audit trail

### 2. Webhook Verification
- Verify Deepgram signature
- Validate session ownership
- Rate limiting per entity

### 3. Audio Data
- Never store raw audio (privacy/cost)
- Store transcripts only (encrypted at rest)
- Respect user privacy preferences
- GDPR/CCPA compliance

## Cost Estimation

### Deepgram STT
- **Price**: $0.0077/min
- **Usage**: 1,000 minutes/month = $7.70/month
- **Scale**: 10,000 minutes/month = $77/month

### Amazon Polly Neural TTS
- **Price**: $16 per 1M characters (Neural), $4 per 1M characters (Standard)
- **Assumption**: Average response ~150 characters
- **Usage**: 1,000 responses/month = 150K chars = $2.40/month (Neural)
- **Scale**: 10,000 responses/month = 1.5M chars = $24/month (Neural)

### Cost Comparison: Polly vs Alternatives
| Provider | Price | Notes |
|----------|-------|-------|
| Polly Neural | $16/1M chars | Best AWS integration, speech marks |
| Polly Standard | $4/1M chars | Lower quality, still acceptable |
| Google Neural2 | $16/1M chars | Similar pricing, cross-cloud complexity |
| Azure Neural | $16/1M chars | Similar pricing, cross-cloud complexity |

### Total Cost per User
- **Light user** (30 min/month, 200 responses): ~$0.50/month (STT + TTS)
- **Medium user** (100 min/month, 650 responses): ~$1.50/month
- **Heavy user** (500 min/month, 3,300 responses): ~$8/month

### Alternative: Full AWS Path
- **AWS Transcribe**: ~$0.03/min (4x more expensive than Deepgram)
- **AWS Polly Neural**: $16/1M chars
- **Total for medium user**: ~$4/month (vs $1.50 with Deepgram)
- **Trade-off**: Unified AWS stack, but higher cost

## Performance Monitoring

### Key Metrics

1. **Latency Metrics**
   - Time to first interim transcript
   - Agent processing time
   - Time to first audio
   - Total round-trip time

2. **Quality Metrics**
   - Transcript accuracy (WER - Word Error Rate)
   - Barge-in success rate
   - User satisfaction ratings

3. **System Metrics**
   - Concurrent sessions
   - Webhook processing time
   - Action Cable message delivery time
   - API error rates

### Alerts

- Latency > 500ms (P1)
- WER > 10% (P2)
- API error rate > 1% (P1)
- Session creation failures (P0)

## Testing Strategy

### Unit Tests
- DeepgramService key generation
- Webhook signature verification
- VoiceAgentService intent parsing

### Integration Tests
- End-to-end session flow
- Webhook processing
- Action Cable broadcasting

### Load Tests
- 100 concurrent sessions
- 1,000 sessions/hour creation rate
- Webhook burst handling

### Manual QA
- Barge-in responsiveness
- Audio quality
- Conversation naturalness
- Multi-turn context retention

## Migration Path

### Phase 1: Beta (Weeks 1-2)
- Core infrastructure
- Deepgram integration
- Basic client implementation
- Internal testing only

### Phase 2: Alpha Release (Weeks 3-4)
- TTS integration
- Multi-agent workflow support
- Limited user rollout (10% traffic)
- Feature flag control

### Phase 3: General Availability (Weeks 5-6)
- Full production release
- All users enabled
- Monitoring and optimization
- Documentation and training

## Future Enhancements

### Near-Term (3-6 months)
- Multi-language support
- Voice biometrics for authentication
- Custom wake words per entity
- Conversation analytics dashboard

### Long-Term (6-12 months)
- Emotion detection in voice
- Multi-speaker diarization
- Real-time translation
- Voice cloning for branded responses

## References

- [Deepgram API Documentation](https://developers.deepgram.com/)
- [Amazon Polly Documentation](https://docs.aws.amazon.com/polly/)
- [Amazon Polly Speech Marks](https://docs.aws.amazon.com/polly/latest/dg/speechmarks.html)
- [AWS Transcribe Streaming](https://docs.aws.amazon.com/transcribe/latest/dg/streaming.html)
- [WebRTC Best Practices](https://webrtc.org/getting-started/overview)
- [Action Cable Guide](https://guides.rubyonrails.org/action_cable_overview.html)

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-10-20 | Use Deepgram over AWS Transcribe | Better DX, lower cost ($0.0077/min vs $0.03/min), semantic turn detection |
| 2025-10-20 | Client-direct WebSocket vs Rails proxy | Reduces latency by 50-100ms, simpler architecture |
| 2025-10-20 | Amazon Polly Neural over Google/Azure TTS | AWS-native (same IAM/region/billing as Bedrock), speech marks for word-level timing, no cross-cloud complexity |
| 2025-10-20 | Use client-direct TTS (Option 2) | Consistent with Deepgram STT architecture, lowest latency, reduced server load, better scalability |
| 2025-10-20 | Skip GPT-4o Realtime for now | Less control over tools and workflows, vendor lock-in |
| 2025-10-20 | Keep Deepgram + Polly over full AWS | Deepgram is 4x cheaper than Transcribe, better DX, worth managing two vendors |

---

**Document Version**: 1.2
**Last Updated**: 2025-10-20
**Owner**: Engineering Team
**Review Cycle**: Monthly

**Changelog**:
- v1.2 (2025-10-20): Updated to use client-direct TTS (Option 2) as primary implementation for consistency with STT and lowest latency
- v1.1 (2025-10-20): Updated TTS from Google Cloud to Amazon Polly Neural for AWS-native integration
- v1.0 (2025-10-20): Initial architecture document
