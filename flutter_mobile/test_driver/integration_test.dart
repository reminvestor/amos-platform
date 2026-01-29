import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  // Create screenshots directory on host machine
  final screenshotsDir = Directory('screenshots/appstore');
  if (!screenshotsDir.existsSync()) {
    screenshotsDir.createSync(recursive: true);
  }

  await integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/appstore/$screenshotName.png');
      await file.writeAsBytes(screenshotBytes);
      print('📸 Screenshot saved: screenshots/appstore/$screenshotName.png');
      return true;
    },
  );
}
