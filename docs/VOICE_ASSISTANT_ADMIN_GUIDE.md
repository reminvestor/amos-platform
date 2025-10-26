# Voice Assistant Admin Settings Guide

## Overview

The Voice Assistant Admin Settings page (`/admin/voice_settings`) provides super admins with fine-grained control over speech-to-text (Deepgram) and text-to-speech (AWS Polly) parameters.

## Accessing the Settings

1. Log in as a super admin
2. Navigate to **Admin Portal** → **Voice Settings** (microphone icon in the navigation)
3. URL: `http://localhost:3000/admin/voice_settings`

## Settings Categories

### 1. Deepgram Transcription Settings (16 settings)

Controls how user speech is converted to text in real-time.

**Model & Language**
- `model`: Deepgram AI model (default: `nova-3`)
  - Options: `nova-2`, `nova-3`, `base`, `enhanced`
  - Recommendation: `nova-3` for best accuracy
- `language`: Language code (default: `en-US`)
  - Examples: `en-GB`, `es`, `fr`, `de`

**Audio Format**
- `encoding`: Audio format (default: `linear16`)
  - **Current implementation: `linear16`** (raw PCM from browser)
  - Options: `linear16`, `opus`, `flac`, `mp3`

  **LINEAR16 vs OPUS:**

  | Feature | LINEAR16 (Current) | OPUS (Future) |
  |---------|-------------------|---------------|
  | Bandwidth | ~256 kbps | ~16-32 kbps (8x less) |
  | Implementation | Simple (raw audio) | Requires MediaRecorder API |
  | Quality | Lossless | Transparent for speech |
  | Browser Support | Universal | Modern browsers only |
  | 10-min call | ~19 MB | ~1.8 MB |

  **Current Setup:** Browser sends raw PCM (LINEAR16) directly from getUserMedia

  **Future Optimization:** Switch to OPUS client-side encoding for:
  - 8x less bandwidth (critical for mobile users)
  - Better handling of poor network conditions
  - Lower latency over slow connections

- `sample_rate`: Sample rate in Hz (default: `16000`)
  - Standard: 16000 Hz (telephony quality) ✅ **Recommended for chatbots**
  - High quality: 44100 Hz (music quality - unnecessary for voice chat)
- `channels`: Number of audio channels (default: `1` = mono)
  - Mono is correct for single microphone (typical chatbot use case)

**Transcription Features**
- `punctuate`: Add punctuation and capitalization (default: `true`)
- `smart_format`: Format dates, times, numbers (default: `true`)
  - Example: "ten twenty five" → "10:25"
- `numerals`: Convert numbers to digits (default: `true`)
  - Example: "one hundred" → "100"
- `interim_results`: Show real-time partial transcripts (default: `true`)
- `utterances`: Split into semantic units (default: `true`)
- `filler_words`: Transcribe "um", "uh" (default: `false`)
- `profanity_filter`: Censor profanity (default: `false`)
- `diarize`: Detect multiple speakers (default: `false`)

**Timing & Performance**
- `endpointing`: Silence duration to end turn (default: `300ms`)
  - Lower = faster response, may cut off user mid-sentence
  - Higher = more complete sentences, slower response
  - Recommended range: 200-500ms
- `utterance_end_ms`: Finalize utterance after silence (default: `800ms`)
  - Time to wait before considering utterance complete
  - Recommended range: 500-1200ms
- `vad_events`: Voice activity detection events (default: `true`)

### 2. AWS Polly Text-to-Speech Settings (4 settings)

Controls how AI responses are converted to speech.

