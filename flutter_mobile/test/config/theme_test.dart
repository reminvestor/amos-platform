import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/config/theme.dart';

void main() {
  group('AppColors', () {
    test('light theme colors are defined', () {
      expect(AppColors.lightPrimary, isA<Color>());
      expect(AppColors.lightPrimaryLight, isA<Color>());
      expect(AppColors.lightBackground, isA<Color>());
      expect(AppColors.lightSurface, isA<Color>());
      expect(AppColors.lightCard, isA<Color>());
      expect(AppColors.lightText, isA<Color>());
      expect(AppColors.lightTextSecondary, isA<Color>());
      expect(AppColors.lightTextTertiary, isA<Color>());
      expect(AppColors.lightBorder, isA<Color>());
    });

    test('dark theme colors are defined', () {
      expect(AppColors.darkPrimary, isA<Color>());
      expect(AppColors.darkPrimaryLight, isA<Color>());
      expect(AppColors.darkBackground, isA<Color>());
      expect(AppColors.darkSurface, isA<Color>());
      expect(AppColors.darkCard, isA<Color>());
      expect(AppColors.darkText, isA<Color>());
      expect(AppColors.darkTextSecondary, isA<Color>());
      expect(AppColors.darkTextTertiary, isA<Color>());
      expect(AppColors.darkBorder, isA<Color>());
    });

    test('semantic colors are defined', () {
      expect(AppColors.success, isA<Color>());
      expect(AppColors.warning, isA<Color>());
      expect(AppColors.error, isA<Color>());
      expect(AppColors.info, isA<Color>());
    });

    test('light and dark primary colors are different', () {
      expect(AppColors.lightPrimary, isNot(equals(AppColors.darkPrimary)));
    });

    test('light and dark background colors are different', () {
      expect(AppColors.lightBackground, isNot(equals(AppColors.darkBackground)));
    });
  });

  group('AppTheme', () {
    test('lightTheme has light brightness', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, equals(Brightness.light));
    });

    test('darkTheme has dark brightness', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, equals(Brightness.dark));
    });

    test('lightTheme uses Material 3', () {
      final theme = AppTheme.lightTheme;
      expect(theme.useMaterial3, isTrue);
    });

    test('darkTheme uses Material 3', () {
      final theme = AppTheme.darkTheme;
      expect(theme.useMaterial3, isTrue);
    });

    test('lightTheme has correct scaffold background', () {
      final theme = AppTheme.lightTheme;
      expect(theme.scaffoldBackgroundColor, equals(AppColors.lightBackground));
    });

    test('darkTheme has correct scaffold background', () {
      final theme = AppTheme.darkTheme;
      expect(theme.scaffoldBackgroundColor, equals(AppColors.darkBackground));
    });

    test('lightTheme has correct card color', () {
      final theme = AppTheme.lightTheme;
      expect(theme.cardColor, equals(AppColors.lightCard));
    });

    test('darkTheme has correct card color', () {
      final theme = AppTheme.darkTheme;
      expect(theme.cardColor, equals(AppColors.darkCard));
    });

    test('lightTheme colorScheme uses light primary', () {
      final theme = AppTheme.lightTheme;
      expect(theme.colorScheme.primary, equals(AppColors.lightPrimary));
    });

    test('darkTheme colorScheme uses dark primary', () {
      final theme = AppTheme.darkTheme;
      expect(theme.colorScheme.primary, equals(AppColors.darkPrimary));
    });

    test('themes have centered app bar titles', () {
      expect(AppTheme.lightTheme.appBarTheme.centerTitle, isTrue);
      expect(AppTheme.darkTheme.appBarTheme.centerTitle, isTrue);
    });

    test('themes have no app bar elevation', () {
      expect(AppTheme.lightTheme.appBarTheme.elevation, equals(0));
      expect(AppTheme.darkTheme.appBarTheme.elevation, equals(0));
    });

    test('input decoration has 12px border radius', () {
      final lightBorder = AppTheme.lightTheme.inputDecorationTheme.border as OutlineInputBorder?;
      final darkBorder = AppTheme.darkTheme.inputDecorationTheme.border as OutlineInputBorder?;
      
      expect(lightBorder?.borderRadius, equals(BorderRadius.circular(12)));
      expect(darkBorder?.borderRadius, equals(BorderRadius.circular(12)));
    });
  });

  group('ThemeExtension', () {
    testWidgets('isDark returns false for light theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              expect(context.isDark, isFalse);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('isDark returns true for dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              expect(context.isDark, isTrue);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('primaryColor returns correct color for light theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              expect(context.primaryColor, equals(AppColors.lightPrimary));
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('primaryColor returns correct color for dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              expect(context.primaryColor, equals(AppColors.darkPrimary));
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('textColor returns correct color for light theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              expect(context.textColor, equals(AppColors.lightText));
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('textColor returns correct color for dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              expect(context.textColor, equals(AppColors.darkText));
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('semantic colors are consistent across themes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              expect(context.successColor, equals(AppColors.success));
              expect(context.warningColor, equals(AppColors.warning));
              expect(context.errorColor, equals(AppColors.error));
              expect(context.infoColor, equals(AppColors.info));
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('surfaceColor returns correct color for light theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              expect(context.surfaceColor, equals(AppColors.lightSurface));
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('borderColor returns correct color for dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              expect(context.borderColor, equals(AppColors.darkBorder));
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });
}
