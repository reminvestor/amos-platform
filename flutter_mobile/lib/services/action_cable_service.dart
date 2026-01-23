import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:amos_mobile/models/space.dart';

/// Service for ActionCable WebSocket connections
/// Handles real-time team messaging
class ActionCableService {
  static final ActionCableService _instance = ActionCableService._internal();
  factory ActionCableService() => _instance;
  ActionCableService._internal();

  final _logger = Logger('ActionCableService');

  WebSocketChannel? _channel;
  bool _isConnected = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _reconnectDelay = Duration(seconds: 5);

  // Stream controllers for message events
  final _messageController = StreamController<HubMessage>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _jobNotificationController = StreamController<JobNotification>.broadcast();
  final _questionQueueController = StreamController<QuestionQueueUpdate>.broadcast();

  Stream<HubMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  Stream<JobNotification> get jobNotificationStream => _jobNotificationController.stream;
  Stream<QuestionQueueUpdate> get questionQueueStream => _questionQueueController.stream;
  bool get isConnected => _isConnected;

  // Subscribed channels/threads
  final Set<String> _subscriptions = {};

  /// Connect to ActionCable
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      final token = await ApiClient.instance.getAuthToken();
      if (token == null) {
        _logger.warn('No auth token available, cannot connect to ActionCable');
        return;
      }

      // Build WebSocket URL
      final baseUrl = Env.apiBaseUrl.replaceFirst('http', 'ws');
      final wsUrl = '$baseUrl/cable?token=$token';

      _logger.info('Connecting to ActionCable: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);
      _startPingTimer();

      _logger.info('Connected to ActionCable');

      // Resubscribe to any previous channels
      for (final subscription in _subscriptions) {
        _sendSubscribe(subscription);
      }
    } catch (e) {
      _logger.error('Failed to connect to ActionCable: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect from ActionCable
  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionStateController.add(false);
    _logger.info('Disconnected from ActionCable');
  }

  /// Subscribe to a Hub thread for real-time messages
  void subscribeToThread(int threadId) {
    final identifier = _createIdentifier('HubChannel', {'thread_id': threadId});
    _subscriptions.add(identifier);

    if (_isConnected) {
      _sendSubscribe(identifier);
    }
  }

  /// Unsubscribe from a Hub thread
  void unsubscribeFromThread(int threadId) {
    final identifier = _createIdentifier('HubChannel', {'thread_id': threadId});
    _subscriptions.remove(identifier);

    if (_isConnected) {
      _sendUnsubscribe(identifier);
    }
  }

  /// Subscribe to entity-wide notifications
  void subscribeToNotifications(int entityId) {
    final identifier = _createIdentifier('NotificationChannel', {'entity_id': entityId});
    _subscriptions.add(identifier);

    if (_isConnected) {
      _sendSubscribe(identifier);
    }
  }

  /// Subscribe to job notifications (background task updates)
  void subscribeToJobNotifications() {
    final identifier = _createIdentifier('JobNotificationChannel', {});
    _subscriptions.add(identifier);

    if (_isConnected) {
      _sendSubscribe(identifier);
    }
    _logger.info('Subscribed to JobNotificationChannel');
  }

  /// Unsubscribe from job notifications
  void unsubscribeFromJobNotifications() {
    final identifier = _createIdentifier('JobNotificationChannel', {});
    _subscriptions.remove(identifier);

    if (_isConnected) {
      _sendUnsubscribe(identifier);
    }
  }

  /// Subscribe to question queue updates (agent questions)
  void subscribeToQuestionQueue(String sessionId) {
    final identifier = _createIdentifier('QuestionQueueChannel', {'session_id': sessionId});
    _subscriptions.add(identifier);

    if (_isConnected) {
      _sendSubscribe(identifier);
    }
    _logger.info('Subscribed to QuestionQueueChannel for session: $sessionId');
  }

  /// Unsubscribe from question queue
  void unsubscribeFromQuestionQueue(String sessionId) {
    final identifier = _createIdentifier('QuestionQueueChannel', {'session_id': sessionId});
    _subscriptions.remove(identifier);

    if (_isConnected) {
      _sendUnsubscribe(identifier);
    }
  }

  // Private methods

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String);

      // Handle ping/pong
      if (message['type'] == 'ping') {
        _sendPong();
        return;
      }

