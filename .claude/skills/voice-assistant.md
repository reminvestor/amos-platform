# Voice Assistant Skill

This skill helps you understand and modify the voice assistant feature in AMOS.

## Architecture Overview

The voice assistant enables real-time voice conversations with Scout AI through:

1. **Browser** → Captures audio via MediaRecorder API (16kHz, mono, linear16 PCM)
2. **Deepgram** → Speech-to-Text (STT) via WebSocket
3. **Scout AI** → Processes the transcript
4. **Browser TTS** → Web Speech API for responses (Polly removed for performance)

## Key Features

- **Wake Word Detection**: "Hey Amos", "Hi Amos", or "Amos" triggers commands
- **Continuous Listening**: Hands-free mode - say wake word, get response, continue
- **Transcript Buffering**: Combines split transcripts from Deepgram (handles natural pauses)
- **Performance Optimized**: 16kHz sample rate (telephony quality, 66% less data than 48kHz)
- **Cross-Platform**: Works on desktop and mobile browsers with microphone access

## File Locations

### Frontend (JavaScript)
- **Controller**: `app/javascript/controllers/voice_assistant_controller.js`
- **View Integration**: `app/views/scout/index.html.erb` (microphone button at line 376-382)

### Backend (Rails)
- **API Controller**: `app/controllers/api/voice/voice_sessions_controller.rb`
- **Deepgram Service**: `app/services/deepgram_service.rb`
- **Model**: `app/models/voice_session.rb`
- **Action Cable Channel**: `app/channels/voice_channel.rb`

### Configuration
- **Settings Model**: `app/models/voice_assistant_setting.rb`
- **Admin UI**: `app/controllers/admin/voice_settings_controller.rb`
- **Routes**: `config/routes.rb` (search for `/api/voice`)

## How It Works (Step-by-Step)

### 1. Initialization Flow

```
User clicks 🎤 button
  ↓
toggleVoice() called
  ↓
startVoice() begins 4-step process:
  1. Create VoiceSession (POST /api/voice/sessions)
  2. Connect to Action Cable (VoiceChannel)
  3. Get Deepgram credentials (GET /api/voice/sessions/:id/deepgram_key)
  4. Request microphone permission & connect to Deepgram WebSocket (getUserMedia)
```

### 2. Critical Authentication Detail

**IMPORTANT**: Deepgram WebSocket connections from browsers MUST use `Sec-WebSocket-Protocol` header:

```javascript
// ✅ CORRECT (browser-compatible)
new WebSocket(url, ['token', api_key])

// ❌ WRONG (causes 1006 errors)
new WebSocket(`${url}?token=${api_key}`)
```

This is documented in Deepgram's browser authentication guide. The browser security model prohibits custom headers, so the token must be passed via the WebSocket protocol handshake.

### 3. Audio Streaming Flow

```
MediaRecorder captures audio (250ms chunks, 16kHz mono)
  ↓
ondataavailable event fires
  ↓
Blob sent to Deepgram WebSocket
  ↓
Deepgram returns interim + final transcripts
  ↓
addToTranscriptBuffer() accumulates finals for 500ms
  ↓
processBufferedTranscript() combines split speech
  ↓
processWakeWord() detects "Hey Amos" (or accepts any speech in continuous mode)
  ↓
Send cleaned transcript to Scout AI
  ↓
Scout responds (streaming SSE)
  ↓
Browser TTS speaks response (speechSynthesis API)
  ↓
In continuous mode: Wait for next wake word
```

### 4. Wake Word & Continuous Listening

**Wake Word Processing**:
- Detects: "hey amos", "hi amos", "amos" (case-insensitive, punctuation removed)
- Strips wake word from command before sending to Scout
- Example: "Hey Amos, show my campaigns" → Scout receives "show my campaigns"

**Continuous Mode**:
- Click mic once to start
- Say: "Hey Amos, show campaigns" → Responds → Still listening
- Say: "Hey Amos, create campaign" → Responds → Still listening
- Auto-stops after 5 minutes or manual button click
- After first command, wake word is OPTIONAL (natural conversation)

**Transcript Buffering**:
- Deepgram may split speech: "Hey," then "Amos create campaign."
- Buffer waits 500ms for more speech
- Combines: "Hey, Amos create campaign." → Detects wake word correctly

### 4. Timing Considerations

**Microphone Initialization Delay**: 500ms
- Location: `connectDeepgram()` onopen handler
- Reason: Prevents cutting off first few milliseconds of speech
- **Adjustable**: Change the `setTimeout` value if needed

**MediaRecorder Chunk Size**: 250ms
- Location: `mediaRecorder.start(250)`
- Reason: Balance between latency and efficiency
- **Adjustable**: Smaller = lower latency, higher overhead

**Deepgram Endpointing**: 300ms
- Location: `VoiceAssistantSetting.get("deepgram.endpointing", 300)`
- Reason: How long to wait for silence before finalizing
- **Adjustable**: Via admin UI or database

## Common Modifications

### Adjust Voice Detection Sensitivity

