import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:amos_mobile/screens/main/main_shell.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/space_provider.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/models/space.dart';

void main() {
  Widget createTestWidget({
    required Widget child,
    Space? currentSpace,
    int unreadCount = 0,
    String initialLocation = '/chat',
  }) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/chat',
              name: 'chat',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/marketing-hub',
              name: 'marketing-hub',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/contacts',
              name: 'contacts',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/tools-hub',
              name: 'tools-hub',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/more',
              name: 'more',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/team-channels',
              name: 'team-channels',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/team-members',
              name: 'team-members',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/inbox',
              name: 'inbox',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/personal-notes',
              name: 'personal-notes',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: '/tasks',
              name: 'tasks',
              builder: (context, state) => child,
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        spaceProvider.overrideWith(() {
          return _MockSpaceNotifier(space: currentSpace ?? Space.work);
        }),
        realtimeProvider.overrideWith(() {
          return _MockRealtimeNotifier(unreadCount: unreadCount);
        }),
        authStateProvider.overrideWith(() {
          return _MockAuthNotifier();
        }),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }

  group('MainShell - Workspace Navigation', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('displays child content', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Content'), findsOneWidget);
    });

    testWidgets('displays bottom navigation bar', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('displays 5 navigation destinations for workspace', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(5));
    });

    testWidgets('displays Amos navigation item in workspace', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Amos'), findsOneWidget);
    });

    testWidgets('displays Marketing navigation item in workspace', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marketing'), findsOneWidget);
    });

    testWidgets('displays Contacts navigation item in workspace', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contacts'), findsOneWidget);
    });

    testWidgets('displays Tools navigation item in workspace', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tools'), findsOneWidget);
    });

    testWidgets('displays More navigation item in workspace', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('Amos tab is selected by default on /chat route', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
          initialLocation: '/chat',
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });
  });

  group('MainShell - Team Space Navigation', () {
    testWidgets('displays 4 navigation destinations for team space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('displays Amos navigation item in team space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Amos'), findsOneWidget);
    });

    testWidgets('displays Channels navigation item in team space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Channels'), findsOneWidget);
    });

    testWidgets('displays Team navigation item in team space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets('displays Inbox navigation item in team space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
    });

    testWidgets('displays unread badge on Channels when messages exist', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
          unreadCount: 5,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsWidgets);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('displays 99+ badge when unread count exceeds 99', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.team,
          unreadCount: 150,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('99+'), findsWidgets);
    });
  });

  group('MainShell - Personal Space Navigation', () {
    testWidgets('displays 4 navigation destinations for personal space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.personal,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('displays Amos navigation item in personal space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.personal,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Amos'), findsOneWidget);
    });

    testWidgets('displays Notes navigation item in personal space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.personal,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
    });

    testWidgets('displays Tasks navigation item in personal space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.personal,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsOneWidget);
    });

    testWidgets('displays Inbox navigation item in personal space', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.personal,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
    });
  });

  group('MainShell - Navigation Interaction', () {
    testWidgets('tapping navigation item triggers navigation', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the Contacts tab (index 2)
      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();

      // Navigation should have been triggered
      // The selected index should change
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 2);
    });

    testWidgets('navigation bar remains visible after navigation', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          child: const Center(child: Text('Test Content')),
          currentSpace: Space.work,
        ),
      );
      await tester.pumpAndSettle();

      // Tap on another tab
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      // Navigation bar should still be visible
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}

// Mock SpaceNotifier for testing
class _MockSpaceNotifier extends SpaceNotifier {
  final Space _space;

  _MockSpaceNotifier({required Space space}) : _space = space;

  @override
  SpaceState build() {
    return SpaceState(
      currentSpace: _space,
      availableSpaces: Space.all,
    );
  }

  @override
  Future<void> switchSpace(Space space) async {
    state = state.copyWith(currentSpace: space);
  }
}

// Mock RealtimeNotifier for testing
class _MockRealtimeNotifier extends RealtimeNotifier {
  final int _unreadCount;

  _MockRealtimeNotifier({int unreadCount = 0}) : _unreadCount = unreadCount;

  @override
  RealtimeState build() {
    return RealtimeState(
      isConnected: false,
      unreadTeamMessages: _unreadCount,
    );
  }

  @override
  Future<void> connect() async {}

  @override
  void disconnect() {}

  @override
  void clearUnreadMessages() {
    state = state.copyWith(unreadTeamMessages: 0);
  }
}

// Mock AuthNotifier for testing
class _MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState();
  }
}
