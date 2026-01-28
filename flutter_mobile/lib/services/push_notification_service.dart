import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:push/push.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Service for handling push notifications
/// Uses native APNs (iOS) / FCM (Android) for remote push notifications
/// and flutter_local_notifications for displaying them
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final _logger = Logger('PushNotificationService');
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _deviceToken;
  VoidCallback? _tokenUnsubscribe;
  VoidCallback? _messageUnsubscribe;
  VoidCallback? _tapUnsubscribe;

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
      // Initialize local notifications (for displaying notifications)
      await _initializeLocalNotifications();

      // Initialize remote push notifications (APNs/FCM)
      await _initializeRemotePush();

      _isInitialized = true;
      _logger.info('Push notification service initialized');
    } catch (e) {
      _logger.error('Failed to initialize push notifications: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // We'll request via Push package
      requestBadgePermission: false,
      requestSoundPermission: false,
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
  }

  Future<void> _initializeRemotePush() async {
    final push = Push.instance;

    // Listen for token updates
    _tokenUnsubscribe = push.addOnNewToken((token) {
      _logger.info('Received new push token: ${token.substring(0, 20)}...');
      _deviceToken = token;
      _registerTokenWithServer(token);
    });

    // Listen for incoming messages when app is in foreground
    _messageUnsubscribe = push.addOnMessage((message) {
      _logger.info('Received push message in foreground');
      _handleRemoteMessage(message);
    });

    // Handle notification taps (app was in background)
    _tapUnsubscribe = push.addOnNotificationTap((data) {
      _logger.info('User tapped notification');
      _handleNotificationTap(data);
    });

    // Check if app was launched from notification tap
    final launchData = await push.notificationTapWhichLaunchedAppFromTerminated;
    if (launchData != null) {
      _logger.info('App launched from notification tap');
      _handleNotificationTap(launchData);
    }

    // Get existing token if available
    try {
      _deviceToken = await push.token;
      if (_deviceToken != null) {
        _logger.info('Got existing push token');
        // Don't register here - wait for user to be authenticated
      }
    } catch (e) {
      _logger.error('Failed to get push token: $e');
    }
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    try {
      // Request via Push package (handles both platforms)
      await Push.instance.requestPermission();

      // Also request local notification permissions (iOS)
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

      // If permissions granted and we have a token, register it
      if (granted && _deviceToken != null) {
        await _registerTokenWithServer(_deviceToken!);
      }

      return granted;
    } catch (e) {
      _logger.error('Failed to request notification permissions: $e');
      return false;
    }
  }

  /// Register the device token with the server (call after user logs in)
  Future<void> registerDeviceIfNeeded() async {
    if (_deviceToken == null) {
      _logger.info('No device token available yet');
      return;
    }

    await _registerTokenWithServer(_deviceToken!);
  }

  /// Unregister device token (call on logout)
  Future<void> unregisterDevice() async {
    if (_deviceToken == null) return;

    try {
      final api = ApiClient();
      await api.delete('/api/v1/device_tokens', data: {
        'token': _deviceToken,
      });
      _logger.info('Device token unregistered');
    } catch (e) {
      _logger.error('Failed to unregister device token: $e');
    }
  }

  Future<void> _registerTokenWithServer(String token) async {
    try {
      // Check if user is authenticated
      final authToken = await ApiClient.instance.getAuthToken();
      if (authToken == null) {
        _logger.info('User not authenticated, skipping token registration');
        return;
      }

      final api = ApiClient();
      await api.post('/api/v1/device_tokens', data: {
        'device_token': {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      });
      _logger.info('Device token registered with server');
    } catch (e) {
      _logger.error('Failed to register device token: $e');
    }
  }

  void _handleRemoteMessage(RemoteMessage message) {
    // Extract notification data
    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      // Show as local notification
      _showFromRemoteMessage(
        title: notification.title ?? 'New Message',
        body: notification.body ?? '',
        data: data,
      );
    }
  }

  void _handleNotificationTap(Map<String?, Object?> data) {
    // Convert to our payload format
    final type = data['type']?.toString();
    final threadId = int.tryParse(data['thread_id']?.toString() ?? '');
    final messageId = int.tryParse(data['message_id']?.toString() ?? '');

    final payload = NotificationPayload(
      type: _parseNotificationType(type),
      threadId: threadId,
      messageId: messageId,
    );

    _notificationTapController.add(payload);
    _logger.info('Notification tap handled: ${payload.type}');
  }

  NotificationType _parseNotificationType(String? type) {
    switch (type) {
      case 'hub_message':
      case 'team_message':
        return NotificationType.teamMessage;
      case 'direct_message':
        return NotificationType.directMessage;
      case 'mention':
        return NotificationType.mention;
      case 'agent_update':
        return NotificationType.agentUpdate;
      default:
        return NotificationType.teamMessage;
    }
  }

  Future<void> _showFromRemoteMessage({
    required String title,
    required String body,
    Map<String?, Object?>? data,
  }) async {
    final channelId = data?['thread_type'] == 'dm' ? _dmChannelId : _teamMessageChannelId;
    final channelName = data?['thread_type'] == 'dm' ? _dmChannelName : _teamMessageChannelName;
    final channelDesc = data?['thread_type'] == 'dm' ? _dmChannelDescription : _teamMessageChannelDescription;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.high,
      priority: Priority.high,
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

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Build payload
    final payload = NotificationPayload(
      type: _parseNotificationType(data?['type']?.toString()),
      threadId: int.tryParse(data?['thread_id']?.toString() ?? ''),
      messageId: int.tryParse(data?['message_id']?.toString() ?? ''),
    );

    await _localNotifications.show(
      notificationId,
      title,
      body,
      details,
      payload: payload.toJson(),
    );
  }

  /// Show a notification for a team message (for local use)
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

  /// Show a notification for a direct message (for local use)
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

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  /// Cancel notifications for a specific thread
  Future<void> cancelForThread(int threadId) async {
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

  void dispose() {
    _tokenUnsubscribe?.call();
    _messageUnsubscribe?.call();
    _tapUnsubscribe?.call();
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
