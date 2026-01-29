# AMOS Mobile Deployment Guide

## Prerequisites

- Flutter SDK 3.2.0+
- Xcode 15+ (for iOS)
- Android Studio with SDK 34+ (for Android)
- Ruby & Bundler (for Fastlane)
- Apple Developer Account (for iOS)
- Google Play Console Account (for Android)

## Quick Start

```bash
cd flutter_mobile

# Install Flutter dependencies
flutter pub get

# Install Fastlane dependencies (iOS)
cd ios && bundle install && cd ..

# Install Fastlane dependencies (Android)
cd android && bundle install && cd ..
```

---

## iOS Deployment

### First-Time Setup

#### 1. Create App Store Connect API Key

1. Go to [App Store Connect → Users and Access → Keys](https://appstoreconnect.apple.com/access/api)
2. Click **+** to create a new key
3. Name it (e.g., "Fastlane CI") and select **Admin** role
4. Download the `.p8` file - **you can only download this once!**
5. Note the **Key ID** and **Issuer ID**

#### 2. Configure Environment Variables

Create `ios/fastlane/.env.local`:

```bash
# From App Store Connect API Keys page
ASC_KEY_ID=ABC123DEF4
ASC_ISSUER_ID=12345678-1234-1234-1234-123456789012
ASC_KEY_CONTENT=LS0tLS1CRUdJTi...  # Base64 encoded .p8 file

# From Apple Developer account
TEAM_ID=ABCD1234EF
APPLE_APP_ID=123456789

# Production API
API_BASE_URL=https://api.amoslabs.com
```

To encode the .p8 file:
```bash
base64 -i AuthKey_ABC123DEF4.p8 | tr -d '\n'
```

#### 3. Set Up Code Signing (Fastlane Match)

```bash
cd ios
fastlane match init       # First time only
fastlane match appstore   # Download/create certificates
```

### Deploy iOS

**Using the deploy script (recommended):**

```bash
# Deploy to TestFlight
./deploy-ios.sh --testflight --notes "Bug fixes and improvements"

# Deploy to App Store (production)
./deploy-ios.sh --production

# With screenshots (auto-uploads for production)
./deploy-ios.sh --screenshots --production
```

**Using Fastlane directly:**

```bash
cd ios
bundle exec fastlane deploy_testflight
bundle exec fastlane deploy_production
```

### iOS Deploy Script Options

```
./deploy-ios.sh [OPTIONS]

Options:
  --testflight           Deploy to TestFlight (default)
  --production           Deploy to App Store
  --screenshots          Capture App Store screenshots before deploy
  --screenshots-only     Only capture screenshots (no deploy)
  --screenshot-device    Capture on specific device
  --skip-flutter-build   Skip Flutter build
  --notes "message"      TestFlight notes
  --help                 Show help
```

---

## Android Deployment

### First-Time Setup

#### 1. Create Google Play Console Account

1. Go to [Google Play Console](https://play.google.com/console)
2. Pay the $25 one-time registration fee
3. Create your app listing

#### 2. Generate Upload Keystore

**This is critical - keep this file safe! You cannot recover it.**

```bash
cd flutter_mobile

# Generate keystore
keytool -genkey -v \
  -keystore android/upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload

# When prompted, enter:
# - Keystore password (save this!)
# - Key password (can be same as keystore password)
# - Your name/organization info
```

#### 3. Configure key.properties

Create `android/key.properties`:

```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=upload
storeFile=../upload-keystore.jks
```

**⚠️ Never commit this file to git!**

#### 4. Create Google Play Service Account

1. Go to **Google Play Console → Setup → API access**
2. Click **Create new service account**
3. In Google Cloud Console:
   - Create a new service account
   - Name it (e.g., "fastlane-deploy")
   - Grant role: **Service Account User**
4. Create a JSON key and download it
5. Back in Play Console, grant the service account **Release Manager** permissions

#### 5. Configure Environment Variables

Create `.env.production` in `flutter_mobile/`:

```bash
# Production API
API_BASE_URL=https://api.amoslabs.com

# Path to service account JSON key
GOOGLE_PLAY_JSON_KEY_PATH=/path/to/play-store-service-account.json
```

Or create `android/fastlane/.env`:

```bash
GOOGLE_PLAY_JSON_KEY_PATH=/path/to/play-store-service-account.json
```

### Deploy Android

**Using the deploy script (recommended):**

```bash
# Deploy to Internal Testing
./deploy-android.sh --internal

# Deploy to Beta
./deploy-android.sh --beta

# Deploy to Production
./deploy-android.sh --production

# With screenshots (auto-uploads for production)
./deploy-android.sh --screenshots --production
```

**Using Fastlane directly:**

```bash
cd android
bundle exec fastlane deploy_internal
bundle exec fastlane deploy_beta
bundle exec fastlane deploy_production
```

### Android Deploy Script Options

```
./deploy-android.sh [OPTIONS]

Options:
  --internal             Deploy to Internal Testing (default)
  --alpha                Deploy to Alpha track
  --beta                 Deploy to Beta track
  --production           Deploy to Production
  --screenshots          Capture Play Store screenshots before deploy
  --screenshots-only     Only capture screenshots (no deploy)
  --screenshot-device    Capture on specific device
  --skip-flutter-build   Skip Flutter build
  --help                 Show help
```

### Android Release Tracks

| Track | Audience | Purpose |
|-------|----------|---------|
| Internal | Up to 100 testers | Quick testing, no review |
| Alpha | Unlimited testers | Closed testing |
| Beta | Unlimited testers | Open beta |
| Production | Everyone | Live app |

### Promoting Between Tracks

```bash
cd android

# Promote internal to beta
bundle exec fastlane promote_internal_to_beta

# Promote beta to production (10% rollout)
bundle exec fastlane promote_beta_to_production
```

---

## Screenshots

Both deploy scripts support automated screenshot capture for App Store/Play Store.

### Capture Screenshots Only

```bash
# iOS - all required devices
./deploy-ios.sh --screenshots-only

# iOS - single device
./deploy-ios.sh --screenshot-device "iPhone 16 Pro Max" --screenshots-only

# Android
./deploy-android.sh --screenshots-only
```

### Screenshots with Deploy

```bash
# Capture + deploy to production (auto-uploads screenshots)
./deploy-ios.sh --screenshots --production
./deploy-android.sh --screenshots --production
```

### Required Screenshot Sizes

**iOS (App Store):**
- iPhone 6.9": iPhone 16 Pro Max
- iPhone 6.3": iPhone 16 Pro
- iPad 12.9": iPad Pro 13-inch (M4)

**Android (Play Store):**
- Phone: Pixel 8 Pro (or similar)
- Tablet: Pixel Tablet (10")

### What Gets Captured

The screenshot test (`integration_test/screenshot_test.dart`) captures:

1. Login screen
2. Amos Chat (AI assistant)
3. Personal Notes
4. Messages
5. Inbox
6. Settings

---

## Play Store Requirements Checklist

Before your first Android release, you'll need:

- [ ] **App icon** (512x512 PNG)
- [ ] **Feature graphic** (1024x500 PNG)
- [ ] **Screenshots** (phone + tablet, 2-8 per device)
- [ ] **Short description** (80 characters max)
- [ ] **Full description** (4000 characters max)
- [ ] **Privacy policy URL** (required)
- [ ] **App category** selected
- [ ] **Content rating** questionnaire completed
- [ ] **Target audience** declaration
- [ ] **Data safety** form completed

---

## Version Management

### Automatic Version Bumping

Both deploy scripts auto-increment the build number based on the latest version in TestFlight/Play Store.

### Manual Version Update

Edit `pubspec.yaml`:

```yaml
version: 1.0.1+2  # format: version+buildNumber
```

---

## Troubleshooting

### iOS Build Fails

```bash
flutter clean
cd ios && rm -rf Pods Podfile.lock
pod install --repo-update
cd .. && flutter build ios --release
```

### Android Build Fails

```bash
flutter clean
cd android && ./gradlew clean
cd .. && flutter build appbundle --release
```

### Code Signing Issues (iOS)

```bash
cd ios
fastlane match nuke appstore  # Reset certificates
fastlane match appstore       # Regenerate
```

### Keystore Issues (Android)

1. Verify `key.properties` exists with correct paths
2. Ensure keystore file exists at specified location
3. Check passwords are correct

### Service Account Issues (Android)

```bash
cd android
bundle exec fastlane validate_bundle
```

---

## Security Notes

- **Never commit** `key.properties`, `*.jks`, or service account JSON files
- Store API keys in CI/CD secrets
- Use Fastlane Match for iOS code signing
- Keep keystores backed up securely (you cannot recover them!)
- HTTPS is enforced for production builds
