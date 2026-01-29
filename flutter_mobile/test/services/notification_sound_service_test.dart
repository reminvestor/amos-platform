import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/services/notification_sound_service.dart';

void main() {
  group('NotificationSoundService', () {
    test('instance returns singleton', () {
      final instance1 = NotificationSoundService.instance;
      final instance2 = NotificationSoundService.instance;

      expect(identical(instance1, instance2), isTrue);
    });

    test('soundEnabled defaults to true', () {
      final service = NotificationSoundService.instance;

      expect(service.soundEnabled, isTrue);
    });

    test('soundEnabled can be toggled', () {
      final service = NotificationSoundService.instance;

      // Disable sound
      service.soundEnabled = false;
      expect(service.soundEnabled, isFalse);

      // Re-enable sound
      service.soundEnabled = true;
      expect(service.soundEnabled, isTrue);
    });

    test('dispose can be called without error', () {
      final service = NotificationSoundService.instance;

      // Should not throw
      expect(() => service.dispose(), returnsNormally);
    });
  });
}
