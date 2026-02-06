# Fastlane Deployment Guide

This guide covers deploying the AMOS Mobile app to TestFlight and the App Store using Fastlane.

## Prerequisites

1. **Apple Developer Program** membership ($99/year) - https://developer.apple.com/programs/
2. **App Store Connect API Key** - Required for automated uploads
3. **Xcode** installed with command line tools

## One-Time Setup

### 1. Create App Store Connect API Key

1. Go to https://appstoreconnect.apple.com/access/api
2. Click the **+** button to create a new key
3. Give it a name (e.g., "Fastlane CI")
4. Select **Admin** role (or App Manager for more restricted access)
5. Download the `.p8` file - **you can only download this once!**
6. Note the **Key ID** and **Issuer ID** shown on the page

### 2. Configure Environment Variables

Create `ios/fastlane/.env.local` (copy from `.env`):

```bash
cd flutter_mobile/ios/fastlane
cp .env .env.local
```

Fill in the values:

```env
# From App Store Connect API Keys page
ASC_KEY_ID=ABC123DEF4          # Your Key ID
ASC_ISSUER_ID=12345678-1234-1234-1234-123456789012  # Your Issuer ID
ASC_KEY_CONTENT=LS0tLS1CRUdJTi...   # Base64 encoded .p8 file content

# From Apple Developer account
APPLE_ID=your-apple-id@example.com     # Your Apple ID email
TEAM_ID=ABCD1234EF             # Team ID from developer.apple.com/account
ITC_TEAM_ID=123456789          # iTunes Connect Team ID (often same as TEAM_ID)
APPLE_APP_ID=123456789         # App ID (assigned after app is created)

# App Identifier
APP_IDENTIFIER=com.amoslabs.mobile
```

### 3. Encode the API Key

Convert your `.p8` file to base64:

```bash
base64 -i AuthKey_ABC123DEF4.p8 | tr -d '\n'
```

Copy the output to `ASC_KEY_CONTENT` in your `.env.local`.

### 4. Find Your Team IDs

**Team ID:**
- Go to https://developer.apple.com/account
- Look in the top right or Membership section

**iTunes Connect Team ID:**
- Usually the same as Team ID
- Can find at https://appstoreconnect.apple.com (check URL or account settings)

## Commands

All commands run from `flutter_mobile/ios/`:

```bash
cd flutter_mobile/ios
```

### Create App on App Store Connect (First Time Only)

```bash
bundle exec fastlane create_app
```

This registers your app with Apple. After running, update `APPLE_APP_ID` in your `.env.local` with the assigned App ID.

### Deploy to TestFlight

```bash
bundle exec fastlane deploy_testflight
```

This will:
1. Load API credentials
2. Bump build number automatically
3. Install CocoaPods
4. Build the app
5. Upload to TestFlight

### Deploy to App Store (Production)

```bash
bundle exec fastlane deploy_production
```

This uploads to App Store Connect for review. By default:
- Does NOT auto-submit for review
- Does NOT auto-release after approval
- Skips screenshots (upload manually or use `fastlane deliver`)

### Other Useful Commands

```bash
# Run Flutter tests
bundle exec fastlane test

# Analyze code
bundle exec fastlane analyze

# Clean build artifacts
bundle exec fastlane clean

# Sync code signing certificates (if using Match)
bundle exec fastlane sync_certificates

# Register a new test device
bundle exec fastlane register_device name:"My iPhone" udid:"00001234-ABCD5678EFGH9012"
```

## Versioning

Version is controlled in `pubspec.yaml`:

```yaml
version: 1.0.1+1  # format: major.minor.patch+build
```

Fastlane auto-increments the build number based on the latest TestFlight build. To manually bump:

```bash
# From flutter_mobile/
bundle exec fastlane bump_version type:patch  # or minor, major
```

## Troubleshooting

### "No signing certificate" error

You need to set up code signing. Options:
1. **Automatic** - Let Xcode manage (open in Xcode, enable automatic signing)
2. **Match** - Use fastlane match for team certificate management

### "App ID not found" error

Run `bundle exec fastlane create_app` first, then update `APPLE_APP_ID` in `.env.local`.

### "Invalid API key" error

1. Verify Key ID and Issuer ID are correct
2. Re-encode the .p8 file to base64
3. Ensure the key has Admin or App Manager permissions

### Build fails with CocoaPods errors

```bash
cd ios
rm -rf Pods Podfile.lock
pod install
```

### Using Wrong Ruby Version

Ensure Homebrew Ruby is in your PATH:

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
ruby -v  # Should show 3.4.x
```

## CI/CD Integration

For GitHub Actions or other CI:

1. Store secrets as environment variables:
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_CONTENT`
   - `TEAM_ID`

2. Example workflow step:
```yaml
- name: Deploy to TestFlight
  env:
    ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    ASC_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
    TEAM_ID: ${{ secrets.TEAM_ID }}
  run: |
    cd flutter_mobile/ios
    bundle exec fastlane deploy_testflight
```

## File Reference

```
flutter_mobile/
├── fastlane/
│   ├── Fastfile         # Root lanes (test, analyze, build_all)
│   └── .env             # Template for environment variables
├── ios/fastlane/
│   ├── Fastfile         # iOS-specific lanes (deploy_testflight, etc.)
│   ├── Appfile          # App identifier config
│   └── .env             # iOS-specific env template
└── android/fastlane/    # Android deployment (TODO)
```

## Quick Reference

| Task | Command |
|------|---------|
| Run tests | `bundle exec fastlane test` |
| Deploy to TestFlight | `cd ios && bundle exec fastlane deploy_testflight` |
| Deploy to App Store | `cd ios && bundle exec fastlane deploy_production` |
| Create app (first time) | `cd ios && bundle exec fastlane create_app` |
| Bump version | `bundle exec fastlane bump_version type:patch` |
