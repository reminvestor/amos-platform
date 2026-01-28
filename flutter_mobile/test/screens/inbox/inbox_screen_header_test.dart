import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/screens/inbox/inbox_screen.dart';

void main() {
  group('InboxScreen Header', () {
    testWidgets('displays logo in app bar', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have Image.asset in app bar for logo
        expect(find.byType(Image), findsOneWidget);
      });
    });

    testWidgets('displays notification bell button', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have notification bell icon
        expect(find.byIcon(LucideIcons.bell), findsOneWidget);
      });
    });

    testWidgets('displays refresh button', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have refresh icon
        expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
      });
    });

    testWidgets('has tab bar with filter tabs', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have TabBar
        expect(find.byType(TabBar), findsOneWidget);

        // Should have filter tabs
        expect(find.text('Unread'), findsOneWidget);
        expect(find.text('All'), findsOneWidget);
        expect(find.text('Starred'), findsOneWidget);
        expect(find.text('Action'), findsOneWidget);
      });
    });

    testWidgets('app bar has correct structure', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have AppBar
        expect(find.byType(AppBar), findsOneWidget);

        // Should have actions
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.actions, isNotNull);
        expect(appBar.actions!.length, greaterThanOrEqualTo(2)); // refresh + bell
      });
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should show loading indicator
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    });

    testWidgets('tab icons are present', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pump();

        // Tab icons
        expect(find.byIcon(LucideIcons.mailOpen), findsOneWidget); // Unread
        expect(find.byIcon(LucideIcons.inbox), findsOneWidget); // All
        expect(find.byIcon(LucideIcons.star), findsWidgets); // Starred (may appear multiple times)
        expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget); // Action
      });
    });
  });
}
