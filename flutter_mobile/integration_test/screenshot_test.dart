import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/main.dart';
import 'mocks/mock_providers.dart';

/// App Store Screenshot Integration Tests
///
/// Captures screenshots for App Store / Play Store submission.
///
/// Run with:
///   flutter drive --driver=test_driver/integration_test.dart \
///                 --target=integration_test/screenshot_test.dart
///
/// For specific device:
///   flutter drive -d "iPhone 16 Pro Max" ...
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Store Screenshots - Unauthenticated', () {
    testWidgets('01 - Login Screen', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      // Use pump instead of pumpAndSettle to avoid waiting for API calls
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Clear any text in email and password fields for clean screenshot
      final emailField = find.byType(TextField).first;
      final passwordField = find.byType(TextField).last;

      if (emailField.evaluate().isNotEmpty) {
        await tester.enterText(emailField, '');
      }
      if (passwordField.evaluate().isNotEmpty) {
        await tester.enterText(passwordField, '');
      }

      // Dismiss keyboard and wait for UI to settle
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await _captureScreenshot(binding, tester, '01_login');
    });
  });

  group('App Store Screenshots - Authenticated', () {
    testWidgets('Capture all main screens', (WidgetTester tester) async {
      // Use mock auth provider to bypass login
      await tester.pumpWidget(
        ProviderScope(
          overrides: screenshotProviderOverrides,
          child: const AmosApp(),
        ),
      );

      // Wait for app to initialize and route to authenticated screen
      // Use pump instead of pumpAndSettle to avoid waiting for API calls
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 02 - Amos Chat Screen (default after login - chat-first architecture)
      await _captureScreenshot(binding, tester, '02_amos_chat');

      // 03 - Navigate to Messages
      await _tapBottomNavItem(tester, 'Messages');
      // Messages screen needs extra time to load conversation data from API
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _captureScreenshot(binding, tester, '03_messages');

      // 04 - Navigate to Toolbox
      await _tapBottomNavItem(tester, 'Toolbox');
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _captureScreenshot(binding, tester, '04_toolbox');

      // 05 - Navigate to Profile
      await _tapBottomNavItem(tester, 'Profile');
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _captureScreenshot(binding, tester, '05_profile');

      // Try to access Settings from Inbox screen (if available via app bar)
      final settingsIcon = find.byIcon(Icons.settings);
      final moreIcon = find.byIcon(Icons.more_vert);

      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _captureScreenshot(binding, tester, '06_settings');
        await _goBack(tester);
      } else if (moreIcon.evaluate().isNotEmpty) {
        await tester.tap(moreIcon.first);
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _captureScreenshot(binding, tester, '06_more_options');
      }

      // Return to Amos tab (the main feature)
      await _tapBottomNavItem(tester, 'Amos');
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      debugPrint('All screenshots captured successfully!');
    });
  });
}

/// Captures a screenshot with the given name
/// The driver (test_driver/integration_test.dart) handles saving to disk
Future<void> _captureScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  // Give UI time to render without waiting for all async operations
  await tester.pump(const Duration(milliseconds: 500));

  try {
    // Convert surface to image and take screenshot
    // The onScreenshot callback in the driver handles saving
    await binding.takeScreenshot(name);
    debugPrint('📸 Screenshot captured: $name');
  } catch (e) {
    debugPrint('Screenshot failed for $name: $e');
  }
}

/// Tap a bottom navigation item by label
Future<void> _tapBottomNavItem(WidgetTester tester, String label) async {
  // Try finding by text in BottomNavigationBar
  final navItem = find.text(label);

  if (navItem.evaluate().isNotEmpty) {
    await tester.tap(navItem.first);
    // Use pump instead of pumpAndSettle to avoid waiting for API calls
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } else {
    debugPrint('Bottom nav item not found: $label');
  }
}

/// Go back (tap back button or use navigator)
Future<void> _goBack(WidgetTester tester) async {
  // Try finding back button
  final backButton = find.byType(BackButton);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return;
  }

  // Try finding IconButton with back arrow
  final backIcon = find.byIcon(Icons.arrow_back);
  if (backIcon.evaluate().isNotEmpty) {
    await tester.tap(backIcon.first);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return;
  }

  // Try finding leading icon button
  final leadingButton = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.icon is Icon,
  );
  if (leadingButton.evaluate().isNotEmpty) {
    await tester.tap(leadingButton.first);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