- `voice_id`: AWS Polly voice (default: `Matthew`)
  - Male voices: Matthew, Joey, Justin, Kevin
  - Female voices: Joanna, Kendra, Kimberly, Salli, Ivy
  - [Full voice list](https://docs.aws.amazon.com/polly/latest/dg/voicelist.html)
- `engine`: Synthesis engine (default: `neural`)
  - `neural`: More natural-sounding, higher quality
  - `standard`: Faster, lower cost
- `output_format`: Audio format (default: `pcm`)
  - PCM required for real-time streaming
- `sample_rate`: Output sample rate (default: `16000`)
  - Should match Deepgram sample_rate

### 3. Audio Processing Settings (1 setting)

- `buffer_size`: Audio buffer size in samples (default: `2048`)
  - Lower = lower latency, higher CPU usage
  - Higher = higher latency, lower CPU usage
  - Recommended range: 1024-4096

## Common Configuration Scenarios

### Scenario 1: Optimize for Speed
**Goal**: Minimize response time for quick interactions

```
deepgram.endpointing: 200
deepgram.utterance_end_ms: 600
audio.buffer_size: 1024
```

⚠️ **Trade-off**: May cut off users if they pause mid-sentence

---

### Scenario 2: Optimize for Accuracy
**Goal**: Capture complete thoughts, especially for longer messages

```
deepgram.endpointing: 500
deepgram.utterance_end_ms: 1200
deepgram.interim_results: true
deepgram.smart_format: true
```

⚠️ **Trade-off**: Slower response time

---

### Scenario 3: Multi-language Support
**Goal**: Support Spanish-speaking users

```
deepgram.language: es
deepgram.model: nova-3
polly.voice_id: Miguel (or Lupe for female)
```

---

### Scenario 4: Professional Meeting Assistant
**Goal**: Transcribe meetings with multiple speakers

```
deepgram.diarize: true
deepgram.utterances: true
deepgram.smart_format: true
deepgram.filler_words: false
deepgram.profanity_filter: true
```

---

## Testing Changes

1. **Make changes** on the admin settings page
2. **Click "Save All Settings"**
3. **Test immediately**:
   - Navigate to http://localhost:3000/chat
   - Click the microphone button (bottom right of chat input)
   - Speak to test the new settings
4. **Monitor behavior**:
   - Check response time (endpointing)
   - Verify transcription accuracy
   - Test voice quality

**Note**: Changes take effect immediately for new voice sessions. Existing sessions continue using old settings.

## Resetting to Defaults

If you've made changes and want to revert:

1. Click **"Reset to Defaults"** button (top right)
2. Confirm the warning dialog
3. All 21 settings will be restored to recommended defaults

## Troubleshooting

### Voice Assistant Not Working
- Verify `DEEPGRAM_API_KEY` is set in `.env`
- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set
- Check browser console for WebSocket errors
- Ensure microphone permissions are granted

### Poor Transcription Accuracy
- Try increasing `deepgram.endpointing` to 400ms
- Enable `deepgram.smart_format` and `deepgram.punctuate`
- Switch to `model: nova-3` (latest model)
- Check audio quality (background noise, microphone)

### Slow Response Time
- Decrease `deepgram.endpointing` to 250ms
- Decrease `deepgram.utterance_end_ms` to 700ms
- Reduce `audio.buffer_size` to 1024

### Voice Cuts Off Mid-Sentence
- Increase `deepgram.endpointing` to 400-500ms
- Increase `deepgram.utterance_end_ms` to 1000-1200ms

### Robotic or Unnatural Voice
- Switch Polly engine from `standard` to `neural`
- Try different voice IDs (Joanna, Matthew are most natural)

## Technical Details

### How Settings Are Applied

1. Settings are stored in the `voice_assistant_settings` database table
2. `DeepgramService` reads settings via `VoiceAssistantSetting.get()`
3. `PollyCredentialsService` reads settings via `VoiceAssistantSetting.get()`
4. Settings are cached per-request (no performance impact)
5. Changes persist across server restarts

### Database Schema

```ruby
# voice_assistant_settings table
- key: string (e.g., "deepgram.endpointing")
- value: string (stored as string, cast to correct type)
- setting_type: string (integer, boolean, string, float)
- description: text (shown in admin UI)
```

### Type Casting

Settings are automatically cast to the correct type:
- `integer`: "300" → 300
- `boolean`: "true" → true
- `float`: "0.5" → 0.5
- `string`: "nova-3" → "nova-3"

## Best Practices

1. **Test incrementally**: Change one setting at a time to understand impact
2. **Document changes**: Note what you changed and why
3. **Monitor performance**: Watch for increased latency or errors
4. **Consider user experience**: Balance speed vs. accuracy
5. **Reset if unsure**: Use "Reset to Defaults" to restore recommended settings

## API Reference

### DeepgramService

```ruby
service = DeepgramService.new(voice_session)
config = service.websocket_config

# Returns hash with all Deepgram parameters
# Reads from VoiceAssistantSetting.get("deepgram.*")
```

### PollyCredentialsService

```ruby
service = PollyCredentialsService.new(voice_session)
config = service.voice_config

# Returns hash with Polly voice configuration
# Reads from VoiceAssistantSetting.get("polly.*")
```

## Support

For issues or questions:
1. Check server logs: `docker compose logs web --tail=100`
2. Check browser console for JavaScript errors
3. Verify environment variables are set correctly
4. Review Deepgram and AWS Polly documentation

## Related Documentation

- [Voice Assistant Quick Start Guide](VOICE_ASSISTANT_QUICK_START.md)
- [Deepgram API Documentation](https://developers.deepgram.com/)
- [AWS Polly Voice List](https://docs.aws.amazon.com/polly/latest/dg/voicelist.html)
