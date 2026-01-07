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

# Install Fastlane dependencies
bundle install

# Run code generation (if needed)
flutter pub run build_runner build
```

## Environment Configuration

The app uses `--dart-define` flags for environment configuration:

```bash
# Development
flutter run \
  --dart-define=ENVIRONMENT=development \
  --dart-define=API_BASE_URL=http://192.168.x.x:3000

# Production
flutter build ios --release \
  --dart-define=ENVIRONMENT=production \
  --dart-define=API_BASE_URL=https://api.amoslabs.com
```

### Available Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ENVIRONMENT` | `development`, `staging`, `production` | Auto-detected |
| `API_BASE_URL` | Backend API URL | Environment-based |
| `DEBUG_MODE` | Enable debug logging | `false` in production |
| `ANALYTICS_ENABLED` | Enable analytics | `true` in production |
| `PRIVACY_POLICY_URL` | Privacy policy URL | `https://amoslabs.com/privacy` |
| `TERMS_OF_SERVICE_URL` | Terms URL | `https://amoslabs.com/terms` |
| `SUPPORT_EMAIL` | Support email | `support@amoslabs.com` |

## iOS Deployment

### First-Time Setup

1. **Create App Store Connect API Key:**
   - Go to App Store Connect → Users and Access → Keys
   - Create a new key with "App Manager" role
   - Download the `.p8` file

2. **Configure Fastlane Match (Code Signing):**
   ```bash
   cd ios
   fastlane match init
   fastlane match appstore
   ```

3. **Set Environment Variables:**
   ```bash
   export ASC_KEY_ID="your_key_id"
   export ASC_ISSUER_ID="your_issuer_id"
   export ASC_KEY_CONTENT="base64_encoded_p8_content"
   export APPLE_APP_ID="your_app_id"
   ```

### Deploy to TestFlight

```bash
cd ios
fastlane deploy_testflight
```

This will:
1. Load App Store Connect API key
2. Auto-increment build number
3. Install CocoaPods
4. Build the IPA
5. Upload to TestFlight

### Deploy to App Store

```bash
cd ios
fastlane deploy_production
```

### Available iOS Lanes

| Lane | Description |
|------|-------------|
| `deploy_testflight` | Full TestFlight deployment |
| `deploy_production` | Full App Store deployment |
| `build_ios` | Build IPA only |
| `sync_certificates` | Sync code signing |
| `register_device` | Add new test device |
| `screenshots` | Capture app screenshots |

## Android Deployment

### First-Time Setup

1. **Create Upload Keystore:**
   ```bash
   keytool -genkey -v \
     -keystore upload-keystore.jks \
     -keyalg RSA \
     -keysize 2048 \
     -validity 10000 \
     -alias upload

   mv upload-keystore.jks android/
   ```

2. **Configure key.properties:**
   ```bash
   cp android/key.properties.example android/key.properties
   # Edit android/key.properties with your keystore info
   ```

3. **Create Google Play Service Account:**
   - Go to Google Play Console → Setup → API access
   - Create or link a service account
   - Download the JSON key file
   - Grant "Release manager" permissions

4. **Set Environment Variables:**
   ```bash
   export GOOGLE_PLAY_JSON_KEY_PATH="/path/to/play-store-key.json"
   ```

### Deploy to Internal Testing

```bash
cd android
fastlane deploy_internal
```

### Deploy to Beta

```bash
cd android
fastlane deploy_beta
```

### Deploy to Production

```bash
cd android
fastlane deploy_production
```

### Available Android Lanes

| Lane | Description |
|------|-------------|
| `build_android` | Build AAB |
| `build_apk` | Build APK |
| `deploy_internal` | Deploy to internal testing |
| `deploy_alpha` | Deploy to alpha track |
| `deploy_beta` | Deploy to beta track |
| `deploy_production` | Deploy to production |
| `promote_internal_to_beta` | Promote build |
| `increment_version_code` | Bump version |

## Version Management

### Automatic Version Bumping

Fastlane automatically increments build numbers based on the latest version in TestFlight/Play Store.

### Manual Version Update

Edit `pubspec.yaml`:
```yaml
version: 1.0.1+2  # version+buildNumber
```

Or use Fastlane:
```bash
# Bump major version (1.0.0 → 2.0.0)
bundle exec fastlane bump type:major

# Bump minor version (1.0.0 → 1.1.0)
bundle exec fastlane bump type:minor

# Bump patch version (1.0.0 → 1.0.1)
bundle exec fastlane bump type:patch
```

## App Store Metadata

Metadata files are stored in `fastlane/metadata/`:

```
fastlane/metadata/
├── android/
│   └── en-US/
│       ├── title.txt
│       ├── short_description.txt
│       ├── full_description.txt
│       └── changelogs/
│           └── 1.txt
└── ios/
    └── en-US/
        ├── name.txt
        ├── subtitle.txt
        ├── description.txt
        ├── keywords.txt
        ├── promotional_text.txt
        ├── release_notes.txt
        ├── privacy_url.txt
        ├── support_url.txt
        └── marketing_url.txt
```

## Troubleshooting

### iOS Build Fails

```bash
# Clean build
flutter clean
cd ios && rm -rf Pods Podfile.lock && pod install --repo-update
flutter build ios --release
```

### Android Build Fails

```bash
# Clean build
flutter clean
cd android && ./gradlew clean
flutter build appbundle --release
```

### Code Signing Issues (iOS)

```bash
# Reset certificates
cd ios
fastlane match nuke appstore
fastlane match appstore
```

### Keystore Issues (Android)

1. Verify `key.properties` exists and has correct paths
2. Ensure keystore file exists at specified location
3. Check passwords are correct

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy iOS
on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: |
          cd ios
          bundle install
          bundle exec fastlane deploy_testflight
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
```

## Security Notes

- Never commit `key.properties` or keystore files
- Store API keys in CI/CD secrets
- Use Fastlane Match for iOS code signing
- Rotate credentials regularly
- HTTPS is enforced for production builds
