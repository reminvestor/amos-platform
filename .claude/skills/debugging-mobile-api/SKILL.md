# Debugging Mobile API

Troubleshoot API connectivity between the Flutter mobile app and Rails backend.

## Description

This skill helps diagnose and fix API communication issues between the AMOS Flutter app and Rails backend. It covers authentication problems, network errors, CORS issues, and environment configuration.

**Use this skill when:**
- API calls from mobile app are failing
- Authentication token issues
- Network timeout or connection refused errors
- Testing API endpoints manually
- Debugging request/response data

## Instructions

### Quick Diagnostics

```bash
# 1. Check if Rails is running
docker compose ps

# 2. Test API health endpoint
curl http://localhost:3000/api/v1/health

# 3. Check Flutter environment
grep API_BASE_URL flutter_mobile/lib/config/env.dart
```

### Common Issues & Fixes

#### Issue: Connection Refused
**Symptom**: `SocketException: Connection refused`

**Causes**:
1. Rails server not running
2. Wrong API_BASE_URL
3. Physical device can't reach localhost

**Fix**:
```bash
# Start Rails
docker compose up -d

# For physical devices, use LAN IP:
flutter run -d android --dart-define=API_BASE_URL=http://192.168.1.100:3000
```

#### Issue: 401 Unauthorized
**Symptom**: API returns 401 after login works

**Causes**:
1. Token not stored correctly
2. Token expired
3. Token not sent in headers

**Debug**:
```bash
# Check token in Flutter storage
# Look in: lib/services/storage_service.dart

# Test token manually
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3000/api/v1/user
```

#### Issue: 404 Not Found
**Symptom**: Routes work on web but not mobile

**Causes**:
1. API namespace mismatch
2. Route not defined for mobile

**Debug**:
```bash
# Check available routes
docker compose exec web rails routes | grep api/v1
```

#### Issue: CORS Errors (Chrome only)
**Symptom**: Works on mobile, fails on Chrome

**Fix**: Check Rails CORS config in `config/initializers/cors.rb`

### Testing API Manually

```bash
# Login and get token
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'

# Use token for authenticated requests
TOKEN="your-token-here"
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/agents

# Test specific endpoint
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/campaigns
```

### Reading Rails Logs

```bash
# View API request logs
docker compose logs -f web | grep -E "(Started|Parameters|Completed)"

# View authentication issues
docker compose logs -f web | grep -i "unauthorized\|auth\|token"

# View all errors
docker compose logs -f web | grep -E "(Error|Exception|500)"
```

### Flutter Debug Points

Key files to check:
- `lib/config/env.dart` - API_BASE_URL configuration
- `lib/services/api_client.dart` - HTTP client setup
- `lib/services/auth_service.dart` - Authentication logic
- `lib/services/storage_service.dart` - Token storage

Add debug logging:
```dart
// In api_client.dart
print('API Request: ${request.method} ${request.url}');
print('Headers: ${request.headers}');
print('Response: ${response.statusCode} ${response.body}');
```

### Physical Device Setup

For testing on physical iOS/Android devices:

1. **Find your Mac's IP**:
```bash
ipconfig getifaddr en0  # WiFi
```

2. **Run with custom API URL**:
```bash
flutter run -d android --dart-define=API_BASE_URL=http://YOUR_IP:3000
```

3. **Ensure same network**: Device and Mac must be on same WiFi

## Examples

**Debug connection issue:**
```
Use debugging-mobile-api to diagnose connection refused error
```

**Test authenticated endpoint:**
```
Use debugging-mobile-api to test /api/v1/agents with my token
```

**Check Rails logs for errors:**
```
Use debugging-mobile-api to view recent API errors
```

## Related Skills

- [Running Flutter App](../running-flutter-app/SKILL.md) - Starting the app
- [Managing Docker Development](../managing-docker-development/SKILL.md) - Rails server management
