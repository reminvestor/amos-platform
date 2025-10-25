# Voice Assistant Skill

This skill helps you understand and modify the voice assistant feature in AMOS.

## Architecture Overview

The voice assistant enables real-time voice conversations with Scout AI through:

1. **Browser** → Captures audio via MediaRecorder API
2. **Deepgram** → Speech-to-Text (STT) via WebSocket
3. **Scout AI** → Processes the transcript
4. **AWS Polly** → Text-to-Speech (TTS) for responses

## File Locations

### Frontend (JavaScript)
- **Controller**: `app/javascript/controllers/voice_assistant_controller.js`
- **View Integration**: `app/views/scout/index.html.erb` (microphone button at line 376-382)

### Backend (Rails)
- **API Controller**: `app/controllers/api/voice/voice_sessions_controller.rb`
- **Deepgram Service**: `app/services/deepgram_service.rb`
- **Polly Service**: `app/services/polly_credentials_service.rb`
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
startVoice() begins 6-step process:
  1. Create VoiceSession (POST /api/voice/sessions)
  2. Connect to Action Cable (VoiceChannel)
  3. Get Deepgram credentials (GET /api/voice/sessions/:id/deepgram_key)
  4. Get Polly credentials (GET /api/voice/sessions/:id/polly_credentials)
  5. Request microphone permission (getUserMedia)
  6. Connect to Deepgram WebSocket
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
MediaRecorder captures audio (250ms chunks)
  ↓
ondataavailable event fires
  ↓
Blob sent to Deepgram WebSocket
  ↓
Deepgram returns transcript
  ↓
handleDeepgramMessage processes it
  ↓
If final: Send to Scout AI
  ↓
Scout responds via VoiceChannel
  ↓
synthesizeSpeech with AWS Polly
```

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

### Change Voice (Polly)

```ruby
# In VoiceAssistantSetting
VoiceAssistantSetting.set("polly.voice_id", "Joanna") # US English Female
VoiceAssistantSetting.set("polly.voice_id", "Matthew") # US English Male
VoiceAssistantSetting.set("polly.engine", "neural") # Better quality
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

### Polly Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| `polly.voice_id` | `Joanna` | Voice name |
| `polly.engine` | `neural` | Engine (neural or standard) |
| `polly.output_format` | `mp3` | Audio format |
| `polly.sample_rate` | `16000` | Audio quality |

## Performance Optimization

### Reduce Latency

1. **Smaller chunk size**: `mediaRecorder.start(100)` (from 250ms)
2. **Faster endpointing**: `deepgram.endpointing = 200`
3. **Skip interim results**: `deepgram.interim_results = false`

### Improve Accuracy

1. **Better model**: `deepgram.model = "nova-3"` (already default)
2. **Add keywords**: Pass business terms to `websocket_config(keywords: ['Acme', 'Q4'])`
3. **Enable smart format**: `deepgram.smart_format = true`

## Security Notes

- **Never commit API keys** - Use environment variables
- **Use ephemeral keys** - Generate temporary keys for client-side use (requires Deepgram plan upgrade)
- **Validate sessions** - VoiceSessionsController checks entity ownership
- **Expire credentials** - Polly credentials expire in 15 minutes

## Related Documentation

- Main docs: `docs/VOICE_ASSISTANT_ADMIN_GUIDE.md`
- Deepgram API: https://developers.deepgram.com/docs
- MediaRecorder API: https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder
- AWS Polly: https://docs.aws.amazon.com/polly/

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
