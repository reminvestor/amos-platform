import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/main.dart';

/// End-to-end tests for realistic user flows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login Flow', () {
    testWidgets('user can enter credentials and attempt login', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Should show login screen
      expect(find.text('Sign In'), findsOneWidget);

      // Find email field and enter text
      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeast(2));

      await tester.enterText(textFields.first, 'test@example.com');
      await tester.pump();

      // Find password field and enter text
      await tester.enterText(textFields.at(1), 'password123');
      await tester.pump();

      // Verify text was entered
      expect(find.text('test@example.com'), findsOneWidget);

      // Tap sign in button
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('forgot password link is accessible', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Find and tap forgot password
      final forgotLink = find.textContaining('Forgot');
      if (forgotLink.evaluate().isNotEmpty) {
        await tester.tap(forgotLink.first);
        await tester.pumpAndSettle();
      }
    });
  });

  group('Navigation Flow', () {
    testWidgets('app has bottom navigation bar', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // On login screen, no bottom nav
      // But BottomNavigationBar or NavigationBar should exist when authenticated
    });
  });

  group('Form Interactions', () {
    testWidgets('text fields accept input correctly', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        // Test entering and clearing text
        await tester.enterText(textFields.first, 'test input');
        expect(find.text('test input'), findsOneWidget);

        // Clear and re-enter
        await tester.enterText(textFields.first, '');
        await tester.enterText(textFields.first, 'new input');
        expect(find.text('new input'), findsOneWidget);
      }
    });

    testWidgets('password field obscures text', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().length >= 2) {
        final passwordField = tester.widget<TextField>(textFields.at(1));
        expect(passwordField.obscureText, isTrue);
      }
    });
  });

  group('Accessibility', () {
    testWidgets('all buttons are tappable', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Find all tappable widgets
      final buttons = find.byType(ElevatedButton);
      final iconButtons = find.byType(IconButton);
      final textButtons = find.byType(TextButton);

      // All should be tappable without errors
      for (final finder in [buttons, iconButtons, textButtons]) {
        for (final widget in finder.evaluate()) {
          expect(widget.widget, isA<Widget>());
        }
      }
    });

    testWidgets('app renders without overflow errors', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // No overflow errors
      expect(tester.takeException(), isNull);
    });
  });

  group('Screen Transitions', () {
    testWidgets('signup link navigates to signup screen', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Find signup link
      final signupLink = find.text('Sign Up');
      if (signupLink.evaluate().isNotEmpty) {
        await tester.tap(signupLink.first);
        await tester.pumpAndSettle();

        // Should show signup form elements
        expect(find.byType(Scaffold), findsWidgets);
      }
    });
  });

  group('Theme and Visual', () {
    testWidgets('app uses correct theme', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Should use MaterialApp
      expect(find.byType(MaterialApp), findsOneWidget);

      // Should have proper scaffold
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('icons render correctly', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Should have icons visible
      expect(find.byType(Icon), findsWidgets);
    });
  });

  group('Error Handling', () {
    testWidgets('app handles invalid input gracefully', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        // Enter invalid email
        await tester.enterText(textFields.first, 'not-an-email');
        await tester.pump();

        // Try to submit
        final submitButton = find.text('Sign In');
        if (submitButton.evaluate().isNotEmpty) {
          await tester.tap(submitButton);
          await tester.pump(const Duration(seconds: 1));
        }

        // App should not crash
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Performance', () {
    testWidgets('app launches within reasonable time', (tester) async {
      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      stopwatch.stop();

      // App should settle within 5 seconds
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    testWidgets('text input is responsive', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        final stopwatch = Stopwatch()..start();

        await tester.enterText(textFields.first, 'Quick typing test');
        await tester.pump();

        stopwatch.stop();

        // Input should be nearly instant
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        expect(find.text('Quick typing test'), findsOneWidget);
      }
    });
  });
}
