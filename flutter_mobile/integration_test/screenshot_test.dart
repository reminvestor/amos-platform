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
      await tester.pumpAndSettle(const Duration(seconds: 3));

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
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 02 - Amos Chat Screen (default after login - chat-first architecture)
      await _captureScreenshot(binding, tester, '02_amos_chat');

      // 03 - Navigate to Notes (Personal Notes)
      await _tapBottomNavItem(tester, 'Notes');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await _captureScreenshot(binding, tester, '03_personal_notes');

      // 04 - Navigate to Messages (DMs)
      await _tapBottomNavItem(tester, 'Messages');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await _captureScreenshot(binding, tester, '04_messages');

      // 05 - Navigate to Inbox (Agent Questions & Activity)
      await _tapBottomNavItem(tester, 'Inbox');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await _captureScreenshot(binding, tester, '05_inbox');

      // Try to access Settings from Inbox screen (if available via app bar)
      final settingsIcon = find.byIcon(Icons.settings);
      final moreIcon = find.byIcon(Icons.more_vert);

      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await _captureScreenshot(binding, tester, '06_settings');
        await _goBack(tester);
      } else if (moreIcon.evaluate().isNotEmpty) {
        await tester.tap(moreIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await _captureScreenshot(binding, tester, '06_more_options');
      }

      // Return to Amos tab (the main feature)
      await _tapBottomNavItem(tester, 'Amos');
      await tester.pumpAndSettle(const Duration(seconds: 1));

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
  // Ensure all animations are complete
  await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    return;
  }

  // Try finding IconButton with back arrow
  final backIcon = find.byIcon(Icons.arrow_back);
  if (backIcon.evaluate().isNotEmpty) {
    await tester.tap(backIcon.first);
    await tester.pumpAndSettle();
    return;
  }

  // Try finding leading icon button
  final leadingButton = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.icon is Icon,
  );
  if (leadingButton.evaluate().isNotEmpty) {
    await tester.tap(leadingButton.first);
    await tester.pumpAndSettle();
  }
}
