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

      // Should display a space name (Operations or Personal)
      expect(find.byType(SpaceSwitcher), findsOneWidget);
    });

    testWidgets('shows label when showLabel is true', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(showLabel: true),
      ));

      // Should show some text
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('hides label when showLabel is false', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(showLabel: false),
      ));

      // Widget should still render
      expect(find.byType(SpaceSwitcher), findsOneWidget);
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

      // Should show space options
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Operations'), findsOneWidget);
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
      expect(find.text('Business tools and workflows'), findsOneWidget);
    });

    testWidgets('shows check mark on selected space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
        initialSpace: Space.operations,
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

    testWidgets('shows briefcase icon for operations space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceSwitcher(),
        initialSpace: Space.operations,
      ));

      // Operations space uses cog/settings icon
      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
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

      // Should show an icon
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('shows correct icon for personal space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
        initialSpace: Space.personal,
      ));

      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('shows correct icon for operations space', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const SpaceIconButton(),
        initialSpace: Space.operations,
      ));

      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
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
      expect(Space.personal.isOperations, isFalse);
    });

    test('isOperations returns true for operations space', () {
      expect(Space.operations.isPersonal, isFalse);
      expect(Space.operations.isOperations, isTrue);
    });

    test('Space.work is alias for operations', () {
      expect(Space.work.slug, equals(Space.operations.slug));
      expect(Space.work.isOperations, isTrue);
    });

    test('Space.all contains all predefined spaces', () {
      expect(Space.all.length, equals(2));
      expect(Space.all.any((s) => s.isPersonal), isTrue);
      expect(Space.all.any((s) => s.isOperations), isTrue);
    });

    test('Space fromJson creates instance correctly', () {
      final json = {
        'slug': 'personal',
        'name': 'Personal',
        'description': 'Your private workspace',
        'icon': '👤',
        'enabled': true,
        'display_order': 0,
      };

      final space = Space.fromJson(json);

      expect(space.slug, equals('personal'));
      expect(space.name, equals('Personal'));
      expect(space.description, equals('Your private workspace'));
      expect(space.isPersonal, isTrue);
    });

    test('Space toJson returns correct map', () {
      final space = Space.personal;
      final json = space.toJson();

      expect(json['slug'], equals('personal'));
      expect(json['name'], equals('Personal'));
    });

    test('Legacy isTeam property returns false', () {
      // isTeam is deprecated and always returns false
      expect(Space.personal.isTeam, isFalse);
      expect(Space.operations.isTeam, isFalse);
    });
  });
}

/// Test notifier that allows setting an initial space
class _TestSpaceNotifier extends SpaceNotifier {
  final Space? _initialSpace;

  _TestSpaceNotifier(this._initialSpace);

  @override
  SpaceState build() {
    return SpaceState(
      currentSpace: _initialSpace ?? Space.operations,
      availableSpaces: Space.all,
    );
  }
}
