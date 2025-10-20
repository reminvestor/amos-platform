# Phase 1 Testing Guide
**Date**: October 19, 2025
**Purpose**: Validate Phase 1 enhancements before deployment

---

## Pre-Testing Setup

### 1. Install Dependencies
```bash
# Install rack-attack gem
bundle install

# Run database migrations
rails db:migrate
```

### 2. Restart Server
```bash
# Stop current server
# Restart with:
bin/dev
# OR
rails server
```

---

## Test 1: Rate Limiting ✅

### Test Scout Chat Rate Limit (50 requests/minute per IP)

**Method 1: Manual Testing**
```bash
# Send 51 requests rapidly to /scout/chat_stream
for i in {1..51}; do
  echo "Request $i"
  curl -X POST http://localhost:3000/scout/chat_stream \
    -H "Content-Type: application/json" \
    -d '{"message": "test"}' \
    -b "cookie.txt" \
    -c "cookie.txt"
  sleep 0.5
done
```

**Expected Result:**
- Requests 1-50: Return 200 OK
- Request 51: Return **429 Too Many Requests**
- Response includes `Retry-After` header

**Example 429 Response:**
```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests. Please try again later.",
  "retry_after": 60
}
```

### Test API Rate Limit (100 requests/minute per IP)

```bash
# Test API endpoint
for i in {1..101}; do
  curl http://localhost:3000/api/v1/health
  sleep 0.5
done
```

**Expected Result:**
- Request 101 returns 429

### Test Login Rate Limit (5 attempts per 20 seconds)

```bash
# Attempt 6 login attempts rapidly
for i in {1..6}; do
  curl -X POST http://localhost:3000/users/sign_in \
    -d "user[email]=test@example.com&user[password]=wrong"
  sleep 1
done
```

**Expected Result:**
- Attempts 1-5: Return 200 or 401
- Attempt 6: Return **429**

### Verify Rack::Attack Logs

```bash
# Check Rails logs for rate limiting events
tail -f log/development.log | grep "Rack::Attack"
```

**Expected Log Output:**
```
[Rack::Attack] Throttled: 127.0.0.1 - /scout/chat_stream
```

---

## Test 2: Custom Error Handling 💬

### Test Bedrock Throttling Error

**Simulate Throttling:**
1. Make many rapid AI requests to exhaust quota
2. OR temporarily modify BedrockService to raise throttling error:

```ruby
# In app/services/bedrock_service.rb (temporary for testing)
def send_message_non_streaming(...)
  raise Aws::BedrockRuntime::Errors::ThrottlingException.new(
    nil, "Rate exceeded"
  )
end
```

**Test Request:**
```bash
curl -X POST http://localhost:3000/scout/chat_stream \
  -H "Content-Type: application/json" \
  -d '{"message": "Generate a landing page"}' \
  -b "cookie.txt"
```

**Expected Response:**
```json
{
  "message": "AI service is currently busy. Please try again in a moment.",
  "error": true,
  "retry_after": 60,
  "error_type": "BedrockThrottlingError"
}
```

**Expected HTTP Status:** 503 Service Unavailable

### Test Integration Error

**Simulate Integration Error:**
1. Disconnect a Stripe/Mailgun integration
2. Try to use it in a workflow

**Expected Response:**
```json
{
  "message": "Stripe integration error: Authentication failed. Please reconnect your Stripe account in Settings > Integrations.",
  "error": true,
  "integration": "Stripe"
}
```

**Expected HTTP Status:** 422 Unprocessable Entity

### Test Timeout Error

**Simulate Timeout:**
1. Temporarily reduce timeout in BedrockService:

```ruby
# config/initializers/bedrock_timeout.rb (temporary)
Aws::BedrockRuntime::Client.new(
  http_read_timeout: 1  # 1 second instead of 600
)
```

2. Make a complex request

**Expected Response:**
```json
{
  "message": "AI service request timed out. This usually happens with complex requests. Please try again or simplify your request.",
  "error": true,
  "retry_after": 30
}
```

### Verify Error Logs

```bash
tail -f log/development.log | grep "Scout.*error"
```

**Expected Log Output:**
```
Scout Bedrock error: BedrockThrottlingError - AI service is currently busy
Scout integration error: Stripe - Authentication failed
```

---

## Test 3: Progress Indicators ⏳

### Test Landing Page Generation Progress

**Steps:**
1. Log in to Scout interface
2. Send message: "Create a landing page for my dental practice"
3. Watch for progress updates

**Expected Progress Updates (in order):**
1. 🚀 Starting landing page generation... (0%)
2. 📋 Analyzing your requirements and gathering context... (10%)
3. 💾 Creating landing page record... (20%)
4. 🎨 Generating page content with AI (this may take 2-3 minutes)... (30%)
5. 🔨 Compiling final landing page... (90%)
6. ✅ Done! Loading your new landing page... (100%)

**Verify in Browser DevTools:**
```javascript
// Open Network tab, watch for SSE events
// Should see events like:
{
  "type": "progress",
  "tool": "generate_ai_landing_page",
  "message": "🎨 Generating page content with AI...",
  "percentage": 30,
  "timestamp": "2025-10-19T..."
}
```

**Check Rails Logs:**
```bash
tail -f log/development.log | grep "progress"
```

---

## Test 4: Scout Message Saving Fix 💾

### Test Duplicate Prevention

**Steps:**
1. Log in to Scout
2. Send message: "hello"
3. Check database immediately after:

```ruby
# Rails console
session_id = "your-session-id"
messages = ScoutMessage.where(session_id: session_id).last(5)
messages.each { |m| puts "#{m.role}: #{m.content}" }
```

