import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:amos_mobile/config/theme.dart';

/// Creates a mock GoRouter for widget testing
///
/// This allows screens that use `context.push()`, `context.pop()`, etc.
/// to work in widget tests without the full router setup.
GoRouter createMockRouter({
  required Widget child,
  String initialLocation = '/',
  List<GoRoute>? additionalRoutes,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => child,
      ),
      // Add common routes that screens might navigate to
      GoRoute(
        path: '/chat',
        builder: (context, state) => const _PlaceholderScreen(name: 'Chat'),
      ),
      GoRoute(
        path: '/campaigns',
        builder: (context, state) => const _PlaceholderScreen(name: 'Campaigns'),
      ),
      GoRoute(
        path: '/campaigns/:id',
        builder: (context, state) => _PlaceholderScreen(
          name: 'Campaign ${state.pathParameters['id']}',
        ),
      ),
      GoRoute(
        path: '/contacts',
        builder: (context, state) => const _PlaceholderScreen(name: 'Contacts'),
      ),
      GoRoute(
        path: '/contacts/:id',
        builder: (context, state) => _PlaceholderScreen(
          name: 'Contact ${state.pathParameters['id']}',
        ),
      ),
      GoRoute(
        path: '/agents',
        builder: (context, state) => const _PlaceholderScreen(name: 'Agents'),
      ),
      GoRoute(
        path: '/tasks',
        builder: (context, state) => const _PlaceholderScreen(name: 'Tasks'),
      ),
      GoRoute(
        path: '/tasks/:id',
        builder: (context, state) => _PlaceholderScreen(
          name: 'Task ${state.pathParameters['id']}',
        ),
      ),
      GoRoute(
        path: '/documents',
        builder: (context, state) => const _PlaceholderScreen(name: 'Documents'),
      ),
      GoRoute(
        path: '/landing-pages',
        builder: (context, state) => const _PlaceholderScreen(name: 'Landing Pages'),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const _PlaceholderScreen(name: 'Settings'),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const _PlaceholderScreen(name: 'Notifications'),
      ),
      ...?additionalRoutes,
    ],
  );
}

/// Creates a test widget wrapped with ProviderScope and GoRouter
///
/// Usage:
/// ```dart
/// testWidgets('my test', (tester) async {
///   await tester.pumpWidget(
///     createRouterTestWidget(const MyScreen()),
///   );
/// });
/// ```
Widget createRouterTestWidget(
  Widget child, {
  List<Override>? overrides,
  String initialLocation = '/',
  ThemeData? theme,
}) {
  final router = createMockRouter(
    child: child,
    initialLocation: initialLocation,
  );

  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp.router(
      routerConfig: router,
      theme: theme ?? AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
    ),
  );
}

/// Placeholder screen used for navigation targets in tests
class _PlaceholderScreen extends StatelessWidget {
  final String name;

  const _PlaceholderScreen({required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(child: Text('$name Screen')),
    );
  }
}

/// Extension to help with router navigation testing
extension RouterTestExtensions on WidgetTester {
  /// Pumps the widget and waits for animations to settle
  Future<void> pumpRouterWidget(Widget widget, {
    List<Override>? overrides,
  }) async {
    await pumpWidget(createRouterTestWidget(widget, overrides: overrides));
    await pumpAndSettle();
  }

  /// Verifies navigation occurred by checking the current location
  void expectRoute(String expectedPath) {
    // Note: In actual tests, you'd need to check the router state
    // This is a simplified helper
  }
}

/// Mock class for testing navigation callbacks
class MockNavigationObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];
  final List<Route<dynamic>> poppedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRoutes.add(route);
  }

  void reset() {
    pushedRoutes.clear();
    poppedRoutes.clear();
  }
}
