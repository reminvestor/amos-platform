# Apple App Store Submission Guide

This guide covers all steps to publish the Amos mobile app to the Apple App Store.

## Prerequisites

- [ ] Apple Developer Account ($99/year) - [developer.apple.com](https://developer.apple.com)
- [ ] Xcode 15+ installed
- [ ] Flutter SDK installed
- [ ] Physical Mac for signing and uploading

---

## Phase 1: Apple Developer Setup

### 1.1 Enroll in Apple Developer Program

1. Go to [developer.apple.com/programs](https://developer.apple.com/programs/)
2. Click "Enroll"
3. Sign in with your Apple ID (or create one)
4. Choose enrollment type:
   - **Individual**: For personal apps ($99/year)
   - **Organization**: For company apps ($99/year, requires D-U-N-S number)
5. Complete payment
6. Wait for approval (usually 24-48 hours)

### 1.2 Create App ID (Bundle Identifier)

1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select **Identifiers** → Click **+**
4. Select **App IDs** → **App**
5. Fill in:
   - **Description**: `Amos Mobile`
   - **Bundle ID**: `com.amoslabs.mobile` (must match `ios/Runner.xcodeproj`)
6. Enable capabilities:
   - [x] Push Notifications
   - [x] Associated Domains (for deep linking)
   - [x] Sign In with Apple (if used)
7. Click **Continue** → **Register**

### 1.3 Create Certificates

#### Distribution Certificate
1. On your Mac, open **Keychain Access**
2. **Keychain Access** → **Certificate Assistant** → **Request a Certificate From a Certificate Authority**
3. Fill in your email, select **Saved to disk**, click **Continue**
4. Save the `.certSigningRequest` file
5. In Apple Developer portal → **Certificates** → **+**
6. Select **Apple Distribution**
7. Upload your `.certSigningRequest` file
8. Download the certificate (`.cer`)
9. Double-click to install in Keychain

### 1.4 Create Provisioning Profile

1. **Profiles** → **+**
2. Select **App Store Connect**
3. Select your App ID (`com.amoslabs.mobile`)
4. Select your Distribution Certificate
5. Name it: `Amos Mobile App Store`
6. Download and double-click to install

---

## Phase 2: App Store Connect Setup

### 2.1 Create App in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - **Platform**: iOS
   - **Name**: `Amos - AI Assistant`
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: Select `com.amoslabs.mobile`
   - **SKU**: `amos-mobile-001`
   - **User Access**: Full Access

### 2.2 Prepare App Store Listing

#### App Information Tab
- **Name**: Amos - AI Assistant (30 chars max)
- **Subtitle**: Your Personal AI Business Partner
- **Category**: Business (Primary), Productivity (Secondary)
- **Content Rights**: Confirm you have rights
- **Age Rating**: Complete questionnaire (likely 4+)

#### Pricing and Availability
- **Price**: Free (or choose price tier)
- **Availability**: All territories (or select specific)

#### App Privacy
Complete the privacy questionnaire:
- Data collected: Email, name, usage data
- Data linked to user: Yes (for personalization)
- Data used for tracking: No

### 2.3 Prepare Screenshots

Required screenshot sizes:
| Device | Size (pixels) | Count |
|--------|---------------|-------|
| iPhone 6.7" (15 Pro Max) | 1290 x 2796 | 3-10 |
| iPhone 6.5" (11 Pro Max) | 1242 x 2688 | 3-10 |
| iPhone 5.5" (8 Plus) | 1242 x 2208 | 3-10 |
| iPad Pro 12.9" | 2048 x 2732 | 3-10 (if supporting iPad) |

**Screenshot content suggestions:**
1. Chat interface with Amos
2. Email integration connected
3. Quick actions/tools screen
4. Personal notes feature
5. Messages/collaboration view

### 2.4 Prepare App Icon

- Size: 1024 x 1024 pixels
- Format: PNG (no transparency, no rounded corners)
- Location: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

### 2.5 Write App Description

```
Amos is your AI-powered business assistant that helps you:

• Summarize and manage your email inbox
• Draft professional responses in seconds
• Take and organize personal notes
• Collaborate with your team via messages
• Access powerful AI tools for marketing and operations

Connect your Gmail or Outlook account to let Amos help you stay on top of your communications. Ask questions, get summaries, and let AI handle the busy work.

Built for entrepreneurs, marketers, and busy professionals who want to work smarter, not harder.

Key Features:
- AI Chat: Have natural conversations with your AI assistant
- Email Integration: Connect Gmail or Outlook for inbox management
- Personal Notes: Keep your thoughts organized
- Team Messages: Collaborate in real-time
- Multi-space Support: Switch between Personal and Operations modes

Privacy First: Your data is encrypted and never shared. You control what Amos can access.
```

### 2.6 Prepare Keywords

```
ai assistant, email summary, inbox management, ai chat, business assistant, productivity, email helper, marketing ai, team collaboration, notes app
```

---

## Phase 3: Configure Flutter/Xcode

### 3.1 Update iOS Configuration

Edit `ios/Runner.xcodeproj/project.pbxproj` or use Xcode:

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Runner** project → **Signing & Capabilities**
3. Set **Team** to your Apple Developer team
4. Ensure **Bundle Identifier** is `com.amoslabs.mobile`
5. Set **Version** and **Build** numbers

### 3.2 Update Info.plist

Ensure `ios/Runner/Info.plist` has required entries:

```xml
<!-- App Transport Security (for API calls) -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>

<!-- Camera usage (if applicable) -->
<key>NSCameraUsageDescription</key>
<string>Amos needs camera access to scan documents</string>

<!-- Photo library (if applicable) -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Amos needs photo access to attach images</string>

<!-- Microphone (for voice) -->
<key>NSMicrophoneUsageDescription</key>
<string>Amos needs microphone access for voice input</string>
```

### 3.3 Set Production API URL

Create a production build configuration:

```bash
# In flutter_mobile/.env.production (create this file)
API_BASE_URL=https://api.amoslabs.com
```

Or pass at build time:
```bash
flutter build ios --release --dart-define=API_BASE_URL=https://api.amoslabs.com
```

---

## Phase 4: Build and Upload

### 4.1 Build Release Archive

```bash
cd flutter_mobile

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build iOS release
flutter build ios --release --dart-define=API_BASE_URL=https://api.amoslabs.com
```

### 4.2 Archive in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select **Any iOS Device (arm64)** as build target
3. **Product** → **Archive**
4. Wait for archive to complete (shows in Organizer)

### 4.3 Upload to App Store Connect

1. In Xcode Organizer, select your archive
2. Click **Distribute App**
3. Select **App Store Connect** → **Upload**
4. Follow prompts:
   - Strip Swift symbols: Yes
   - Upload symbols: Yes
   - Manage version: Yes
5. Click **Upload**
6. Wait for processing (10-30 minutes)

### Alternative: Using Fastlane (Recommended for CI/CD)

```bash
# Install fastlane
gem install fastlane

# Initialize (run once)
cd ios
fastlane init

# Upload to TestFlight
fastlane pilot upload
```

---

## Phase 5: TestFlight Beta Testing

### 5.1 Add Internal Testers

1. In App Store Connect → **TestFlight** → **Internal Testing**
2. Add your team members (up to 100)
3. They'll receive email invitations

### 5.2 Add External Testers

1. **TestFlight** → **External Testing** → **+**
2. Create a test group (e.g., "Beta Testers")
3. Add testers by email (up to 10,000)
4. Submit for **Beta App Review** (usually 24-48 hours)

### 5.3 Collect Feedback

- Monitor crash reports in App Store Connect
- Collect feedback via TestFlight
- Fix issues and upload new builds

---

## Phase 6: App Review Submission

### 6.1 Final Checklist

- [ ] All screenshots uploaded
- [ ] App icon uploaded (1024x1024)
- [ ] Description, keywords, categories set
- [ ] Privacy policy URL added
- [ ] Support URL added
- [ ] Age rating completed
- [ ] Build selected from TestFlight
- [ ] Export compliance answered

### 6.2 App Review Information

Provide demo account credentials:
```
Email: demo@amoslabs.com
Password: DemoPassword123!
```

Add notes for reviewers:
```
To test the app:
1. Log in with the demo credentials above
2. The app requires an internet connection
3. Email integration requires OAuth - you can skip this step
4. Try asking Amos questions in the chat interface

Note: Some features require connected services (Gmail, etc.)
which may not be available in review environment.
```

### 6.3 Submit for Review

1. In App Store Connect → **App Store** tab
2. Scroll to **Build** section → Select your build
3. Click **Add for Review**
4. Answer submission questions
5. Click **Submit to App Review**

### 6.4 Review Timeline

- **First submission**: 24-48 hours typically, up to 7 days
- **Updates**: Usually faster (24 hours)
- **Rejection**: Fix issues and resubmit

---

## Phase 7: Post-Launch

### 7.1 Monitor Performance

- **App Analytics**: Downloads, sessions, retention
- **Crash Reports**: Monitor and fix crashes
- **Reviews**: Respond to user reviews

### 7.2 Update Process

1. Increment version number in `pubspec.yaml`:
   ```yaml
   version: 1.0.1+2  # version+build
   ```
2. Build and archive
3. Upload to App Store Connect
4. Submit for review
5. Release (manual or automatic)

### 7.3 Phased Release (Recommended)

- Release to 1% of users initially
- Monitor for crashes
- Gradually increase to 100%

---

## Common Rejection Reasons & Fixes

### 1. Guideline 2.1 - App Completeness
**Issue**: Crash or incomplete features
**Fix**: Test thoroughly, handle edge cases

### 2. Guideline 4.2 - Minimum Functionality
**Issue**: App doesn't do enough
**Fix**: Ensure core features work without external dependencies

### 3. Guideline 5.1.1 - Data Collection
**Issue**: Missing privacy disclosures
**Fix**: Update privacy policy, complete App Privacy questionnaire

### 4. Guideline 2.3.3 - Accurate Metadata
**Issue**: Screenshots don't match app
**Fix**: Use actual app screenshots

### 5. Guideline 4.0 - Design
**Issue**: Uses non-standard UI patterns
**Fix**: Follow iOS Human Interface Guidelines

---

## OAuth Setup for Production

Before submitting, ensure OAuth is configured for production:

### Gmail OAuth
1. Publish OAuth consent screen (removes test user limit)
2. Update redirect URI to production domain
3. May require Google verification for sensitive scopes

### Outlook OAuth
1. Register app in Azure as multi-tenant
2. Configure redirect URI for production
3. Request admin consent if needed

---

## Estimated Timeline

| Phase | Duration |
|-------|----------|
| Developer account setup | 1-3 days |
| App Store Connect setup | 1-2 days |
| Screenshots & marketing | 2-3 days |
| Build & upload | 1 day |
| TestFlight testing | 1-2 weeks |
| App Review | 1-7 days |
| **Total** | **2-4 weeks** |

---

## Resources

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Flutter iOS Deployment](https://docs.flutter.dev/deployment/ios)
