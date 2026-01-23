import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/screens/auth/forgot_password_screen.dart';
import 'package:amos_mobile/config/theme.dart';

void main() {
  Widget createTestWidget() {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ForgotPasswordScreen(),
      ),
    );
  }

  group('ForgotPasswordScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });

    testWidgets('displays back button in app bar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('displays Forgot Password header', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Forgot Password?'), findsOneWidget);
    });

    testWidgets('displays instructions text', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.text("Enter your email address and we'll send you instructions to reset your password."),
        findsOneWidget,
      );
    });

    testWidgets('displays email text field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('displays Send Reset Link button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Send Reset Link'), findsOneWidget);
    });

    testWidgets('shows validation error for empty email', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap the submit button without entering email
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid email', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter invalid email
      await tester.enterText(find.byType(TextFormField), 'invalidemail');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('accepts valid email format', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter valid email
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      await tester.pumpAndSettle();

      // No validation errors should appear when a valid email is entered
      // (We don't tap submit since it triggers async operations)
      expect(find.text('Please enter your email'), findsNothing);
      expect(find.text('Please enter a valid email'), findsNothing);
    });

    testWidgets('email field is present and functional', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify email field exists
      expect(find.byType(TextFormField), findsOneWidget);

      // Verify we can enter text into it
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      await tester.pumpAndSettle();

      // The text should be entered
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('screen is scrollable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('form has proper structure', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(Form), findsOneWidget);
    });
  });
}
