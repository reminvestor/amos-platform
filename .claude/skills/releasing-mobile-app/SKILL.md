# Releasing Mobile App

Build and deploy the AMOS mobile app to App Store and Play Store.

## Description

This skill covers building production releases, managing version numbers, code signing, and deploying to app stores. It handles both iOS (App Store / TestFlight) and Android (Play Store / Internal Testing) distribution.

**Use this skill when:**
- Creating production or beta builds
- Incrementing version numbers
- Signing apps for distribution
- Deploying to TestFlight or Play Store
- Generating store screenshots

## Instructions

### Version Management

Version is defined in `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^     ^
#        |     build number (increment for each upload)
#        version name (shown to users)
```

**Increment version:**
```bash
# Edit pubspec.yaml, then:
cd flutter_mobile
flutter pub get
```

### Android Release Build

#### 1. Configure Signing

Create `flutter_mobile/android/key.properties`:
```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=upload
storeFile=/path/to/your/upload-keystore.jks
```

#### 2. Build Release

```bash
cd flutter_mobile

# Build APK (for direct distribution)
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release

# With environment configuration
flutter build appbundle --release \
  --dart-define=ENVIRONMENT=production \
  --dart-define=API_BASE_URL=https://api.amoslabs.com
```

Output locations:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

### iOS Release Build

#### 1. Configure Signing

Open in Xcode:
```bash
cd flutter_mobile/ios
open Runner.xcworkspace
```

In Xcode:
- Select Runner target
- Signing & Capabilities tab
- Select your Team and Bundle Identifier

#### 2. Build Archive

```bash
cd flutter_mobile

# Build iOS release
flutter build ios --release

# Or build IPA directly
flutter build ipa --release
```

#### 3. Upload to TestFlight

Option A - Xcode:
1. Open `ios/Runner.xcworkspace`
2. Product → Archive
3. Distribute App → App Store Connect

Option B - Command line:
```bash
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/amos_mobile.ipa \
  --apiKey YOUR_API_KEY \
  --apiIssuer YOUR_ISSUER_ID
```

### Environment-Specific Builds

```bash
# Development
flutter build apk --debug

# Staging
flutter build apk --release \
  --dart-define=ENVIRONMENT=staging \
  --dart-define=API_BASE_URL=https://staging-api.amoslabs.com

# Production
flutter build apk --release \
  --dart-define=ENVIRONMENT=production \
  --dart-define=API_BASE_URL=https://api.amoslabs.com
```

### Pre-Release Checklist

Before releasing:

- [ ] Update version in `pubspec.yaml`
- [ ] Test on physical iOS device
- [ ] Test on physical Android device
- [ ] Verify API endpoints point to production
- [ ] Check all environment variables
- [ ] Run `flutter analyze` for lint issues
- [ ] Run `flutter test` for test failures
- [ ] Update screenshots if UI changed
- [ ] Update release notes

### Build Script

```bash
#!/bin/bash
# .claude/skills/releasing-mobile-app/scripts/build-release.sh

set -e

cd flutter_mobile

echo "🧹 Cleaning..."
flutter clean
flutter pub get

echo "🔍 Analyzing..."
flutter analyze

echo "🧪 Testing..."
flutter test

echo "🤖 Building Android..."
flutter build appbundle --release \
  --dart-define=ENVIRONMENT=production

echo "🍎 Building iOS..."
flutter build ipa --release \
  --dart-define=ENVIRONMENT=production

echo "✅ Builds complete!"
echo "Android: build/app/outputs/bundle/release/app-release.aab"
echo "iOS: build/ios/ipa/*.ipa"
```

### Troubleshooting

**Issue: Android signing fails**
```bash
# Verify key.properties exists and paths are correct
cat android/key.properties

# Verify keystore
keytool -list -v -keystore /path/to/keystore.jks
```

**Issue: iOS provisioning profile expired**
- Open Xcode
- Preferences → Accounts → Download Manual Profiles
- Or regenerate in Apple Developer Portal

**Issue: Build number already used**
- Increment build number in `pubspec.yaml`: `1.0.0+2` → `1.0.0+3`

**Issue: Pod install fails**
```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
```

## Examples

**Build Android release:**
```
Use releasing-mobile-app to build Android production release
```

**Full release workflow:**
```
Use releasing-mobile-app to run pre-release checklist and build both platforms
```

**Deploy to TestFlight:**
```
Use releasing-mobile-app to build and upload iOS to TestFlight
```

## Store Listing Resources

- App icon: `flutter_mobile/android/app/src/main/res/` (Android)
- App icon: `flutter_mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/` (iOS)
- Screenshots: Generate at standard sizes for each platform
- Release notes: Keep concise, focus on user-visible changes

## Related Skills

- [Running Flutter App](../running-flutter-app/SKILL.md) - Testing before release
- [Debugging Mobile API](../debugging-mobile-api/SKILL.md) - Verify production API
