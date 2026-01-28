import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Screenshot helper for App Store submission
class ScreenshotHelper {
  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final String deviceName;
  int _screenshotIndex = 0;

  ScreenshotHelper({
    required this.binding,
    required this.tester,
    this.deviceName = 'device',
  });

  /// Initialize screenshot directory
  Future<void> initialize() async {
    final dir = Directory('screenshots/$deviceName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// Capture a screenshot with auto-incrementing index
  Future<void> capture(String name, {String? description}) async {
    _screenshotIndex++;
    final filename = '${_screenshotIndex.toString().padLeft(2, '0')}_$name';

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    try {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();

      final bytes = await binding.takeScreenshot(filename);

      final file = File('screenshots/$deviceName/$filename.png');
      await file.writeAsBytes(bytes);

      debugPrint('Screenshot captured: $filename${description != null ? ' - $description' : ''}');
    } catch (e) {
      debugPrint('Screenshot failed: $filename - $e');
    }
  }

  /// Wait for network/animation settle then capture
  Future<void> captureAfterSettle(
    String name, {
    Duration settleTime = const Duration(seconds: 2),
    String? description,
  }) async {
    await tester.pumpAndSettle(settleTime);
    await capture(name, description: description);
  }

  /// Navigate to a route and capture
  Future<void> navigateAndCapture(
    String routeName,
    String screenshotName, {
    Finder? tapTarget,
    String? description,
  }) async {
    if (tapTarget != null) {
      await tester.tap(tapTarget);
      await tester.pumpAndSettle();
    }
    await captureAfterSettle(screenshotName, description: description);
  }
}

/// Screenshot configuration for different screen types
class ScreenshotConfig {
  // App Store requires these screenshot sizes (as of 2024):
  // iPhone 6.9": iPhone 16 Pro Max (1320 x 2868)
  // iPhone 6.5": iPhone 15 Plus/14 Plus (1284 x 2778)
  // iPhone 5.5": iPhone 8 Plus (1242 x 2208)
  // iPad Pro 12.9" 6th gen: (2048 x 2732)
  // iPad Pro 12.9" 2nd gen: (2048 x 2732)

  static const List<String> requiredDevices = [
    'iPhone 16 Pro Max',  // 6.9"
    'iPhone 15 Plus',     // 6.7" (can substitute for 6.5")
    'iPad Pro 13-inch (M4)',
  ];

  static const List<String> appStoreScreenNames = [
    'login',
    'home',
    'chat',
    'agents',
    'tasks',
    'settings',
  ];
}
