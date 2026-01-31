Deploy the Flutter mobile app to Android (Google Play Store).

## Usage

For internal testing track:
```bash
cd flutter_mobile && ./deploy-android.sh --internal
```

For beta track:
```bash
cd flutter_mobile && ./deploy-android.sh --beta
```

For production release:
```bash
cd flutter_mobile && ./deploy-android.sh --production
```

## Options

- `--internal` - Deploy to internal testing track (default)
- `--alpha` - Deploy to alpha/closed testing track
- `--beta` - Deploy to beta/open testing track
- `--production` - Deploy to production
- `--screenshots` - Capture screenshots before deploy
- `--screenshots-only` - Only capture screenshots, don't deploy
- `--skip-flutter-build` - Use existing build

## Prerequisites

1. Environment variables set (in `.env.production` or exported):
   - `API_BASE_URL` - Production API URL
   - `GOOGLE_PLAY_JSON_KEY` - Path to service account JSON key

2. Ruby/Fastlane installed in `flutter_mobile/android/`

3. Google Play Console service account with appropriate permissions

## What it does

1. Loads environment from `.env.production`
2. Runs `flutter build appbundle --release`
3. Runs Fastlane to upload to Google Play
4. Commits version bump to git
