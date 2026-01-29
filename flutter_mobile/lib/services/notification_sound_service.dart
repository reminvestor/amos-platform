import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Service for playing in-app notification sounds
class NotificationSoundService {
  static NotificationSoundService? _instance;
  static NotificationSoundService get instance {
    _instance ??= NotificationSoundService._();
    return _instance!;
  }

  NotificationSoundService._();

  AudioPlayer? _player;
  bool _initialized = false;
  bool _soundEnabled = true;

  /// Whether notification sounds are enabled
  bool get soundEnabled => _soundEnabled;
  set soundEnabled(bool value) => _soundEnabled = value;

  /// Initialize the audio player
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _player = AudioPlayer();
      // Set to low latency mode for quick playback
      await _player!.setPlayerMode(PlayerMode.lowLatency);
      _initialized = true;
      AppLogger.info('NotificationSoundService initialized');
    } catch (e) {
      AppLogger.error('Failed to initialize notification sound', error: e);
    }
  }

  /// Play the message received notification sound
  Future<void> playMessageSound() async {
    if (!_soundEnabled) return;

    try {
      if (!_initialized) {
        await initialize();
      }

      if (_player == null) return;

      // Try to play from assets first
      try {
        await _player!.play(AssetSource('sounds/notification.mp3'));
      } catch (e) {
        // If asset doesn't exist, play system sound using haptic feedback as fallback
        AppLogger.warning('Notification sound asset not found, using haptic feedback');
        await HapticFeedback.mediumImpact();
      }
    } catch (e) {
      AppLogger.error('Failed to play notification sound', error: e);
      // Fall back to haptic feedback
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }
  }

  /// Play a subtle sound for AI response completion
  Future<void> playResponseCompleteSound() async {
    if (!_soundEnabled) return;

    try {
      if (!_initialized) {
        await initialize();
      }

      if (_player == null) {
        // Fallback to haptic
        await HapticFeedback.lightImpact();
        return;
      }

      try {
        // Use lower volume for completion sound
        await _player!.setVolume(0.5);
        await _player!.play(AssetSource('sounds/notification.mp3'));
        // Reset volume
        await _player!.setVolume(1.0);
      } catch (e) {
        // Asset not found, use haptic
        await HapticFeedback.lightImpact();
      }
    } catch (e) {
      AppLogger.error('Failed to play completion sound', error: e);
    }
  }

  /// Dispose of resources
  void dispose() {
    _player?.dispose();
    _player = null;
    _initialized = false;
  }
}
