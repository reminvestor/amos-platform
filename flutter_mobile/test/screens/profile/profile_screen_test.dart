import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/screens/profile/profile_screen.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/models/user.dart';

void main() {
  Widget createTestWidget({User? user}) {
    return ProviderScope(
      overrides: [
        authStateProvider.overrideWith(() {
          return _MockAuthNotifier(user: user);
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ProfileScreen(),
      ),
    );
  }

  group('ProfileScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('My Account'), findsOneWidget);
    });

    testWidgets('displays user initials when logged in', (tester) async {
      final user = User(
        id: '1',
        email: 'john@example.com',
        name: 'John Doe',
        mfaEnabled: true,
      );
      await tester.pumpWidget(createTestWidget(user: user));
      await tester.pumpAndSettle();

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('displays user name when logged in', (tester) async {
      final user = User(
        id: '1',
        email: 'john@example.com',
        name: 'John Doe',
        mfaEnabled: true,
      );
      await tester.pumpWidget(createTestWidget(user: user));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('displays user email when logged in', (tester) async {
      final user = User(
        id: '1',
        email: 'john@example.com',
        name: 'John Doe',
        mfaEnabled: true,
      );
      await tester.pumpWidget(createTestWidget(user: user));
      await tester.pumpAndSettle();

      expect(find.text('john@example.com'), findsWidgets);
    });

    testWidgets('displays default user when not logged in', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('User'), findsOneWidget);
      expect(find.text('U'), findsOneWidget);
    });

    testWidgets('displays Account section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('ACCOUNT'), findsOneWidget);
    });

    testWidgets('displays Edit Profile option', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Change your name and photo'), findsOneWidget);
    });

    testWidgets('displays Email Address option', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Email Address'), findsOneWidget);
    });

    testWidgets('displays Security section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('SECURITY'), findsOneWidget);
    });

    testWidgets('displays Change Password option', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Update your password'), findsOneWidget);
    });

    testWidgets('displays Two-Factor Authentication option', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll to Two-Factor Authentication option
      await tester.scrollUntilVisible(
        find.text('Two-Factor Authentication'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Two-Factor Authentication'), findsOneWidget);
      expect(find.text('Add extra security to your account'), findsOneWidget);
    });

    testWidgets('displays Sign Out button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll to Sign Out button if needed
      await tester.scrollUntilVisible(
        find.text('Sign Out'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('displays Danger Zone section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find Danger Zone section
      await tester.scrollUntilVisible(
        find.text('DANGER ZONE'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('DANGER ZONE'), findsOneWidget);
    });

    testWidgets('displays Delete Account option', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find Delete Account option
      await tester.scrollUntilVisible(
        find.text('Delete Account'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsOneWidget);
      expect(find.text('Permanently delete your account and data'), findsOneWidget);
    });

    testWidgets('tapping Edit Profile shows snackbar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Profile'));
      await tester.pump();

      expect(find.text('Profile editing coming soon'), findsOneWidget);
    });

    testWidgets('tapping Change Password shows snackbar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change Password'));
      await tester.pump();

      expect(find.text('Password change coming soon'), findsOneWidget);
    });

    testWidgets('tapping Sign Out shows confirmation dialog', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll to Sign Out button if needed
      await tester.scrollUntilVisible(
        find.text('Sign Out'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping Delete Account shows confirmation dialog', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll to Delete Account option
      await tester.scrollUntilVisible(
        find.text('Delete Account'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account?'), findsOneWidget);
      expect(find.text('This action cannot be undone. All your data will be permanently deleted.'), findsOneWidget);
    });

    testWidgets('screen is scrollable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });
  });
}

// Mock AuthNotifier for testing
class _MockAuthNotifier extends AuthNotifier {
  final User? _user;

  _MockAuthNotifier({User? user}) : _user = user;

  @override
  AuthState build() {
    return AuthState(
      user: _user,
      token: _user != null ? 'mock-token' : null,
    );
  }

  @override
  Future<void> logout() async {
    state = const AuthState();
  }
}
