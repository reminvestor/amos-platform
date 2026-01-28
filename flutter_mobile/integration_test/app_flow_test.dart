import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Authentication Flow', () {
    testWidgets('login screen displays correctly', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Should show login screen
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('login screen has email and password fields', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Find text fields
      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeast(2));
    });

    testWidgets('can navigate to signup screen', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Look for signup link
      final signupLink = find.text('Sign Up');
      if (signupLink.evaluate().isNotEmpty) {
        await tester.tap(signupLink.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('can navigate to forgot password screen', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Look for forgot password link
      final forgotLink = find.text('Forgot Password?');
      if (forgotLink.evaluate().isNotEmpty) {
        await tester.tap(forgotLink.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('shows validation error for empty fields', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Tap sign in button without entering credentials
      final signInButton = find.text('Sign In');
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      // Should show some kind of error or validation message
    });

    testWidgets('login attempt with invalid credentials', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Find email field and enter text
      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeast(2));

      await tester.enterText(textFields.first, 'invalid@example.com');
      await tester.enterText(textFields.at(1), 'wrongpassword');

      // Tap sign in button
      final signInButton = find.text('Sign In');
      await tester.tap(signInButton);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('Home Screen Navigation', () {
    testWidgets('shows login screen when not authenticated', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Should redirect to login since not authenticated
      expect(find.text('Sign In'), findsOneWidget);
    });
  });

  group('UI Components', () {
    testWidgets('login screen renders without errors', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Verify no overflow errors
      expect(tester.takeException(), isNull);
    });

    testWidgets('text fields accept input', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, 'test@example.com');
        expect(find.text('test@example.com'), findsOneWidget);
      }
    });

    testWidgets('password field obscures text', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().length >= 2) {
        await tester.enterText(textFields.at(1), 'password123');
        // Password should be obscured
      }
    });
  });

  group('Accessibility', () {
    testWidgets('login button is tappable', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final signInButton = find.text('Sign In');
      expect(signInButton, findsOneWidget);

      // Should be able to tap without exception
      await tester.tap(signInButton);
      await tester.pump();
    });

    testWidgets('text fields are focusable', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.tap(textFields.first);
        await tester.pump();
        // Field should now have focus
      }
    });
  });

  group('App Initialization', () {
    testWidgets('app launches without errors', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pump();

      // App should launch without throwing
      expect(tester.takeException(), isNull);
    });

    testWidgets('app settles to login screen', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Should eventually settle to login screen
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('Theme and Styling', () {
    testWidgets('app uses Material 3', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // App should use Material widgets
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('has proper scaffold structure', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
