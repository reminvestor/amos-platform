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

  Stream<HubMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
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
  }
}

/// Provider for ActionCable service (use with Riverpod)
/// Usage:
/// ```dart
/// final actionCable = ref.watch(actionCableProvider);
/// actionCable.subscribeToThread(threadId);
/// ```
