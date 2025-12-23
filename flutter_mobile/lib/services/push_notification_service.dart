import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Service for handling push notifications
/// Supports local notifications and will integrate with FCM when configured
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final _logger = Logger('PushNotificationService');
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Stream controller for notification taps
  final _notificationTapController = StreamController<NotificationPayload>.broadcast();
  Stream<NotificationPayload> get onNotificationTap => _notificationTapController.stream;

  // Notification channels
  static const String _teamMessageChannelId = 'team_messages';
  static const String _teamMessageChannelName = 'Team Messages';
  static const String _teamMessageChannelDescription = 'Notifications for team messages';

  static const String _dmChannelId = 'direct_messages';
  static const String _dmChannelName = 'Direct Messages';
  static const String _dmChannelDescription = 'Notifications for direct messages';

  static const String _jobChannelId = 'job_notifications';
  static const String _jobChannelName = 'Background Tasks';
  static const String _jobChannelDescription = 'Notifications for background task completion';

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Create notification channels (Android)
      await _createNotificationChannels();

      _isInitialized = true;
      _logger.info('Push notification service initialized');
    } catch (e) {
      _logger.error('Failed to initialize push notifications: $e');
    }
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    try {
      // iOS
      final iosPermission = await _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

      // Android 13+
      final androidPermission = await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final granted = (iosPermission ?? true) && (androidPermission ?? true);
      _logger.info('Notification permissions granted: $granted');
      return granted;
    } catch (e) {
      _logger.error('Failed to request notification permissions: $e');
      return false;
    }
  }

  /// Show a notification for a team message
  Future<void> showTeamMessageNotification({
    required int messageId,
    required String channelName,
    required String senderName,
    required String message,
    int? threadId,
    int? channelId,
  }) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      _teamMessageChannelId,
      _teamMessageChannelName,
      channelDescription: _teamMessageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      groupKey: 'team_messages_$channelId',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = NotificationPayload(
      type: NotificationType.teamMessage,
      threadId: threadId,
      channelId: channelId,
      messageId: messageId,
    );

    await _localNotifications.show(
      messageId,
      '#$channelName',
      '$senderName: $message',
      details,
      payload: payload.toJson(),
    );

    _logger.info('Showed team message notification: $messageId');
  }

  /// Show a notification for a direct message
  Future<void> showDirectMessageNotification({
    required int messageId,
    required String senderName,
    required String message,
    required int threadId,
    bool isFromAgent = false,
  }) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      _dmChannelId,
      _dmChannelName,
      channelDescription: _dmChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      groupKey: 'dms_$threadId',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = NotificationPayload(
      type: NotificationType.directMessage,
      threadId: threadId,
      messageId: messageId,
    );

    final title = isFromAgent ? '$senderName (AI)' : senderName;

    await _localNotifications.show(
      messageId,
      title,
      message,
      details,
      payload: payload.toJson(),
    );

    _logger.info('Showed DM notification: $messageId');
  }

  /// Show a notification for a background job update
  Future<void> showJobNotification({
    required String title,
    required String message,
    String? jobType,
  }) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      _jobChannelId,
      _jobChannelName,
      channelDescription: _jobChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _localNotifications.show(
      notificationId,
      title,
      message,
      details,
    );

    _logger.info('Showed job notification: $title');
  }

  /// Register device token with the server
  Future<void> registerDeviceToken(String token) async {
    try {
      final api = ApiClient();
      await api.post('/api/v1/device_tokens', data: {
        'device_token': {
          'token': token,
          'platform': _getPlatform(),
        },
      });
      _logger.info('Device token registered');
    } catch (e) {
      _logger.error('Failed to register device token: $e');
    }
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  /// Cancel notifications for a specific thread
  Future<void> cancelForThread(int threadId) async {
    // We'd need to track notification IDs per thread for this
    // For now, just log
    _logger.info('Would cancel notifications for thread: $threadId');
  }

  // Private methods

  Future<void> _createNotificationChannels() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _teamMessageChannelId,
          _teamMessageChannelName,
          description: _teamMessageChannelDescription,
          importance: Importance.high,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _dmChannelId,
          _dmChannelName,
          description: _dmChannelDescription,
          importance: Importance.high,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _jobChannelId,
          _jobChannelName,
          description: _jobChannelDescription,
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final payload = NotificationPayload.fromJson(response.payload!);
        _notificationTapController.add(payload);
        _logger.info('Notification tapped: ${payload.type}');
      } catch (e) {
        _logger.error('Failed to parse notification payload: $e');
      }
    }
  }

  String _getPlatform() {
    // Return platform for device token registration
    return 'ios'; // or 'android' - should be detected dynamically
  }

  void dispose() {
    _notificationTapController.close();
  }
}

/// Notification types
enum NotificationType {
  teamMessage,
  directMessage,
  mention,
  agentUpdate,
}

/// Notification payload for handling taps
class NotificationPayload {
  final NotificationType type;
  final int? threadId;
  final int? channelId;
  final int? messageId;

  NotificationPayload({
    required this.type,
    this.threadId,
    this.channelId,
    this.messageId,
  });

  String toJson() {
    return '{"type":"${type.name}","threadId":$threadId,"channelId":$channelId,"messageId":$messageId}';
  }

  factory NotificationPayload.fromJson(String json) {
    // Simple JSON parsing
    final typeMatch = RegExp(r'"type":"(\w+)"').firstMatch(json);
    final threadMatch = RegExp(r'"threadId":(\d+|null)').firstMatch(json);
    final channelMatch = RegExp(r'"channelId":(\d+|null)').firstMatch(json);
    final messageMatch = RegExp(r'"messageId":(\d+|null)').firstMatch(json);

    return NotificationPayload(
      type: NotificationType.values.firstWhere(
        (t) => t.name == typeMatch?.group(1),
        orElse: () => NotificationType.teamMessage,
      ),
      threadId: threadMatch?.group(1) != 'null' ? int.tryParse(threadMatch?.group(1) ?? '') : null,
      channelId: channelMatch?.group(1) != 'null' ? int.tryParse(channelMatch?.group(1) ?? '') : null,
      messageId: messageMatch?.group(1) != 'null' ? int.tryParse(messageMatch?.group(1) ?? '') : null,
    );
  }
}
