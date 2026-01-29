# Amos Watch App

watchOS companion app for Amos Mobile, built with SwiftUI.

## Features

- **Quick Voice Commands** - Tap to dictate commands to Amos
- **Quick Actions** - Pre-configured common actions:
  - "What needs attention?"
  - "Today's schedule"
  - "New messages"
  - "Task summary"
  - "Campaign status"
  - "Team updates"
- **Notifications** - View and manage notifications from the iPhone app
- **Connection Status** - See iPhone connection status

## Setup Instructions

### 1. Add Watch Target to Xcode Project

1. Open `flutter_mobile/ios/Runner.xcworkspace` in Xcode
2. File → New → Target
3. Select "watchOS" → "App"
4. Configure:
   - Product Name: `AmosWatch`
   - Bundle Identifier: `io.amos.mobile.watchkitapp`
   - Language: Swift
   - Interface: SwiftUI
   - Uncheck "Include Notification Scene"
5. Click Finish

### 2. Replace Generated Files

After Xcode creates the target, replace the generated files with the ones in this folder:

```bash
# Remove Xcode-generated files
rm -rf ios/AmosWatch/AmosWatch/*.swift

# The files in this folder are ready to use:
# - AmosWatchApp.swift (app entry point)
# - ContentView.swift (main view)
# - WatchConnectivityManager.swift (iPhone communication)
# - QuickCommandsView.swift (quick actions)
# - NotificationsView.swift (notifications list)
```

### 3. Configure Signing

1. Select the AmosWatch target in Xcode
2. Go to "Signing & Capabilities"
3. Set your Team
4. Bundle Identifier: `io.amos.mobile.watchkitapp`

### 4. Add Watch Connectivity to iOS App

The Flutter iOS app needs WatchConnectivity to communicate with the watch. Add this to the iOS AppDelegate or create a native module:

```swift
// In ios/Runner/AppDelegate.swift, add:
import WatchConnectivity

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ... existing code ...

        // Setup Watch Connectivity
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // WCSessionDelegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Handle messages from watch
        guard let type = message["type"] as? String else {
            replyHandler(["error": "Unknown message type"])
            return
        }

        switch type {
        case "voice_command":
            if let text = message["text"] as? String {
                // TODO: Forward to Flutter via MethodChannel
                replyHandler(["response": "Command received: \(text)"])
            }
        case "quick_action":
            if let action = message["action"] as? String {
                // TODO: Handle quick action
                replyHandler(["response": "Action \(action) executed"])
            }
        default:
            replyHandler(["status": "ok"])
        }
    }
}
```

### 5. Build and Run

1. Select the AmosWatch scheme in Xcode
2. Select an Apple Watch simulator (paired with iPhone simulator)
3. Build and Run

## Architecture

```
AmosWatch/
├── AmosWatchApp.swift        # App entry point
├── ContentView.swift          # Main view with status and navigation
├── WatchConnectivityManager.swift  # Handles iPhone <-> Watch communication
├── QuickCommandsView.swift    # Quick action buttons
├── NotificationsView.swift    # Notification list
├── Info.plist                 # Watch app configuration
└── Assets.xcassets/           # App icons
```

## Communication Flow

1. **Watch → iPhone**: Voice commands and quick actions
   - Uses `WCSession.sendMessage()` for real-time communication
   - Falls back to `updateApplicationContext()` when iPhone not reachable

2. **iPhone → Watch**: Notifications and responses
   - Push notifications via `WCSession.sendMessage()`
   - Background context via `updateApplicationContext()`

## App Icon

Add your app icon images to `Assets.xcassets/AppIcon.appiconset/`. Required sizes for watchOS:
- 48x48 (24pt @2x) - Notification Center 38mm
- 55x55 (27.5pt @2x) - Notification Center 42mm
- 58x58 (29pt @2x) - Settings
- 87x87 (29pt @3x) - Settings
- 80x80 (40pt @2x) - Home Screen 38mm
- 88x88 (44pt @2x) - Home Screen 40mm
- 100x100 (50pt @2x) - Home Screen 44mm
- 172x172 (86pt @2x) - Short Look 38mm
- 196x196 (98pt @2x) - Short Look 42mm
- 216x216 (108pt @2x) - Short Look 44mm
- 1024x1024 (1024pt @1x) - App Store
