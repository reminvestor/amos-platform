Deploy the Flutter mobile app to iOS (TestFlight or App Store).

## Usage

For TestFlight deployment:
```bash
cd flutter_mobile && ./deploy-ios.sh --testflight
```

For App Store deployment:
```bash
cd flutter_mobile && ./deploy-ios.sh --production
```

With custom release notes:
```bash
cd flutter_mobile && ./deploy-ios.sh --testflight --notes "Fixed login bug, added new scanner feature"
```

## Options

- `--testflight` - Deploy to TestFlight (default)
- `--production` - Deploy to App Store
- `--notes "message"` - What to Test notes for testers
- `--screenshots` - Capture screenshots before deploy
- `--screenshots-only` - Only capture screenshots, don't deploy
- `--skip-flutter-build` - Use existing build

## Prerequisites

1. Environment variables set (in `.env.production` or exported):
   - `API_BASE_URL` - Production API URL
   - `ASC_KEY_ID` - App Store Connect API Key ID
   - `ASC_ISSUER_ID` - App Store Connect Issuer ID
   - `ASC_KEY_CONTENT` - App Store Connect API Key (base64)

2. Ruby/Fastlane installed in `flutter_mobile/ios/`

## What it does

1. Loads environment from `.env.production`
2. Runs `flutter build ios --release`
3. Runs Fastlane to upload to TestFlight/App Store
4. Commits version bump to git