```ruby
# In Rails console or seed file
VoiceAssistantSetting.set("deepgram.endpointing", 500) # Wait longer for pauses
VoiceAssistantSetting.set("deepgram.utterance_end_ms", 1000) # Finalize after 1s silence
```

### Change Microphone Initialization Delay

```javascript
// In voice_assistant_controller.js, connectDeepgram() method
setTimeout(() => {
  this.streamAudioToDeepgram()
}, 1000) // Increase from 500ms to 1000ms
```

### Modify Audio Quality

```javascript
// In streamAudioToDeepgram() method
const options = {
  mimeType: 'audio/webm;codecs=opus',
  audioBitsPerSecond: 32000 // Increase from 16000 for better quality
}
```

## Known Issues

### Deprecation Warning: ScriptProcessorNode
**Symptom**: Console shows "The ScriptProcessorNode is deprecated. Use AudioWorkletNode instead."

**Impact**: None - this is just a warning. The feature works perfectly.

**Why we use it**: ScriptProcessorNode is the original working implementation. We tried MediaRecorder (the modern approach) but it had audio format compatibility issues with Deepgram.

**Future improvement**: Migrate to AudioWorkletNode for modern audio processing (post-demo task)

**Current status**: ✅ Works reliably for demo, safe to ignore warning

## Troubleshooting Guide

### Issue: WebSocket Connection Fails (Code 1006)

**Symptom**: Console shows "WebSocket connection error (Ready State: CLOSED)"

**Causes**:
1. **Wrong authentication method** - Must use `Sec-WebSocket-Protocol` header
2. **API key lacks permissions** - Check Deepgram dashboard for streaming access
3. **CORS issue** - Should not happen with Sec-WebSocket-Protocol

**Fix**:
```javascript
// Verify in voice_assistant_controller.js line ~317
this.deepgramSocket = new WebSocket(wsUrl, ['token', creds.api_key])
// NOT: new WebSocket(`${wsUrl}?token=${creds.api_key}`)
```

### Issue: Microphone Cuts Off First Word

**Symptom**: First word or two are not transcribed

**Cause**: MediaRecorder starts before microphone is fully ready

**Fix**: Increase initialization delay
```javascript
// In connectDeepgram() onopen handler
setTimeout(() => {
  this.streamAudioToDeepgram()
}, 1000) // Increase from 500ms
```

### Issue: Recordings Stop Unexpectedly

**Symptom**: Recording stops after a few seconds

**Cause**: Using deprecated `createScriptProcessor` API

**Fix**: Ensure you're using `MediaRecorder` (already fixed in current code)
```javascript
// Should see this in code:
this.mediaRecorder = new MediaRecorder(this.mediaStream, options)
// NOT: createScriptProcessor
```

### Issue: Long Pauses Between Words Not Detected as Separate Utterances

**Symptom**: Multiple sentences run together

**Cause**: Endpointing timeout too long

**Fix**:
```ruby
VoiceAssistantSetting.set("deepgram.utterance_end_ms", 500) # Shorter pause detection
```

### Issue: Too Sensitive - Cuts Off Mid-Sentence

**Symptom**: Sentences get split incorrectly

**Cause**: Endpointing timeout too short

**Fix**:
```ruby
VoiceAssistantSetting.set("deepgram.utterance_end_ms", 1200) # Wait longer
VoiceAssistantSetting.set("deepgram.endpointing", 400)
```

## Testing Changes

### 1. Rebuild JavaScript

```bash
docker compose exec web yarn build
```

### 2. Hard Refresh Browser

Press `Cmd+Shift+R` (Mac) or `Ctrl+Shift+R` (Windows/Linux)

### 3. Check Console Logs

Look for:
- ✅ "Deepgram WebSocket connected"
- ✅ "MediaRecorder created with mimeType: audio/webm;codecs=opus"
- ✅ "Microphone fully initialized and streaming"
- ✅ "Final transcript: [your words]"

## Configuration Reference

### Deepgram Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| `deepgram.model` | `nova-3` | STT model (nova-3, nova-2, base) |
| `deepgram.language` | `en-US` | Language code |
| `deepgram.sample_rate` | `48000` | Audio sample rate (Hz) - higher = better accuracy |
| `deepgram.channels` | `1` | Mono (1) or stereo (2) |
| `deepgram.punctuate` | `true` | Add punctuation |
| `deepgram.interim_results` | `true` | Show live captions |
| `deepgram.endpointing` | `1500` | Silence detection (ms) |
| `deepgram.utterance_end_ms` | `2000` | Finalize after silence (ms) |
| `deepgram.vad_events` | `true` | Voice activity detection |
| `deepgram.smart_format` | `true` | Better number/date formatting |

## Performance Optimizations (Implemented)

### 1. Polly TTS Removal (412ms saved per response)
**Problem**: AWS Polly added 412ms latency bottleneck
**Solution**: Switched to browser's native `speechSynthesis` API
**Impact**: Eliminated 412ms delay, reduced complexity

