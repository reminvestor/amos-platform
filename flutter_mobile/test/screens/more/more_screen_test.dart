import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/screens/more/more_screen.dart';
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
        home: const MoreScreen(),
      ),
    );
  }

  group('MoreScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('displays user profile card when logged in', (tester) async {
      final user = User(
        id: '1',
        email: 'john@example.com',
        name: 'John Doe',
        mfaEnabled: true,
      );
      await tester.pumpWidget(createTestWidget(user: user));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('john@example.com'), findsOneWidget);
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('hides user profile card when not logged in', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should not show user name when not logged in
      expect(find.text('John Doe'), findsNothing);
    });

    testWidgets('displays Account section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('displays Business Profile menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Business Profile'), findsOneWidget);
      expect(find.text('Your business info and brand voice'), findsOneWidget);
    });

    testWidgets('displays Settings menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('App preferences and notifications'), findsOneWidget);
    });

    testWidgets('displays Notifications menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Manage notification preferences'), findsOneWidget);
    });

    testWidgets('displays Integrations section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Integrations'), findsOneWidget);
    });

    testWidgets('displays Connected Apps menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Connected Apps'), findsOneWidget);
      expect(find.text('Manage your connected integrations'), findsOneWidget);
    });

    testWidgets('displays Marketplace section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Marketplace'), findsOneWidget);
    });

    testWidgets('displays Browse Templates menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Browse Templates'), findsOneWidget);
      expect(find.text('Explore pre-built templates'), findsOneWidget);
    });

    testWidgets('displays AI Agents menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('AI Agents'), findsOneWidget);
      expect(find.text('Discover and install AI agents'), findsOneWidget);
    });

    testWidgets('displays Support section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Support'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Support'), findsOneWidget);
    });

    testWidgets('displays Help Center menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Help Center'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Help Center'), findsOneWidget);
      expect(find.text('FAQs and documentation'), findsOneWidget);
    });

    testWidgets('displays Contact Support menu item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Contact Support'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('Get help from our team'), findsOneWidget);
    });

    testWidgets('displays Sign Out button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Sign Out'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('displays app version', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Amos v1.0.0'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Amos v1.0.0'), findsOneWidget);
    });

    testWidgets('tapping Help Center shows coming soon snackbar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Help Center'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Help Center'));
      await tester.pump();

      expect(find.text('Help Center coming soon'), findsOneWidget);
    });

    testWidgets('tapping Contact Support shows coming soon snackbar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Contact Support'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Contact Support'));
      await tester.pump();

      expect(find.text('Contact Support coming soon'), findsOneWidget);
    });

    testWidgets('tapping Sign Out shows confirmation dialog', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

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
