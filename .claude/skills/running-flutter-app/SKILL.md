# Running Flutter App

Start and debug the AMOS Flutter mobile application on devices, emulators, and web browsers.

## Description

This skill provides commands for running, debugging, and managing the AMOS Flutter mobile app. It handles device selection, hot reload, build modes, and common troubleshooting for iOS Simulator, Android Emulator, and Chrome web.

**Use this skill when:**
- Starting the Flutter development server
- Running on iOS Simulator, Android Emulator, or Chrome
- Hot reloading after code changes
- Debugging app startup or runtime issues
- Checking available devices
- Cleaning build artifacts

## Instructions

### Quick Start

```bash
# Start on Chrome (fastest for development)
cd flutter_mobile && flutter run -d chrome

# Start on iOS Simulator
cd flutter_mobile && flutter run -d ios

# Start on Android Emulator
cd flutter_mobile && flutter run -d android
```

### Available Actions

**1. run** - Start the app
```bash
# Run on Chrome (web)
./.claude/skills/running-flutter-app/scripts/flutter-run.sh chrome

# Run on iOS Simulator
./.claude/skills/running-flutter-app/scripts/flutter-run.sh ios

# Run on Android Emulator
./.claude/skills/running-flutter-app/scripts/flutter-run.sh android
```

**2. devices** - List available devices
```bash
cd flutter_mobile && flutter devices
```

**3. clean** - Clean build artifacts
```bash
cd flutter_mobile && flutter clean && flutter pub get
```

**4. logs** - View Flutter logs
```bash
cd flutter_mobile && flutter logs
```

### Hot Reload vs Hot Restart

While the app is running:
- **Hot Reload** (`r`): Rebuilds widget tree, preserves state. Use for UI changes.
- **Hot Restart** (`R`): Full restart, clears state. Use for logic changes.
- **Quit** (`q`): Stop the app.

### Environment Configuration

The app uses dart-define flags for configuration:

```bash
# Development (default)
flutter run -d chrome

# With custom API URL (for physical devices)
flutter run -d android --dart-define=API_BASE_URL=http://192.168.1.100:3000

# Production build
flutter run --release --dart-define=ENVIRONMENT=production
```

### Common Issues

**Issue: Chrome shows blank screen**
```bash
flutter clean && flutter pub get && flutter run -d chrome
```

**Issue: iOS Simulator not found**
```bash
open -a Simulator  # Start simulator first
flutter devices    # Verify it appears
flutter run -d ios
```

**Issue: Android Emulator not connecting**
```bash
flutter doctor     # Check Android setup
flutter devices    # Verify emulator is running
```

**Issue: API connection refused**
- Ensure Rails backend is running: `docker compose up -d`
- Check API_BASE_URL in `lib/config/env.dart`
- For physical devices, use your machine's LAN IP, not localhost

## Examples

**Start development on Chrome:**
```
Use running-flutter-app with action=run device=chrome
```

**Clean and restart:**
```
Use running-flutter-app with action=clean
Use running-flutter-app with action=run device=chrome
```

**Debug on physical Android device:**
```
Use running-flutter-app with action=devices
Use running-flutter-app with action=run device=android api_url=http://192.168.1.100:3000
```

## Project Structure

```
flutter_mobile/
├── lib/
│   ├── main.dart              # App entry point
│   ├── config/
│   │   ├── env.dart           # Environment configuration
│   │   ├── router.dart        # Navigation routes
│   │   └── theme.dart         # App theme
│   ├── models/                # Data models
│   ├── providers/             # Riverpod providers
│   ├── screens/               # UI screens
│   ├── services/              # API services
│   └── widgets/               # Reusable widgets
├── test/                      # Test files
├── pubspec.yaml               # Dependencies
└── .env.example               # Environment template
```

## Related Skills

- [Debugging Mobile API](../debugging-mobile-api/SKILL.md) - API connectivity issues
- [Building Flutter Screens](../building-flutter-screens/SKILL.md) - Adding new screens
- [Releasing Mobile App](../releasing-mobile-app/SKILL.md) - Production builds
