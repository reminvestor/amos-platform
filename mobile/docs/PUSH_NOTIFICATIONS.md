# Push Notifications Options - AMOS Mobile App

Guide to implementing push notifications using AWS services or alternatives.

## Overview

Since you're using AWS, here are your options for push notifications:

| Option | Best For | Cost | Setup | Reliability |
|--------|----------|------|-------|-------------|
| **AWS SNS + SQS** | Native AWS integration | ✓ Low | Medium | Excellent |
| **AWS Amplify Notifications** | Managed AWS service | ✓ Medium | Easy | Excellent |
| **OneSignal** | Multi-channel messaging | ✓✓ Medium | Easy | Excellent |
| **Firebase Cloud Messaging (FCM)** | Simple setup | ✓ Low | Very Easy | Excellent |
| **Twilio** | SMS + Push + Email | ✓✓✓ High | Medium | Excellent |

## Recommendation: AWS SNS + React Native

**Why SNS?**
- Native AWS integration (same infrastructure)
- Direct integration with your Rails backend
- Lower cost than third-party services
- Full control over message delivery

---

## Option 1: AWS SNS (Amazon Simple Notification Service)

### Architecture

```
Rails Backend
    ↓
AWS SNS
    ↓
Device Tokens (iOS APNs / Android GCM)
    ↓
React Native App
```

### Setup Steps

#### 1. Configure AWS SNS on Backend (Rails)

```ruby
# Gemfile
gem 'aws-sdk-sns'

# config/initializers/aws_sns.rb
Aws.config.update(
  region: ENV['AWS_REGION'] || 'us-east-1',
  credentials: Aws::Credentials.new(
    ENV['AWS_ACCESS_KEY_ID'],
    ENV['AWS_SECRET_ACCESS_KEY']
  )
)

$sns_client = Aws::SNS::Client.new
```

#### 2. Create SNS Platform Application

```ruby
# app/services/aws_sns_service.rb
class AwsSnsService
  def self.create_platform_app
    # iOS
    response = $sns_client.create_platform_application({
      name: 'amos-ios',
      platform: 'APNS',
      attributes: {
        'EventEndpointCreated' => 'arn:aws:sns:us-east-1:123456789:ios-created',
        'EventEndpointDeleted' => 'arn:aws:sns:us-east-1:123456789:ios-deleted',
        'EventEndpointUpdated' => 'arn:aws:sns:us-east-1:123456789:ios-updated',
      }
    })

    # Android
    response = $sns_client.create_platform_application({
      name: 'amos-android',
      platform: 'GCM',
      attributes: {
        'PlatformCredential' => ENV['FIREBASE_API_KEY']
      }
    })
  end

  def self.register_device(user_id, device_token, platform)
    platform_app_arn = ENV["SNS_#{platform.upcase}_APP_ARN"]

    response = $sns_client.create_platform_endpoint({
      platform_application_arn: platform_app_arn,
      token: device_token,
      custom_user_data: user_id.to_s
    })

    response.endpoint_arn
  end

  def self.send_notification(endpoint_arn, title, message, data = {})
    payload = {
      aps: {
        alert: {
          title: title,
          body: message
        },
        sound: 'default',
        badge: 1,
        'custom-data' => data
      }
    }

    android_payload = {
      notification: {
        title: title,
        body: message
      },
      data: data
    }

    $sns_client.publish({
      target_arn: endpoint_arn,
      message: payload.to_json,
      message_structure: 'json'
    })
  end

  def self.send_bulk_notification(user_ids, title, message, data = {})
    topic_arn = ENV['SNS_TOPIC_ARN']

    payload = {
      default: message,
      APNS: {
        aps: {
          alert: {
            title: title,
            body: message
          }
        }
      },
      GCM: {
        notification: {
          title: title,
          body: message
        }
      }
    }

    $sns_client.publish({
      topic_arn: topic_arn,
      subject: title,
      message: payload.to_json,
      message_structure: 'json'
    })
  end
end
```

