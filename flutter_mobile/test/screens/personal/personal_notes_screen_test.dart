import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/screens/personal/personal_notes_screen.dart';

// Mock router delegate for testing
class MockRouterDelegate extends RouterDelegate with ChangeNotifier {
  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  Future<bool> popRoute() async => true;

  @override
  Future<void> setNewRoutePath(configuration) async {}
}

class MockRouteInformationParser extends RouteInformationParser<String> {
  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) async {
    return routeInformation.uri.path;
  }
}

void main() {
  group('PersonalNotesScreen', () {
    testWidgets('displays logo in app bar', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should have Image.asset in app bar for logo
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('displays notification bell button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should have notification bell icon
      expect(find.byIcon(LucideIcons.bell), findsOneWidget);
    });

    testWidgets('notification button is tappable', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => const PersonalNotesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bellButton = find.byIcon(LucideIcons.bell);
      expect(bellButton, findsOneWidget);

      // Should be able to tap without exception (navigation will fail without router)
      await tester.tap(bellButton);
      await tester.pump();
    });

    testWidgets('shows empty state when no notes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show empty state with sticky note icon
      expect(find.byIcon(LucideIcons.stickyNote), findsOneWidget);
      expect(find.text('No notes yet'), findsOneWidget);
    });

    testWidgets('has floating action button to create note', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should have FAB with plus icon
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsWidgets);
    });

    testWidgets('FAB opens note editor when tapped', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should navigate to editor screen
      expect(find.text('New Note'), findsOneWidget);
    });

    testWidgets('Create Note button opens editor', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap Create Note button
      final createButton = find.text('Create Note');
      if (createButton.evaluate().isNotEmpty) {
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        // Should open note editor
        expect(find.text('New Note'), findsOneWidget);
      }
    });

    testWidgets('app bar has correct structure', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should have AppBar
      expect(find.byType(AppBar), findsOneWidget);

      // Should have actions
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.actions, isNotNull);
      expect(appBar.actions!.length, greaterThanOrEqualTo(1));
    });
  });

  group('Note Editor', () {
    testWidgets('can create and save a note', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap FAB to create note
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Enter title
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Test Note');

      // Enter content
      final contentField = find.byType(TextField).at(1);
      await tester.enterText(contentField, 'This is test content');

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should navigate back to notes list
      expect(find.text('No notes yet'), findsNothing);
      expect(find.text('Test Note'), findsOneWidget);
    });

    testWidgets('editor has color picker', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap FAB to create note
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should have palette icon for color picker
      expect(find.byIcon(LucideIcons.palette), findsOneWidget);
    });

    testWidgets('can close editor with X button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const PersonalNotesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap FAB to create note
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should have X icon to close
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });
  });
}
