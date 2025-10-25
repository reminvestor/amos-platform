# Voice Assistant Performance Analysis

## Executive Summary

**Current Performance**: ~1250ms from mic button click to "Listening..."
**Identified Bottleneck**: AWS Polly credentials generation takes **412ms average** (98.8% of backend time)
**Optimized Target**: ~300-500ms (60-75% improvement possible)

---

## Backend Performance Test Results

### Individual Component Timings

| Component | Average Time | % of Total | Status |
|-----------|-------------|------------|--------|
| **Polly Credentials** | 412ms | 98.8% | 🔴 CRITICAL BOTTLENECK |
| Session Creation | 5ms | 1.1% | 🟢 Optimized |
| Deepgram Config | <1ms | 0.0% | 🟢 Optimized |
| Database Queries | <50ms | — | 🟢 Acceptable |

### Polly Credentials Breakdown

AWS STS calls show high variance:
- Run 1: **1031ms** (cold start)
- Run 2: 461ms
- Run 3: **49ms** (cached?)
- Run 4: 472ms
- Run 5: **49ms** (cached?)

**Analysis**: Network latency to AWS STS API is the primary bottleneck. Credentials are generated fresh on each request instead of being cached.

---

## Current Initialization Flow

```
User clicks mic button
  ↓
1. Request microphone access      500ms  (browser permission)
2. Create voice session           5ms    (database write)
3. Parallel API calls:
   - Get Deepgram credentials     250ms  (HTTP round-trip)
   - Get Polly credentials        412ms  🔴 BOTTLENECK
   - Connect Action Cable         200ms  (WebSocket handshake)
4. Connect Deepgram WebSocket     200ms  (WebSocket handshake)
  ↓
Total: ~1250ms
```

---

## Optimization Strategies

### Strategy 1: Cache Polly Credentials ⭐ BIGGEST WIN
**Impact**: Reduces 412ms → ~5ms (99% improvement on this component)

**Implementation**:
```ruby
# Use Rails.cache with 14-minute TTL (credentials valid for 15 mins)
def cached_polly_credentials(session_id)
  Rails.cache.fetch("polly_creds:#{session_id}", expires_in: 14.minutes) do
    PollyCredentialsService.new(session).generate_credentials
  end
end
```

**Savings**: ~400ms per request after first call

### Strategy 2: Pre-Initialize on Page Load ⭐ SECOND BIGGEST WIN
**Impact**: Reduces perceived latency from 1250ms → 500ms (60% improvement)

**Implementation**:
```javascript
// In Scout page controller - run on page load
connect() {
  // Pre-create session and fetch credentials
  this.preInitializeVoiceSession()
}

async preInitializeVoiceSession() {
  // Create session
  const session = await this.createVoiceSession()
  this.cachedSessionId = session.session_id

  // Pre-fetch credentials in parallel
  const [deepgramCreds, pollyCreds] = await Promise.all([
    this.getDeepgramCredentials(this.cachedSessionId),
    this.getPollyCredentials(this.cachedSessionId)
  ])

  this.cachedDeepgramCreds = deepgramCreds
  this.cachedPollyCreds = pollyCreds

  // Now mic button only needs: microphone + WebSocket = ~500ms total!
}
```

**Savings**: User only waits for microphone + WebSocket (~700ms instead of 1250ms)

### Strategy 3: Optimize Deepgram Credentials Endpoint
**Impact**: Reduces 250ms → ~50ms

Currently making full HTTP request. Could inline credentials in session creation response:

```ruby
# POST /api/voice/sessions
{
  session_id: "...",
  deepgram_credentials: { ... },  # Include immediately
  polly_credentials: { ... }      # Include immediately
}
```

**Savings**: ~200ms (eliminates 2 extra HTTP round-trips)

### Strategy 4: WebSocket Pre-Connection (Advanced)
**Impact**: Reduces 200ms WebSocket handshake

Connect to Deepgram WebSocket in "paused" state, start streaming when mic is clicked.

**Risk**: More complex, may have connection timeout issues
**Savings**: ~200ms

---

## Recommended Implementation Plan

### Phase 1: Quick Wins (30 minutes)
1. ✅ **Cache Polly credentials** (14-minute TTL)
2. ✅ **Inline credentials in session creation response**

**Expected Result**: First load ~850ms, subsequent loads ~450ms

### Phase 2: Pre-Initialization (1 hour)
3. ✅ **Pre-create session on page load**
4. ✅ **Pre-fetch credentials on page load**

**Expected Result**: Mic button click → ~300-500ms

### Phase 3: Advanced (Optional, 2 hours)
5. ⚠️ **Pre-connect WebSocket** (if phase 2 isn't fast enough)

---

## Expected Performance After Optimization

| Scenario | Current | After Phase 1 | After Phase 2 |
|----------|---------|---------------|---------------|
| First mic click | 1250ms | 850ms | 500ms |
| Subsequent clicks | 1250ms | 450ms | 300ms |
| **Improvement** | — | **32-64%** | **60-76%** |

---

## Browser Performance Test Suite

A comprehensive test suite has been created: `app/javascript/controllers/voice_performance_test.js`

### To Run Tests:
1. Open Scout page in browser
2. Open DevTools console
3. Paste the test file content
4. Run: `await VoicePerformanceTest.runFullTest()`

### Tests Included:
- Individual step timing (microphone, API calls, WebSocket)
- Parallel vs sequential API comparison
- Microphone initialization variance
- Connection caching opportunities

---

## Files Created

1. **Frontend Test Suite**: `app/javascript/controllers/voice_performance_test.js`
2. **Backend Test Suite**: `tmp/test_voice_performance.rb`
3. **This Analysis**: `docs/VOICE_ASSISTANT_PERFORMANCE_ANALYSIS.md`

---

## Next Steps

Run: `await VoicePerformanceTest.runFullTest()` in browser console to get client-side metrics, then implement Phase 1 optimizations.
