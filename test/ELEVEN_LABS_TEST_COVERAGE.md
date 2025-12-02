# Eleven Labs Scribe v2 Test Coverage

This document describes the comprehensive test coverage for the Eleven Labs Scribe v2 real-time transcription integration.

## Test Files

### 1. Service Tests
**File:** `test/services/eleven_labs_transcription_service_test.rb`

Comprehensive unit tests for the `ElevenLabsTranscriptionService` class.

#### Configuration Tests
- ✅ `websocket_config` returns valid configuration
- ✅ Correct encoding (PCM 16-bit) and sample rate (16kHz)
- ✅ Single channel (mono) audio
- ✅ Correct model selection (scribe-v2-realtime)
- ✅ Default language handling
- ✅ Custom language support
- ✅ Punctuation enabled
- ✅ Partial results enabled
- ✅ Latency optimization enabled

#### Keywords Tests
- ✅ Keywords included in configuration
- ✅ Keyword deduplication
- ✅ Nil keyword filtering
- ✅ Session keyword integration
- ✅ User-provided keyword merging

#### Connection Parameters Tests
- ✅ Complete connection data returned
- ✅ WebSocket URL format validation
- ✅ API key inclusion
- ✅ Configuration passed to connection params
- ✅ Secure WebSocket protocol (wss://)

#### API Key Tests
- ✅ Environment variable reading
- ✅ Error handling for missing API key
- ✅ Credential source precedence

#### Language Support Tests
- ✅ Supported languages list retrieval
- ✅ Major languages included (English, Spanish, French, German)
- ✅ Indian language support (Hindi)
- ✅ Language code/name structure validation

#### Connection Health Tests
- ✅ Connection test for valid API key
- ✅ Connection test for missing API key
- ✅ HTTP error handling

#### Constants Tests
- ✅ Correct WebSocket URL constant
- ✅ Correct model name constant
- ✅ Correct default language constant
- ✅ Correct API base URL constant

**Total Service Tests: 26**

---

### 2. Controller Tests
**File:** `test/controllers/api/voice/voice_sessions_controller_test.rb`

Comprehensive integration tests for the voice sessions API endpoints.

#### Session Creation Tests
- ✅ Create new voice session
- ✅ Session attributes correctly set
- ✅ User association
- ✅ Entity scoping
- ✅ Session ID generation
- ✅ Status initialization to "active"
- ✅ Metadata capture (user agent, IP address)

#### Session Retrieval Tests
- ✅ Get session details
- ✅ Session data structure validation
- ✅ Timestamp fields included
- ✅ 404 response for non-existent session

#### Eleven Labs Credentials Tests
- ✅ Get Eleven Labs credentials endpoint
- ✅ WebSocket URL format validation
- ✅ API key returned correctly
- ✅ Full configuration included in response
- ✅ Audio encoding specification
- ✅ Sample rate specification
- ✅ Model name in config
- ✅ Punctuation enabled flag
- ✅ Partial results flag
- ✅ Latency optimization flag

#### Deepgram Fallback Tests
- ✅ Backward compatibility with Deepgram
- ✅ Deepgram credentials still accessible

#### Session End Tests
- ✅ End voice session
- ✅ Status updated to "ended"
- ✅ Ended timestamp set

#### Authentication Tests
- ✅ All endpoints require authentication
- ✅ Unauthenticated requests rejected with 401
- ✅ Proper error responses

#### Authorization/Entity Scoping Tests
- ✅ Users can only access their own entity's sessions
- ✅ Cross-entity access forbidden
- ✅ Proper 403 Forbidden responses
- ✅ Entity isolation maintained

#### Error Handling Tests
- ✅ Missing API key handled gracefully
- ✅ Service errors caught and reported
- ✅ Invalid session ID handling
- ✅ Database error handling
- ✅ Proper error response format

#### Metadata Tests
- ✅ User agent captured
- ✅ IP address captured
- ✅ Creation source tracked ("web")

**Total Controller Tests: 33**

---

## Test Coverage Summary

| Category | Count | Status |
|----------|-------|--------|
| Service Unit Tests | 26 | ✅ Complete |
| Controller Integration Tests | 33 | ✅ Complete |
| **Total Tests** | **59** | **✅ Complete** |

## Running the Tests

### Run All Eleven Labs Tests
```bash
bundle exec rails test test/services/eleven_labs_transcription_service_test.rb \
                       test/controllers/api/voice/voice_sessions_controller_test.rb
```

### Run Service Tests Only
```bash
bundle exec rails test test/services/eleven_labs_transcription_service_test.rb
```

### Run Controller Tests Only
```bash
bundle exec rails test test/controllers/api/voice/voice_sessions_controller_test.rb
```

### Run with Verbose Output
```bash
bundle exec rails test test/services/eleven_labs_transcription_service_test.rb -v
```

### Run Specific Test
```bash
bundle exec rails test test/services/eleven_labs_transcription_service_test.rb -n test_websocket_config_returns_valid_configuration
```

## Test Fixtures & Setup

Tests use the following fixtures:
- `users(:one)` - Default test user
- `entities(:one)` - Default test entity
- `VoiceSession` - Created dynamically with proper associations

## Coverage Areas

### Functional Coverage
- ✅ WebSocket configuration generation
- ✅ API key management
- ✅ Connection parameter generation
- ✅ Language support
- ✅ Audio encoding specifications
- ✅ Keyword handling
- ✅ Session creation and retrieval
- ✅ Credentials endpoint
- ✅ Error handling
- ✅ Authentication and authorization

### Non-Functional Coverage
- ✅ API security (authentication required)
- ✅ Entity scoping (multi-tenancy)
- ✅ Error handling and validation
- ✅ Environment variable configuration
- ✅ Backward compatibility
- ✅ Metadata tracking

## Integration with Existing Tests

These tests follow the same patterns as existing tests in the codebase:
- Use `ActiveSupport::TestCase` for unit tests
- Use `ActionDispatch::IntegrationTest` for controller tests
- Follow Rails conventions for test organization
- Use `Minitest::Mock` for mocking external services
- Support parallel test execution
- Work with existing test fixtures

## Fallback Mechanism

The integration includes automatic fallback from Eleven Labs to Deepgram with comprehensive logging:

### How It Works
1. **Primary Provider**: Eleven Labs Scribe v2 is attempted first
2. **Fallback Trigger**: If Eleven Labs fails to connect:
   - Network error
   - API credentials invalid
   - Service unavailable
   - Connection timeout
3. **Fallback Provider**: Deepgram automatically takes over
4. **User Notification**: Status message indicates which provider is active
5. **Logging**: Detailed console logs track which provider was used

### Logging Output Example
```
🚀 Attempting STT provider connection (priority: Eleven Labs → Deepgram)...
1️⃣ Attempting Eleven Labs Scribe v2 (primary provider)...
⚠️ Eleven Labs Scribe v2 unavailable, attempting fallback...
   Error: Connection timeout
   Reason: Eleven Labs API unreachable or credentials invalid
2️⃣ Attempting Deepgram (fallback provider)...
✅ Deepgram connected successfully in 245ms
📊 STT Provider: Deepgram (fallback)
ℹ️ Note: Using fallback provider. Eleven Labs will be retried on next session.
```

### Session End Logging
When voice session ends, the provider used is logged:
```
📊 Session used STT provider: Deepgram (fallback)
```

## Continuous Integration

These tests are compatible with:
- ✅ Rails test runner
- ✅ CI/CD pipelines
- ✅ Parallel test execution
- ✅ Code coverage tools

## Future Enhancement Opportunities

Potential additional test coverage:
1. JavaScript WebSocket connection tests (browser automation)
   - Test Eleven Labs → Deepgram fallback scenario
   - Test connection timeouts
   - Test error recovery
2. End-to-end voice transcription tests (with mock providers)
3. Performance benchmarks for provider switching
4. Load testing for concurrent sessions with provider failover
5. Error recovery and reconnection tests
6. Audio quality validation for each provider
7. Provider health check mechanism
8. Metrics collection for fallback usage tracking
