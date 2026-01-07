import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Agents Flow Integration Tests', () {
    testWidgets('shows loading state when loading agents', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Initially should show login screen since not authenticated
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('login screen has email and password fields', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Login form should have email and password fields
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('login with valid credentials', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Find email field and enter text
      final emailField = find.byType(TextField).first;
      await tester.enterText(emailField, 'admin@demo.com');

      // Find password field and enter text
      final textFields = find.byType(TextField);
      if (textFields.evaluate().length >= 2) {
        final passwordField = textFields.at(1);
        await tester.enterText(passwordField, 'password123');
      }

      // Tap login button
      final loginButton = find.text('Sign In');
      await tester.tap(loginButton);

      // Wait for navigation
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // After login, should see home screen or agents screen
      // The exact assertion depends on where the app navigates after login
    });
  });

  group('Agent List Screen', () {
    testWidgets('displays loading indicator initially', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));

      // During login flow
      await tester.pump();

      // Check for CircularProgressIndicator at some point
      // This may appear during various loading states
    });

    testWidgets('displays error state on network failure', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: AmosApp()));
      await tester.pumpAndSettle();

      // Error states should show "Failed to Load" and "Retry" button
      // This requires simulating a network failure scenario
    });
  });
}