#### 3. Implement in Mobile App

Install dependencies:

```bash
npm install expo-notifications
```

Setup in React Native:

```typescript
// src/services/notifications.ts
import * as Notifications from 'expo-notifications';
import { apiClient } from './api';

export async function requestNotificationPermission() {
  try {
    const { status } = await Notifications.requestPermissionsAsync({
      ios: {
        allowAlert: true,
        allowSound: true,
        allowBadge: true,
      },
    });

    return status === 'granted';
  } catch (error) {
    console.error('Failed to request notification permission:', error);
    return false;
  }
}

export async function getDeviceToken(): Promise<string | null> {
  try {
    // For Expo Go
    const token = (await Notifications.getExpoPushTokenAsync()).data;
    return token;

    // For standalone/built app with SNS, use Expo's token or APNs token
    // const { uniqueId } = await Application.getInstallationIdAsync();
    // return uniqueId;
  } catch (error) {
    console.error('Failed to get device token:', error);
    return null;
  }
}

export async function registerDevice(deviceToken: string, platform: 'ios' | 'android') {
  try {
    await apiClient.post('/api/v1/notifications/register_device', {
      device_token: deviceToken,
      platform,
      device_type: 'mobile'
    });
  } catch (error) {
    console.error('Failed to register device:', error);
    throw error;
  }
}

export function setupNotificationHandlers() {
  // Handle notification when app is in foreground
  Notifications.setNotificationHandler({
    handleNotification: async (notification) => {
      console.log('Notification received:', notification);
      return {
        shouldShowAlert: true,
        shouldPlaySound: true,
        shouldSetBadge: true,
      };
    },
  });

  // Handle notification tap when app is backgrounded
  Notifications.addNotificationResponseReceivedListener((response) => {
    const { notification } = response;
    console.log('User tapped notification:', notification);
    // Navigate to relevant screen based on notification data
  });
}
```

#### 4. App Initialization

```typescript
// src/App.tsx
import { useEffect } from 'react';
import * as notificationService from '@services/notifications';

export default function App() {
  useEffect(() => {
    setupNotifications();
  }, []);

  const setupNotifications = async () => {
    // Setup handlers
    notificationService.setupNotificationHandlers();

    // Request permission
    const allowed = await notificationService.requestNotificationPermission();
    if (allowed) {
      const token = await notificationService.getDeviceToken();
      if (token) {
        await notificationService.registerDevice(token, 'ios'); // or 'android'
      }
    }
  };

  // ... rest of app
}
```

---

## Option 2: AWS Amplify Notifications

More managed experience with Amplify framework.

### Setup

```bash
npm install @aws-amplify/notifications @aws-amplify/core
```

### Configuration

```typescript
// src/services/amplify-notifications.ts
import { Amplify } from '@aws-amplify/core';
import { Notifications } from '@aws-amplify/notifications';

Amplify.configure({
  Notifications: {
    AWS_PINPOINT: {
      appId: process.env.EXPO_PUBLIC_PINPOINT_APP_ID,
      region: 'us-east-1',
    }
  }
});

export async function sendNotification(title: string, message: string) {
  try {
    await Notifications.push.send({
      title,
      body: message,
      customData: {}
    });
  } catch (error) {
    console.error('Failed to send notification:', error);
  }
}
```

---

## Option 3: OneSignal (Third-party, Recommended for Simplicity)

Easier setup than AWS SNS, works great with AWS backend.

### Setup

```bash
npm install onesignal-react-native-plugin
```

### Configuration

