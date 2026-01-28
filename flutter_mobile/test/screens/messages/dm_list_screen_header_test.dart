import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/screens/messages/dm_list_screen.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';

void main() {
  group('DmListScreen Header', () {
    testWidgets('displays BrandedAppBar with logo', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realtimeProvider.overrideWith(() => _MockRealtimeNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const DmListScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have BrandedAppBar
        expect(find.byType(BrandedAppBar), findsOneWidget);

        // Should have logo image
        expect(find.byType(Image), findsOneWidget);
      });
    });

    testWidgets('displays refresh button', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realtimeProvider.overrideWith(() => _MockRealtimeNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const DmListScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have refresh icon
        expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
      });
    });

    testWidgets('displays notification bell button', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realtimeProvider.overrideWith(() => _MockRealtimeNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const DmListScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have notification bell icon
        expect(find.byIcon(LucideIcons.bell), findsOneWidget);
      });
    });

    testWidgets('displays new message FAB', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realtimeProvider.overrideWith(() => _MockRealtimeNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const DmListScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should have FAB with pen icon
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.byIcon(LucideIcons.squarePen), findsOneWidget);
      });
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realtimeProvider.overrideWith(() => _MockRealtimeNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const DmListScreen(),
            ),
          ),
        );
        await tester.pump();

        // Should show loading indicator
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    });
  });
}

/// Mock realtime notifier for testing
class _MockRealtimeNotifier extends RealtimeNotifier {
  @override
  RealtimeState build() {
    return const RealtimeState(
      isConnected: false,
      unreadTeamMessages: 0,
    );
  }
}