      // Handle welcome message
      if (message['type'] == 'welcome') {
        _logger.info('ActionCable welcomed us');
        return;
      }

      // Handle subscription confirmation
      if (message['type'] == 'confirm_subscription') {
        _logger.info('Subscription confirmed: ${message['identifier']}');
        return;
      }

      // Handle actual messages
      if (message['message'] != null) {
        final payload = message['message'];

        // Check message type
        if (payload['type'] == 'new_message') {
          final hubMessage = HubMessage.fromJson(payload['message']);
          _messageController.add(hubMessage);
          _logger.info('Received new message: ${hubMessage.id}');
        } else if (payload['type'] == 'job_update' ||
                   payload['type'] == 'job_complete' ||
                   payload['type'] == 'job_failed') {
          // Job notification from JobNotificationChannel
          final jobNotification = JobNotification.fromJson(payload);
          _jobNotificationController.add(jobNotification);
          _logger.info('Received job notification: ${payload['type']}');
        } else if (payload['action'] == 'added' ||
                   payload['action'] == 'answered' ||
                   payload['action'] == 'skipped' ||
                   payload['action'] == 'cancelled' ||
                   payload['action'] == 'completed') {
          // Question queue update
          final update = QuestionQueueUpdate.fromJson(payload);
          _questionQueueController.add(update);
          _logger.info('Received question queue update: ${payload['action']}');
        }
      }
    } catch (e) {
      _logger.error('Error handling ActionCable message: $e');
    }
  }

  void _handleError(dynamic error) {
    _logger.error('ActionCable error: $error');
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _connectionStateController.add(false);
    _pingTimer?.cancel();
    _logger.warn('ActionCable disconnected');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.error('Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay * (_reconnectAttempts + 1), () {
      _reconnectAttempts++;
      _logger.info('Attempting to reconnect (attempt $_reconnectAttempts)');
      connect();
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_isConnected) {
        _sendPing();
      }
    });
  }

  void _sendPing() {
    _send({'type': 'ping'});
  }

  void _sendPong() {
    _send({'type': 'pong'});
  }

  void _sendSubscribe(String identifier) {
    _send({
      'command': 'subscribe',
      'identifier': identifier,
    });
    _logger.info('Subscribed to: $identifier');
  }

  void _sendUnsubscribe(String identifier) {
    _send({
      'command': 'unsubscribe',
      'identifier': identifier,
    });
    _logger.info('Unsubscribed from: $identifier');
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  String _createIdentifier(String channel, Map<String, dynamic> params) {
    final data = {'channel': channel, ...params};
    return jsonEncode(data);
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStateController.close();
    _jobNotificationController.close();
    _questionQueueController.close();
  }
}

/// Question queue update from ActionCable
class QuestionQueueUpdate {
  final String action;
  final int? questionId;
  final Map<String, dynamic>? question;
  final Map<String, dynamic>? completion;
  final int? pendingCount;

  QuestionQueueUpdate({
    required this.action,
    this.questionId,
    this.question,
    this.completion,
    this.pendingCount,
  });

  factory QuestionQueueUpdate.fromJson(Map<String, dynamic> json) {
    return QuestionQueueUpdate(
      action: json['action'] ?? 'unknown',
      questionId: json['question_id'],
      question: json['question'] is Map<String, dynamic> ? json['question'] : null,
      completion: json['completion'] is Map<String, dynamic> ? json['completion'] : null,
      pendingCount: json['pending_count'],
    );
  }
}

/// Job notification from ActionCable
class JobNotification {
  final String type;
  final String? jobId;
  final String? jobType;
  final String? status;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  JobNotification({
    required this.type,
    this.jobId,
    this.jobType,
    this.status,
    this.message,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory JobNotification.fromJson(Map<String, dynamic> json) {
    return JobNotification(
      type: json['type'] ?? 'unknown',
      jobId: json['job_id']?.toString(),
      jobType: json['job_type'],
      status: json['status'],
      message: json['message'],
      data: json['data'] is Map<String, dynamic> ? json['data'] : null,
    );
  }

  bool get isComplete => type == 'job_complete';
  bool get isFailed => type == 'job_failed';
  bool get isUpdate => type == 'job_update';
}

/// Provider for ActionCable service (use with Riverpod)
/// Usage:
/// ```dart
/// final actionCable = ref.watch(actionCableProvider);
/// actionCable.subscribeToThread(threadId);
/// ```
