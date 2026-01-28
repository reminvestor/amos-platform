# Push Notifications Setup Guide

This guide covers setting up AWS SNS push notifications for the AMOS mobile apps.

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│   Rails API     │────▶│   AWS SNS       │
│  (Flutter)      │     │  DeviceTokens   │     │  Platform App   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │   Apple APNs    │
                                                │   (or FCM)      │
                                                └─────────────────┘
```

## AWS Console Setup

### 1. Create Platform Application in SNS

1. Go to **AWS Console → SNS → Push notifications → Platform applications**
2. Click **Create platform application**
3. Configure:
   - **Name**: `amos-ios-production` (or similar)
   - **Push notification platform**: Apple iOS
   - **Push service**: APNs (not sandbox for production)
   - **Authentication method**: Token-based (use the .p8 key)
4. Upload the .p8 file from Apple Developer Portal
5. Enter your **Key ID** and **Team ID**
6. Copy the **Platform Application ARN** - you'll need this!

### 2. Add IAM Permissions

Add this policy to your ECS task role (or CodeBuild role for testing):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:CreatePlatformEndpoint",
        "sns:Publish",
        "sns:DeleteEndpoint",
        "sns:GetEndpointAttributes",
        "sns:SetEndpointAttributes"
      ],
      "Resource": "arn:aws:sns:*:*:app/APNS/*"
    }
  ]
}
```

### 3. Set Environment Variables

Add to your production environment:

```bash
# AWS SNS Push Notifications
AWS_SNS_IOS_PLATFORM_ARN=arn:aws:sns:us-east-1:637423327454:app/APNS/amos-ios-production

# For Android (future)
# AWS_SNS_ANDROID_PLATFORM_ARN=arn:aws:sns:us-east-1:637423327454:app/GCM/amos-android-production

# AWS credentials (already configured)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=xxx
AWS_SECRET_ACCESS_KEY=xxx
```

## API Endpoints

### Register Device Token

```http
POST /api/v1/device_tokens
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "device_token": {
    "token": "abc123...(APNs device token)",
    "platform": "ios",
    "device_id": "unique-device-uuid",
    "device_name": "Rick's iPhone",
    "device_model": "iPhone 15 Pro",
    "os_version": "17.2",
    "app_version": "1.0.0"
  }
}
```

**Response:**
```json
{
  "success": true,
  "device_token": {
    "id": 123,
    "platform": "ios",
    "device_name": "Rick's iPhone",
    "device_model": "iPhone 15 Pro",
    "active": true,
    "created_at": "2026-01-28T..."
  },
  "message": "Device registered successfully"
}
```

### Unregister Device (Logout)

```http
DELETE /api/v1/device_tokens/by_token?token=abc123...
Authorization: Bearer <api_key>
```

### Logout All Devices

```http
DELETE /api/v1/device_tokens/logout_all
Authorization: Bearer <api_key>
```

### List Registered Devices

```http
GET /api/v1/device_tokens
Authorization: Bearer <api_key>
```

### Update Notification Preferences

```http
PATCH /api/v1/device_tokens/:id/preferences
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "preferences": {
    "chat_messages": true,
    "workflow_complete": true,
    "new_leads": false
  }
}
```

## iOS Integration (Flutter)

### 1. Request Notification Permission

```dart
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> requestNotificationPermission() async {
  final messaging = FirebaseMessaging.instance;
  
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  
  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    // Get the APNs token
    String? apnsToken = await messaging.getAPNSToken();
    if (apnsToken != null) {
      await registerDeviceToken(apnsToken);
    }
  }
}
```

### 2. Register Token with Backend

```dart
Future<void> registerDeviceToken(String token) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/api/v1/device_tokens'),
    headers: {
      'Authorization': 'Bearer $userApiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'device_token': {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'device_id': await getDeviceId(),
        'device_name': await getDeviceName(),
        'device_model': await getDeviceModel(),
        'os_version': Platform.operatingSystemVersion,
        'app_version': packageInfo.version,
      },
    }),
  );
  
  if (response.statusCode == 201) {
    print('Device registered for push notifications');
  }
}
```

### 3. Handle Token Refresh

```dart
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  // Re-register with new token
  await registerDeviceToken(newToken);
});
```

### 4. Handle Incoming Notifications

```dart
// Foreground messages
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  // Show local notification or handle in-app
  print('Received notification: ${message.notification?.title}');
  
  // Handle data payload
  if (message.data['type'] == 'chat_message') {
    // Navigate to chat
  }
});

// Background/terminated app - message opens app
FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
  // Handle navigation based on message data
  handleNotificationNavigation(message.data);
});
```

## Notification Types

The system sends these notification types:

| Type | Description | Data Keys |
|------|-------------|-----------|
| `chat_message` | New chat message | `conversation_id` |
| `reminder` | Task reminder | `reminder_id` |
| `workflow_complete` | Workflow finished | `workflow_id`, `status` |
| `new_lead` | New CRM lead | `lead_id`, `source` |
| `system_notification` | System alerts | `notification_id`, `category`, `severity` |

## Sending Notifications from Backend

### Direct Service Call

```ruby
# Send to all user's devices
SnsPushNotificationService.send_to_user(
  user: current_user,
  title: "New Message",
  body: "You have a new message from John",
  data: { type: 'chat_message', conversation_id: 123 },
  options: { category: 'chat', sound: 'default' }
)

# Send to specific device
SnsPushNotificationService.send_to_device(
  device_token: device,
  title: "Reminder",
  body: "Your meeting starts in 15 minutes",
  data: { type: 'reminder', reminder_id: 456 }
)
```

### Via Background Job

```ruby
SendPushNotificationJob.perform_later(
  user_id: user.id,
  title: "Workflow Complete",
  body: "Your data export is ready",
  data: { type: 'workflow_complete', workflow_id: 789, status: 'success' }
)
```

### Automatic via SystemNotificationService

Push notifications are automatically sent for error/critical system notifications:

```ruby
SystemNotificationService.new(entity: entity, user: user)
  .notify_job_failure(
    job_id: 123,
    job_type: 'DataExport',
    error: 'Connection timeout'
  )
# This automatically sends push notification to user's devices
```

## Troubleshooting

### Device Not Receiving Notifications

1. Check device token is registered: `DeviceToken.where(user: user).active`
2. Verify platform_arn is set: `device.platform_arn.present?`
3. Check AWS SNS logs in CloudWatch
4. Verify APNs certificate is valid in AWS Console

### Token Invalid Errors

When SNS returns "EndpointDisabled", the token is automatically deactivated:
```ruby
device.deactivation_reason # => "token_invalid"
```

The app should re-register on next launch.

### Testing Locally

```ruby
# In rails console
user = User.find(1)
SnsPushNotificationService.send_to_user(
  user: user,
  title: "Test",
  body: "Test notification"
)
```

## Security Considerations

1. **Token Storage**: Device tokens are stored encrypted in the database
2. **User Validation**: API validates user owns the token before operations
3. **Rate Limiting**: Consider adding rate limits to prevent notification spam
4. **Sensitive Data**: Never include sensitive information in notification payloads
