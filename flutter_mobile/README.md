# AMOS Mobile (Flutter)

Cross-platform mobile app for the AMOS Marketing Platform, built with Flutter.

## Tech Stack

- **Framework**: Flutter 3.x
- **State Management**: Riverpod
- **Navigation**: go_router
- **HTTP Client**: Dio
- **Icons**: Lucide Icons
- **CI/CD**: Fastlane

## Getting Started

### Prerequisites

- Flutter SDK 3.2.0+
- Xcode 15+ (for iOS)
- Android Studio (for Android)
- Ruby (for Fastlane)

### Installation

1. **Install Flutter dependencies**
   ```bash
   cd flutter_mobile
   flutter pub get
   ```

2. **iOS Setup**
   ```bash
   cd ios
   pod install
   cd ..
   ```

3. **Run the app**
   ```bash
   # iOS Simulator
   flutter run -d ios

   # Android Emulator
   flutter run -d android

   # All connected devices
   flutter run
   ```

## Project Structure

```
lib/
├── config/
│   ├── router.dart          # Navigation configuration
│   └── theme.dart           # Theme and colors
├── models/
│   ├── user.dart
│   ├── campaign.dart
│   ├── contact.dart
│   ├── task.dart
│   ├── agent.dart
│   ├── landing_page.dart
│   └── chat.dart
├── providers/
│   ├── auth_provider.dart   # Authentication state
│   └── theme_provider.dart  # Theme mode state
├── screens/
│   ├── auth/                # Login, Forgot Password
│   ├── home/                # Dashboard
│   ├── chat/                # AI Chat
│   ├── agents/              # AI Agents
│   ├── campaigns/           # Email Campaigns
│   ├── contacts/            # Contact Management
│   ├── tasks/               # Task Manager
│   ├── landing_pages/       # Landing Pages
│   ├── settings/            # App Settings
│   └── main/                # Bottom Navigation Shell
├── services/
│   ├── api_client.dart      # HTTP client with auth
│   └── auth_service.dart    # Authentication service
└── main.dart
```

## Development

### Code Generation

For freezed and json_serializable:

```bash
flutter pub run build_runner build --delete-conflicting-outputs

# Or watch for changes
flutter pub run build_runner watch --delete-conflicting-outputs
```

### Run Tests

```bash
flutter test
```

### Analyze Code

```bash
flutter analyze
```

## Deployment with Fastlane

### Setup

1. **Install Fastlane**
   ```bash
   gem install bundler
   bundle install
   ```

2. **Configure Environment**
   ```bash
   cp .env.example .env
   # Edit .env with your credentials
   ```

### iOS Deployment

```bash
cd ios

# Deploy to TestFlight
fastlane deploy_testflight

# Deploy to App Store
fastlane deploy_production

# Sync certificates
fastlane sync_certificates
```

### Android Deployment

```bash
cd android

# Deploy to Internal Testing
fastlane deploy_internal

# Deploy to Beta
fastlane deploy_beta

# Deploy to Production
fastlane deploy_production
```

### Unified Commands

From the project root `flutter_mobile/`:

```bash
# Run tests
fastlane test

# Analyze code
fastlane analyze

# Build both platforms
fastlane build_all

# Deploy to both stores (internal/testflight)
fastlane deploy_all_internal

# Bump version
fastlane bump_version type:patch  # or minor, major
```

## Environment Configuration

Create a `.env` file based on `.env.example`:

| Variable | Description |
|----------|-------------|
| `API_BASE_URL` | Backend API URL |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `GOOGLE_PLAY_JSON_KEY_PATH` | Path to Google Play service account JSON |

## Features

- **Authentication**: Secure login with token storage
- **AI Chat**: Conversational interface with AMOS
- **AI Agents**: Run specialized marketing AI agents
- **Campaigns**: View and manage email campaigns
- **Contacts**: Browse and manage contact lists
- **Tasks**: Track marketing tasks
- **Landing Pages**: View landing page analytics
- **Dark Mode**: System-aware theme switching
- **Pull-to-Refresh**: Refresh data with gesture

## Architecture

### State Management (Riverpod)

```dart
// Define a provider
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

// Use in widgets
class MyWidget extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return Text(authState.user?.name ?? 'Guest');
  }
}
```

### Navigation (go_router)

```dart
// Navigate by name
context.goNamed('home');

// Navigate with parameters
context.pushNamed('campaign-detail', pathParameters: {'id': '123'});
```

### Theme Access

```dart
// Use theme extension
Text(
  'Hello',
  style: TextStyle(color: context.primaryColor),
);

// Check dark mode
if (context.isDark) {
  // Dark mode specific code
}
```

## Troubleshooting

### iOS Build Fails

```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
```

### Android Build Fails

```bash
cd android
./gradlew clean
flutter clean
flutter pub get
```

### Code Generation Issues

```bash
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

## Contributing

1. Create a feature branch
2. Make your changes
3. Run tests and analyze
4. Submit a pull request

## License

Proprietary - AMOS Labs
