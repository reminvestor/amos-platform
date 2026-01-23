import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/screens/marketplace/marketplace_screen.dart';
import 'package:amos_mobile/config/theme.dart';

void main() {
  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const MarketplaceScreen(),
    );
  }

  group('MarketplaceScreen', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(MarketplaceScreen), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Marketplace'), findsOneWidget);
    });

    testWidgets('displays Agent Marketplace header', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Agent Marketplace'), findsOneWidget);
      expect(
        find.text('Discover and install pre-built agents to automate your workflows'),
        findsOneWidget,
      );
    });

    testWidgets('displays Featured Agents section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Featured Agents'), findsOneWidget);
    });

    testWidgets('displays Email Campaign Assistant agent', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Email Campaign Assistant'), findsOneWidget);
      expect(
        find.text('Automates email campaign creation and scheduling'),
        findsOneWidget,
      );
    });

    testWidgets('displays Lead Qualifier agent', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Lead Qualifier'), findsOneWidget);
      expect(
        find.text('Scores and qualifies incoming leads automatically'),
        findsOneWidget,
      );
    });

    testWidgets('displays Social Media Scheduler agent', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Social Media Scheduler'), findsOneWidget);
      expect(
        find.text('Plans and schedules social media posts'),
        findsOneWidget,
      );
    });

    testWidgets('displays Integration Agents section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Integration Agents'), findsOneWidget);
    });

    testWidgets('displays Stripe Revenue Reporter agent', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Stripe Revenue Reporter'), findsOneWidget);
      expect(
        find.text('Tracks and reports on Stripe revenue metrics'),
        findsOneWidget,
      );
    });

    testWidgets('displays HubSpot Sync Agent', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('HubSpot Sync Agent'), findsOneWidget);
      expect(
        find.text('Syncs contacts and deals with HubSpot CRM'),
        findsOneWidget,
      );
    });

    testWidgets('displays Coming Soon section', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Coming Soon'), findsOneWidget);
      expect(find.text('More agents coming soon!'), findsOneWidget);
    });

    testWidgets('displays Installed badge for Email Campaign Assistant', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Installed'), findsOneWidget);
    });

    testWidgets('displays Install buttons for non-installed agents', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should have multiple Install buttons (for non-installed agents)
      expect(find.text('Install'), findsWidgets);
    });

    testWidgets('tapping Install button shows snackbar', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap the first Install button
      final installButtons = find.text('Install');
      expect(installButtons, findsWidgets);

      await tester.tap(installButtons.first);
      await tester.pump();

      // Verify snackbar appears
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('screen is scrollable', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify SingleChildScrollView is present
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
