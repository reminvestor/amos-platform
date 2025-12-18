import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/services/action_cable_service.dart';
import 'package:amos_mobile/services/push_notification_service.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/utils/logger.dart' as logger;

/// State for real-time messaging
class RealtimeState {
  final bool isConnected;
  final int unreadTeamMessages;
  final List<HubMessage> recentMessages;

  const RealtimeState({
    this.isConnected = false,
    this.unreadTeamMessages = 0,
    this.recentMessages = const [],
  });

  RealtimeState copyWith({
    bool? isConnected,
    int? unreadTeamMessages,
    List<HubMessage>? recentMessages,
  }) {
    return RealtimeState(
      isConnected: isConnected ?? this.isConnected,
      unreadTeamMessages: unreadTeamMessages ?? this.unreadTeamMessages,
      recentMessages: recentMessages ?? this.recentMessages,
    );
  }
}

/// Notifier for real-time messaging state
class RealtimeNotifier extends Notifier<RealtimeState> {
  static const String _tag = 'RealtimeNotifier';
  final ActionCableService _actionCable = ActionCableService();
  final PushNotificationService _pushNotifications = PushNotificationService();

  StreamSubscription<HubMessage>? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  // Current screen tracking for notification decisions
  String? _currentScreen;
  int? _currentThreadId;

  @override
  RealtimeState build() {
    // Initialize services
    _initialize();

    // Listen for auth state changes to auto-connect/disconnect
    ref.listen(authStateProvider, (previous, next) {
      if (next.isAuthenticated && !previous!.isAuthenticated) {
        // Just logged in - connect
        connect();
      } else if (!next.isAuthenticated && previous!.isAuthenticated) {
        // Just logged out - disconnect
        disconnect();
      }
    });

    // Clean up on dispose
    ref.onDispose(() {
      _messageSubscription?.cancel();
      _connectionSubscription?.cancel();
    });

    return const RealtimeState();
  }

  Future<void> _initialize() async {
    // Initialize push notifications
    await _pushNotifications.initialize();
    await _pushNotifications.requestPermissions();

    // Set up ActionCable listeners
    _connectionSubscription = _actionCable.connectionStateStream.listen((connected) {
      state = state.copyWith(isConnected: connected);
    });

    _messageSubscription = _actionCable.messageStream.listen(_handleIncomingMessage);

    // Connect if already authenticated
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      connect();
    }
  }

  /// Connect to ActionCable (call after login)
  Future<void> connect() async {
    await _actionCable.connect();
  }

  /// Disconnect from ActionCable (call on logout)
  void disconnect() {
    _actionCable.disconnect();
    state = const RealtimeState();
  }

  /// Subscribe to a thread for real-time updates
  void subscribeToThread(int threadId) {
    _actionCable.subscribeToThread(threadId);
  }

  /// Unsubscribe from a thread
  void unsubscribeFromThread(int threadId) {
    _actionCable.unsubscribeFromThread(threadId);
  }

  /// Set the current screen for notification filtering
  void setCurrentScreen(String screen, {int? threadId}) {
    _currentScreen = screen;
    _currentThreadId = threadId;
  }

  /// Clear unread count
  void clearUnreadMessages() {
    state = state.copyWith(unreadTeamMessages: 0);
  }

  void _handleIncomingMessage(HubMessage message) {
    final authState = ref.read(authStateProvider);
    final currentUserIdStr = authState.user?.id;
    final currentUserId = currentUserIdStr != null ? int.tryParse(currentUserIdStr) : null;

    // Don't process own messages
    if (currentUserId != null && message.senderId == currentUserId) return;

    // Add to recent messages
    final updatedMessages = [...state.recentMessages, message];
    if (updatedMessages.length > 50) {
      updatedMessages.removeRange(0, updatedMessages.length - 50);
    }

    // Increment unread count if not viewing the thread
    final shouldIncrement = _currentScreen != 'team_chat' ||
        _currentThreadId != message.threadId;

    state = state.copyWith(
      recentMessages: updatedMessages,
      unreadTeamMessages: shouldIncrement
          ? state.unreadTeamMessages + 1
          : state.unreadTeamMessages,
    );

    // Show notification if not viewing this thread
    if (shouldIncrement) {
      _showNotification(message);
    }

    logger.AppLogger.info('Received message from ${message.senderName}: ${message.content.substring(0, message.content.length.clamp(0, 50))}', tag: _tag);
  }

  void _showNotification(HubMessage message) {
    // Use the message type to determine notification style
    if (message.channelId != null) {
      _pushNotifications.showTeamMessageNotification(
        messageId: message.id,
        channelName: 'Team', // Would need channel name from context
        senderName: message.senderName,
        message: message.content,
        threadId: message.threadId,
        channelId: message.channelId,
      );
    } else {
      _pushNotifications.showDirectMessageNotification(
        messageId: message.id,
        senderName: message.senderName,
        message: message.content,
        threadId: message.threadId ?? 0,
        isFromAgent: message.isFromAgent,
      );
    }
  }
}

/// Provider for real-time messaging state
final realtimeProvider = NotifierProvider<RealtimeNotifier, RealtimeState>(() {
  return RealtimeNotifier();
});

/// Convenience provider for connection status
final isRealtimeConnectedProvider = Provider<bool>((ref) {
  return ref.watch(realtimeProvider).isConnected;
});

/// Convenience provider for unread team messages
final unreadTeamMessagesProvider = Provider<int>((ref) {
  return ref.watch(realtimeProvider).unreadTeamMessages;
});
