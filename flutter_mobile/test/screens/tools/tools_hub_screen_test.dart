import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/screens/tools/tools_hub_screen.dart';
import 'package:amos_mobile/config/theme.dart';

void main() {
  Widget createTestWidget() {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ToolsHubScreen(),
      ),
    );
  }

  group('ToolsHubScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ToolsHubScreen), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Tools'), findsOneWidget);
    });

    testWidgets('displays Knowledge Base section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Knowledge Base'), findsOneWidget);
    });

    testWidgets('displays Documents tool card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
      expect(
        find.text('Upload and manage documents for AI knowledge'),
        findsOneWidget,
      );
    });

    testWidgets('displays Inbox section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Inbox'), findsOneWidget);
    });

    testWidgets('displays Work Items tool card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Work Items'), findsOneWidget);
      expect(
        find.text('View agent completions and notifications'),
        findsOneWidget,
      );
    });

    testWidgets('displays Productivity section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Productivity'), findsOneWidget);
    });

    testWidgets('displays Tasks tool card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsOneWidget);
      expect(
        find.text('View and manage your tasks and to-dos'),
        findsOneWidget,
      );
    });

    testWidgets('displays AI & Automation section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('AI & Automation'), findsOneWidget);
    });

    testWidgets('displays AI Agents tool card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('AI Agents'), findsOneWidget);
      expect(
        find.text('View and configure your AI agents'),
        findsOneWidget,
      );
    });

    testWidgets('displays Insights section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find Insights section
      await tester.scrollUntilVisible(
        find.text('Insights'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Insights'), findsOneWidget);
    });

    testWidgets('displays Analytics tool card', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find Analytics section
      await tester.scrollUntilVisible(
        find.text('Analytics'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Analytics'), findsOneWidget);
      expect(
        find.text('View performance metrics and insights'),
        findsOneWidget,
      );
    });

    testWidgets('displays Quick Actions section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find Quick Actions section
      await tester.scrollUntilVisible(
        find.text('Quick Actions'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick Actions'), findsOneWidget);
    });

    testWidgets('displays Upload Document quick action', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find quick actions
      await tester.scrollUntilVisible(
        find.text('Upload Document'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Upload Document'), findsOneWidget);
    });

    testWidgets('displays New Task quick action', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find quick actions
      await tester.scrollUntilVisible(
        find.text('New Task'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('New Task'), findsOneWidget);
    });

    testWidgets('displays Ask Amos quick action', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Scroll down to find quick actions
      await tester.scrollUntilVisible(
        find.text('Ask Amos'),
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ask Amos'), findsOneWidget);
    });

    testWidgets('screen is scrollable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('tool cards are tappable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify InkWell widgets exist (for tappable cards)
      expect(find.byType(InkWell), findsWidgets);
    });
  });
}