### 2. Sample Rate: 48kHz → 16kHz (66% data reduction)
**Problem**: 48kHz is music quality - overkill for voice (human speech: 300-3400Hz)
**Solution**: Reduced to 16kHz (telephony standard - same as Alexa, Siri, Zoom)
**Impact**:
- 66% less network bandwidth
- 66% less Deepgram processing
- Faster transmission
- Lower costs
- **Location**: `voice_assistant_controller.js` line ~150 (`sampleRate: 16000`)

### 3. Conversation History Truncation (40% token reduction)
**Problem**: Conversation history growing unbounded → 7000+ tokens per request
**Solution**: Truncate to last 6 messages (3 exchanges), compress long messages
**Impact**:
- Before: 10 messages, ~7000 tokens
- After: 6 messages, ~4200 tokens
- **Location**: `scout_generic_tools_service_v2.rb` `format_conversation_for_ai()`

###  4. System Prompt Compression (70% reduction: 3000→900 tokens)
**Problem**: Verbose system prompt with ASCII art, excessive examples
**Solution**: Removed bloat, consolidated sections, 1 example per concept
**Impact**:
- Before: 3000 tokens
- After: 900 tokens
- Saved: 2100 tokens
- **Location**: `scout_generic_tools_service_v2.rb` `build_system_prompt()`

### 5. Debug Logging Removal
**Problem**: High-frequency console.log causing performance overhead
**Solution**: Removed verbose Deepgram message logging (fired every ~100ms)
**Impact**: Reduced console spam from 10+ messages/sec to ~2 messages/session

### 6. Transcript Buffer Timeout: 800ms → 500ms
**Problem**: Added latency waiting for speech completion
**Solution**: Reduced wait time by 300ms
**Impact**: 37.5% faster transcript finalization

**Overall Performance**:
- Combined optimizations: ~7000 tokens → ~5000 tokens per request (28% faster)
- Response time: More consistent, no degradation over long conversations
- **Note**: Prompt caching NOT available (AWS Bedrock limitation)

### Additional Latency Optimizations

1. **Smaller chunk size**: `mediaRecorder.start(100)` (from 250ms)
2. **Faster endpointing**: `deepgram.endpointing = 200`
3. **Skip interim results**: `deepgram.interim_results = false`

### Accuracy Improvements

1. **Better model**: `deepgram.model = "nova-2"` (current default)
2. **Add keywords**: Pass business terms to `websocket_config(keywords: ['Acme', 'Q4'])`
3. **Enable smart format**: `deepgram.smart_format = true`

## Security Notes

- **Never commit API keys** - Use environment variables
- **Use ephemeral keys** - Generate temporary keys for client-side use (requires Deepgram plan upgrade)
- **Validate sessions** - VoiceSessionsController checks entity ownership

## Related Documentation

- Main docs: `docs/VOICE_ASSISTANT_ADMIN_GUIDE.md`
- Deepgram API: https://developers.deepgram.com/docs
- MediaRecorder API: https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder
- Web Speech API: https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesis

## Additional Deepgram Features (Not Yet Enabled)

**Note**: Some features require higher Deepgram plan tiers or only work in batch mode (not streaming). The following caused WebSocket errors (code 1006) and were removed:
- ❌ `detect_entities` - Requires premium plan
- ❌ `paragraphs` - Not supported in streaming mode
- ❌ `utterances` - Conflicts with real-time processing

These features can potentially be added to `deepgram_service.rb` config if your plan supports them:

### **Sentiment Analysis** 😊😡
```ruby
config[:sentiment] = true
```
**Use case**: Detect frustrated customers → escalate priority

### **Language Detection** 🌍
```ruby
config[:detect_language] = true
```
**Use case**: Auto-detect Spanish, French, German, etc. (Nova-3 supports 10 languages)

### **PII Redaction** 🔒
```ruby
config[:redact] = ['pci', 'ssn', 'numbers']
```
**Use case**: Protect credit cards, SSNs in transcripts for compliance

### **Summarization** 📋
```ruby
config[:summarize] = true
```
**Use case**: Get AI summary of long voice conversations

### **Topic Detection** 🏷️
```ruby
config[:detect_topics] = true
```
**Use case**: Automatically categorize conversations (sales, support, billing)

### **Replace/Profanity Filter** 🤐
```ruby
config[:replace] = ['badword:replacement']
config[:profanity_filter] = true
```
**Use case**: Clean up transcripts for public display

## Quick Reference Commands

```bash
# View current settings
docker compose exec web rails runner "VoiceAssistantSetting.all.each { |s| puts \"#{s.key}: #{s.value}\" }"

# Update a setting
docker compose exec web rails runner "VoiceAssistantSetting.set('deepgram.endpointing', 400)"

# Test Deepgram API key
docker compose exec web bash -c 'curl -s -X GET "https://api.deepgram.com/v1/projects" -H "Authorization: Token ${DEEPGRAM_API_KEY}"'

# Rebuild assets
docker compose exec web yarn build

# View voice sessions
docker compose exec web rails runner "VoiceSession.last(5).each { |s| puts \"#{s.session_id}: #{s.status}\" }"
```
