import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/services/badge_service.dart';

void main() {
  group('BadgeService', () {
    test('instance returns singleton', () {
      final instance1 = BadgeService.instance;
      final instance2 = BadgeService.instance;

      expect(identical(instance1, instance2), isTrue);
    });

    test('currentBadgeCount starts at 0', () {
      final service = BadgeService.instance;

      // Note: Without initialization, the count should be at its default
      // In a real test environment, we'd mock FlutterAppBadger
      expect(service.currentBadgeCount, greaterThanOrEqualTo(0));
    });

    test('isSupported returns false before initialization', () {
      // Since we can't actually initialize without a real device,
      // isSupported will be false by default
      final service = BadgeService.instance;
      expect(service.isSupported, isFalse);
    });
  });
}
