import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeMode', () {
    test('ThemeMode enum has all expected values', () {
      expect(ThemeMode.values.length, equals(3));
      expect(ThemeMode.values, contains(ThemeMode.system));
      expect(ThemeMode.values, contains(ThemeMode.light));
      expect(ThemeMode.values, contains(ThemeMode.dark));
    });

    test('ThemeMode.name returns correct string', () {
      expect(ThemeMode.system.name, equals('system'));
      expect(ThemeMode.light.name, equals('light'));
      expect(ThemeMode.dark.name, equals('dark'));
    });

    test('ThemeMode can be found by name', () {
      expect(
        ThemeMode.values.firstWhere((e) => e.name == 'light'),
        equals(ThemeMode.light),
      );
      expect(
        ThemeMode.values.firstWhere((e) => e.name == 'dark'),
        equals(ThemeMode.dark),
      );
      expect(
        ThemeMode.values.firstWhere((e) => e.name == 'system'),
        equals(ThemeMode.system),
      );
    });

    test('ThemeMode fallback works for unknown values', () {
      final result = ThemeMode.values.firstWhere(
        (e) => e.name == 'unknown',
        orElse: () => ThemeMode.system,
      );
      expect(result, equals(ThemeMode.system));
    });
  });
}