```typescript
// src/services/onesignal.ts
import OneSignal from 'onesignal-react-native-plugin';

export function initializeOneSignal() {
  OneSignal.setAppId(process.env.EXPO_PUBLIC_ONESIGNAL_APP_ID!);

  // Request permission
  OneSignal.promptForPushNotificationsWithUserResponse((response) => {
    console.log('Push permission:', response);
  });

  // Listen to received notifications
  OneSignal.setNotificationWillShowInForegroundHandler((notificationReceivedEvent) => {
    const notification = notificationReceivedEvent.getNotification();
    console.log('Notification received:', notification);
    notificationReceivedEvent.complete(notification);
  });

  // Listen to notification opens
  OneSignal.setNotificationOpenedHandler((message) => {
    console.log('Notification opened:', message);
    // Handle navigation
  });
}

export async function getUserId(): Promise<string | null> {
  try {
    const externalId = await OneSignal.getOnesignalId();
    return externalId;
  } catch (error) {
    console.error('Failed to get OneSignal ID:', error);
    return null;
  }
}

export async function setUserEmail(email: string) {
  OneSignal.setEmail(email);
}
```

---

## Backend Integration

### Rails Endpoints for Device Registration

```ruby
# routes.rb
namespace :api do
  namespace :v1 do
    namespace :notifications do
      post 'register_device'
      post 'send_test'
      get 'preferences'
      patch 'preferences'
    end
  end
end

# app/controllers/api/v1/notifications_controller.rb
class Api::V1NotificationsController < ApplicationController
  def register_device
    device = current_user.notification_devices.find_or_create_by(
      device_token: params[:device_token]
    )

    device.update(
      platform: params[:platform],
      device_type: params[:device_type],
      last_seen_at: Time.current
    )

    # Register with SNS
    if Rails.env.production?
      endpoint_arn = AwsSnsService.register_device(
        current_user.id,
        params[:device_token],
        params[:platform]
      )
      device.update(sns_endpoint_arn: endpoint_arn)
    end

    render json: { success: true }
  end

  def send_test
    device = current_user.notification_devices.find(params[:device_id])

    AwsSnsService.send_notification(
      device.sns_endpoint_arn,
      'Test Notification',
      'This is a test notification from AMOS',
      { type: 'test' }
    )

    render json: { success: true }
  end
end
```

### Notification Database Model

```ruby
# db/migrate/xxx_create_notification_devices.rb
create_table :notification_devices do |t|
  t.references :user, foreign_key: true
  t.string :device_token, null: false
  t.string :platform, null: false # ios, android
  t.string :device_type
  t.string :sns_endpoint_arn
  t.datetime :last_seen_at
  t.timestamps
end

# app/models/notification_device.rb
class NotificationDevice < ApplicationRecord
  belongs_to :user
  validates :device_token, :platform, presence: true
end
```

---

## Cost Comparison (Monthly, 1M Notifications)

| Service | Estimated Cost | Notes |
|---------|----------------|-------|
| AWS SNS | $100-150 | $0.50/million + free tier |
| AWS Amplify | $150-200 | Includes other features |
| OneSignal | $0 (free tier 10K/mo) | Generous free tier |
| Firebase | $0 (free) | No cost for push |
| Twilio | $500+ | Most expensive |

---

## Recommendation

**For AMOS:**

1. **Start with**: AWS SNS + React Native
   - Best integration with your AWS infrastructure
   - Lower costs
   - Full control
   - Scales with your app

2. **If you want simplicity**: OneSignal
   - Faster setup
   - Free tier covers small apps
   - Can call AWS backend from their webhooks
   - Easy migration path

3. **If cost is priority**: Firebase Cloud Messaging
   - Completely free
   - No AWS dependency
   - Works great with React Native

---

## Implementation Timeline

### AWS SNS (Recommended):
- Backend setup: 2-3 hours
- Mobile setup: 1-2 hours
- Total: 3-5 hours

### OneSignal:
- Backend setup: 1 hour
- Mobile setup: 1 hour
- Total: 2 hours

### Firebase:
- Backend setup: 30 minutes
- Mobile setup: 30 minutes
- Total: 1 hour

---

## Next Steps

Let me know which option you prefer and I'll implement the full setup including:
- Backend configuration
- Mobile integration
- Deep linking for notification actions
- Notification preferences management
