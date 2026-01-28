import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Service for managing app icon badge (unread count indicator)
class BadgeService {
  static BadgeService? _instance;
  static BadgeService get instance {
    _instance ??= BadgeService._();
    return _instance!;
  }

  BadgeService._();

  bool _isSupported = false;
  int _currentBadgeCount = 0;

  /// Current badge count
  int get currentBadgeCount => _currentBadgeCount;

  /// Initialize and check if badges are supported
  Future<void> initialize() async {
    try {
      _isSupported = await FlutterAppBadger.isAppBadgeSupported();
      AppLogger.info('App badge supported: $_isSupported');
    } catch (e) {
      AppLogger.warning('Failed to check badge support: $e');
      _isSupported = false;
    }
  }

  /// Update the app badge with the given count
  Future<void> updateBadge(int count) async {
    if (!_isSupported) return;

    try {
      _currentBadgeCount = count;
      if (count > 0) {
        await FlutterAppBadger.updateBadgeCount(count);
        AppLogger.info('Badge updated to $count');
      } else {
        await FlutterAppBadger.removeBadge();
        AppLogger.info('Badge cleared');
      }
    } catch (e) {
      AppLogger.warning('Failed to update badge: $e');
    }
  }

  /// Increment the badge count by the given amount
  Future<void> incrementBadge([int amount = 1]) async {
    await updateBadge(_currentBadgeCount + amount);
  }

  /// Decrement the badge count by the given amount
  Future<void> decrementBadge([int amount = 1]) async {
    final newCount = (_currentBadgeCount - amount).clamp(0, 999);
    await updateBadge(newCount);
  }

  /// Clear the badge (set to 0)
  Future<void> clearBadge() async {
    await updateBadge(0);
  }

  /// Check if badges are supported on this device
  bool get isSupported => _isSupported;
}
