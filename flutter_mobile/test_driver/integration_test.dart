import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  // Create screenshots directory on host machine (en-US for Fastlane compatibility)
  final screenshotsDir = Directory('screenshots/en-US');
  if (!screenshotsDir.existsSync()) {
    screenshotsDir.createSync(recursive: true);
  }

  await integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/en-US/$screenshotName.png');
      await file.writeAsBytes(screenshotBytes);
      print('📸 Screenshot saved: screenshots/en-US/$screenshotName.png');
      return true;
    },
  );
}
