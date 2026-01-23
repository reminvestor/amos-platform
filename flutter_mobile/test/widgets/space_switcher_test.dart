import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/widgets/space_switcher.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/providers/space_provider.dart';

void main() {
  Widget createTestWidget(Widget child, {Space? initialSpace}) {
    return ProviderScope(
      overrides: [
        spaceProvider.overrideWith(() => _TestSpaceNotifier(initialSpace)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('SpaceSwitcher', () {
    testWidgets('renders correctly with default space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
      ));

      // Should display workspace name (default)
      expect(find.text('Workspace'), findsOneWidget);
    });

    testWidgets('shows label when showLabel is true', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(showLabel: true),
      ));

      expect(find.text('Workspace'), findsOneWidget);
    });

    testWidgets('hides label when showLabel is false', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(showLabel: false),
      ));

      // Should not show the space name
      expect(find.text('Workspace'), findsNothing);
    });

    testWidgets('shows chevron down icon', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
      ));

      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    });

    testWidgets('opens popup menu on tap', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
      ));

      // Tap the switcher
      await tester.tap(find.byType(SpaceSwitcher));
      await tester.pumpAndSettle();

      // Should show all space options
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Team Space'), findsOneWidget);
    });

    testWidgets('displays space descriptions in popup', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
      ));

      // Tap to open popup
      await tester.tap(find.byType(SpaceSwitcher));
      await tester.pumpAndSettle();

      // Should show descriptions
      expect(find.text('Your private workspace'), findsOneWidget);
      expect(find.text('Marketing and business tools'), findsOneWidget);
      expect(find.text('Collaborate with your team'), findsOneWidget);
    });

    testWidgets('shows check mark on selected space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
        initialSpace: Space.work,
      ));

      // Tap to open popup
      await tester.tap(find.byType(SpaceSwitcher));
      await tester.pumpAndSettle();

      // Should show check icon for selected space
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
    });

    testWidgets('shows user icon for personal space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
        initialSpace: Space.personal,
      ));

      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('shows briefcase icon for work space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
        initialSpace: Space.work,
      ));

      expect(find.byIcon(LucideIcons.briefcase), findsOneWidget);
    });

    testWidgets('shows users icon for team space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
        initialSpace: Space.team,
      ));

      expect(find.byIcon(LucideIcons.users), findsOneWidget);
    });

    testWidgets('compact mode uses smaller padding', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(compact: true),
      ));

      // Widget should render without error in compact mode
      expect(find.byType(SpaceSwitcher), findsOneWidget);
    });
  });

  group('SpaceIconButton', () {
    testWidgets('renders correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
      ));

      // Should show briefcase icon for default work space
      expect(find.byIcon(LucideIcons.briefcase), findsOneWidget);
    });

    testWidgets('shows correct icon for personal space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
        initialSpace: Space.personal,
      ));

      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('shows correct icon for team space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
        initialSpace: Space.team,
      ));

      expect(find.byIcon(LucideIcons.users), findsOneWidget);
    });

    testWidgets('has tooltip with space name', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
        initialSpace: Space.work,
      ));

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, equals('Workspace'));
    });

    testWidgets('opens bottom sheet on tap when no onTap provided', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
      ));

      await tester.tap(find.byType(SpaceIconButton));
      await tester.pumpAndSettle();

      // Should show "Switch Space" title
      expect(find.text('Switch Space'), findsOneWidget);
    });

    testWidgets('calls custom onTap when provided', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(createTestWidget(
        SpaceIconButton(onTap: () => tapped = true),
      ));

      await tester.tap(find.byType(SpaceIconButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('respects custom size', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(size: 32),
      ));

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, equals(32));
    });
  });

  group('Space model', () {
    test('isPersonal returns true for personal space', () {
      expect(Space.personal.isPersonal, isTrue);
      expect(Space.personal.isWork, isFalse);
      expect(Space.personal.isTeam, isFalse);
    });

    test('isWork returns true for work space', () {
      expect(Space.work.isPersonal, isFalse);
      expect(Space.work.isWork, isTrue);
      expect(Space.work.isTeam, isFalse);
    });

    test('isTeam returns true for team space', () {
      expect(Space.team.isPersonal, isFalse);
      expect(Space.team.isWork, isFalse);
      expect(Space.team.isTeam, isTrue);
    });

    test('Space.all contains all predefined spaces', () {
      expect(Space.all.length, equals(3));
      expect(Space.all.any((s) => s.isPersonal), isTrue);
      expect(Space.all.any((s) => s.isWork), isTrue);
      expect(Space.all.any((s) => s.isTeam), isTrue);
    });

    test('fromJson creates correct Space', () {
      final json = {
        'slug': 'custom',
        'name': 'Custom Space',
        'description': 'A custom space',
        'icon': '🔧',
        'enabled': true,
        'display_order': 5,
      };

      final space = Space.fromJson(json);
      expect(space.slug, equals('custom'));
      expect(space.name, equals('Custom Space'));
      expect(space.description, equals('A custom space'));
    });

    test('toJson returns correct map', () {
      final json = Space.personal.toJson();
      expect(json['slug'], equals('personal'));
      expect(json['name'], equals('Personal'));
    });
  });
}

/// Test notifier that allows setting initial space
class _TestSpaceNotifier extends SpaceNotifier {
  final Space? _initialSpace;

  _TestSpaceNotifier(this._initialSpace);

  @override
  SpaceState build() {
    return SpaceState(
      currentSpace: _initialSpace ?? Space.work,
      availableSpaces: Space.all,
    );
  }
}
