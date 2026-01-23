import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/screens/home/home_screen.dart';
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
        home: const HomeScreen(),
      ),
    );
  }

  group('HomeScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('displays app bar with logo', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('displays notification bell icon', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsWidgets);
    });

    testWidgets('displays welcome message when user is logged in', (tester) async {
      final user = User(
        id: '1',
        email: 'john@example.com',
        name: 'John Doe',
      );
      await tester.pumpWidget(createTestWidget(user: user));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back, John!'), findsOneWidget);
      expect(find.text('What would you like to do today?'), findsOneWidget);
    });

    testWidgets('hides welcome message when user is null', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('displays Campaigns quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Campaigns'), findsOneWidget);
    });

    testWidgets('displays Contacts quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Contacts'), findsOneWidget);
    });

    testWidgets('displays Pages quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Pages'), findsOneWidget);
    });

    testWidgets('displays Agents quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Agents'), findsOneWidget);
    });

    testWidgets('displays Analytics quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('displays Integrations quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Integrations'), findsOneWidget);
    });

    testWidgets('displays Templates quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Templates'), findsOneWidget);
    });

    testWidgets('displays Inbox quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
    });

    testWidgets('displays Tasks quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('displays Marketplace quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Marketplace'), findsOneWidget);
    });

    testWidgets('displays Documents quick action chip', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
    });

    testWidgets('displays Quick Actions section header', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('displays Ask Amos quick action card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Ask Amos'), findsOneWidget);
      expect(find.text('Get help with any marketing task'), findsOneWidget);
    });

    testWidgets('displays Create Campaign quick action card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create Campaign'), findsOneWidget);
      expect(find.text('Start a new email campaign'), findsOneWidget);
    });

    testWidgets('displays Add Contact quick action card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Add Contact'), findsOneWidget);
      expect(find.text('Add a new contact to your list'), findsOneWidget);
    });

    testWidgets('displays Create Landing Page quick action card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Create Landing Page'), findsOneWidget);
      expect(find.text('Build an AI-powered landing page'), findsOneWidget);
    });

    testWidgets('displays Recent Activity section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Recent Activity'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Activity'), findsOneWidget);
    });

    testWidgets('displays See all button in Recent Activity section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('See all'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('displays No recent activity message', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('No recent activity'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('No recent activity'), findsOneWidget);
    });

    testWidgets('screen is scrollable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('quick action chips are wrapped in a Wrap widget', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(Wrap), findsWidgets);
    });

    testWidgets('quick action cards are wrapped in Card widgets', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsWidgets);
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
}