**Expected Output:**
```
user: hello
assistant: [AI response, not "hello"]
```

**Should NOT see:**
```
user: hello
assistant: hello  # ❌ WRONG - should not happen now
```

### Test Role Validation

**Simulate Invalid Role:**
```ruby
# Rails console
controller = ScoutController.new
controller.instance_variable_set(:@current_user, User.first)
controller.send(:save_scout_message, "invalid_role", "test message")
```

**Expected Log:**
```
❌ Invalid role 'invalid_role' for message, defaulting to 'assistant'
💾 Saving assistant message: test message
```

### Test Duplicate Detection

**Steps:**
1. Send short user message: "hi"
2. Try to save it again as assistant within 10 seconds:

```ruby
# Rails console (should be blocked)
ScoutMessage.create!(
  session_id: "test",
  role: "assistant",  # Wrong role
  content: "hi"  # Same as recent user message
)
```

**Expected Log:**
```
⚠️ Skipping potential duplicate: identical user message found within 10 seconds
```

---

## Test 5: Performance Improvements 🚀

### Test Contact Model Performance

**Before (with debug code):**
```ruby
# Rails console
require 'benchmark'

Benchmark.measure do
  1000.times { Contact.first }
end
```

**After (without debug code):**
```ruby
Benchmark.measure do
  1000.times { Contact.first }
end
```

**Expected Improvement:** ~5-10ms faster per operation (5-10 seconds total for 1000 operations)

### Test Database Query Performance

**Run EXPLAIN ANALYZE:**
```sql
-- Scout messages query (should use new index)
EXPLAIN ANALYZE
SELECT * FROM scout_messages
WHERE session_id = 'test'
ORDER BY created_at DESC
LIMIT 10;

-- Should show: "Index Scan using index_scout_messages_on_session_and_created"
```

```sql
-- Email deliveries query (should use new index)
EXPLAIN ANALYZE
SELECT * FROM email_deliveries
WHERE campaign_id = 1
  AND status = 'sent'
ORDER BY sent_at DESC;

-- Should show: "Index Scan using index_email_deliveries_on_campaign_status_sent"
```

**Check Index Usage:**
```sql
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE tablename IN ('scout_messages', 'email_deliveries', 'contacts')
ORDER BY idx_scan DESC;
```

---

## Integration Testing Checklist

### Scout Chat Flow
- [ ] Send user message → saves as "user" role
- [ ] Receive AI response → saves as "assistant" role
- [ ] No duplicate messages in database
- [ ] Progress indicators appear during long operations
- [ ] Error messages are user-friendly

### Error Scenarios
- [ ] Bedrock throttling → 503 with retry-after
- [ ] Integration failure → 422 with actionable message
- [ ] Timeout → 503 with user guidance
- [ ] Rate limit exceeded → 429 with retry-after

### Performance
- [ ] Contact queries use indexes
- [ ] Scout message queries use indexes
- [ ] No N+1 queries in Scout chat
- [ ] Response times < 500ms for 95th percentile

---

## Monitoring & Logging

### Key Logs to Watch

```bash
# Rate limiting
tail -f log/development.log | grep "Rack::Attack"

# Error handling
tail -f log/development.log | grep "error"

# Message saving
tail -f log/development.log | grep "💾 Saving"

# Progress indicators
tail -f log/development.log | grep "progress"
```

### Database Monitoring

```sql
-- Check for duplicate scout messages
SELECT session_id, role, content, COUNT(*)
FROM scout_messages
GROUP BY session_id, role, content
HAVING COUNT(*) > 1;

-- Check message role distribution
SELECT role, COUNT(*) as count
FROM scout_messages
GROUP BY role;

-- Check for orphaned messages (no user)
SELECT COUNT(*)
FROM scout_messages
WHERE user_id IS NULL;
```

---

## Rollback Plan

If any issues arise:

### 1. Disable Rate Limiting
```ruby
# config/initializers/rack_attack.rb
# Comment out all throttle rules temporarily
```

### 2. Revert Error Handling
```bash
git revert <commit-hash>
```

### 3. Rollback Migrations
```bash
rails db:rollback STEP=2
```

### 4. Revert Scout Message Validation
```ruby
# Temporarily comment out validation in save_scout_message
# Lines 1269-1287 in scout_controller.rb
```

---

## Success Criteria

Phase 1 is successful if:

- ✅ Rate limiting blocks requests beyond limits (429 responses)
- ✅ Error messages include actionable guidance (not generic)
- ✅ Landing page generation shows 6 progress updates
- ✅ No duplicate scout messages saved
- ✅ Database queries use new indexes
- ✅ Response times < 500ms for 95th percentile
- ✅ Zero unexplained errors in logs

---

## Troubleshooting

### Rack::Attack Not Working
- Check if gem is installed: `bundle list | grep rack-attack`
- Verify middleware is loaded: `rails middleware | grep Rack::Attack`
- Check initializer is loaded: `Rails.application.config.middleware`

### Custom Errors Not Showing
- Verify AmosErrors module is loaded: `AmosErrors::BedrockError.new("test")`
- Check error handling in controller (lines 114-155)
- Look for error logs: `grep "Bedrock error" log/development.log`

### Progress Indicators Not Appearing
- Check if progress_callback is being passed to tools
- Verify streaming is enabled in chat_stream endpoint
- Check browser console for SSE events

### Indexes Not Used
- Run `ANALYZE` on tables: `ANALYZE scout_messages;`
- Check query plan: `EXPLAIN SELECT ...`
- Verify indexes exist: `\d scout_messages` in psql

---

**Last Updated**: October 19, 2025
**Status**: Ready for testing
**Next**: Deploy to staging environment
