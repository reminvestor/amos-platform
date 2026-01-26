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
  final int unreadDirectMessages;
  final List<HubMessage> recentMessages;
  final List<JobNotification> recentJobNotifications;

  const RealtimeState({
    this.isConnected = false,
    this.unreadTeamMessages = 0,
    this.unreadDirectMessages = 0,
    this.recentMessages = const [],
    this.recentJobNotifications = const [],
  });

  /// Total unread count across all message types
  int get totalUnreadCount => unreadTeamMessages + unreadDirectMessages;

  RealtimeState copyWith({
    bool? isConnected,
    int? unreadTeamMessages,
    int? unreadDirectMessages,
    List<HubMessage>? recentMessages,
    List<JobNotification>? recentJobNotifications,
  }) {
    return RealtimeState(
      isConnected: isConnected ?? this.isConnected,
      unreadTeamMessages: unreadTeamMessages ?? this.unreadTeamMessages,
      unreadDirectMessages: unreadDirectMessages ?? this.unreadDirectMessages,
      recentMessages: recentMessages ?? this.recentMessages,
      recentJobNotifications: recentJobNotifications ?? this.recentJobNotifications,
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
  StreamSubscription<JobNotification>? _jobNotificationSubscription;

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
      _jobNotificationSubscription?.cancel();
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
      if (connected) {
        // Auto-subscribe to job notifications when connected
        _actionCable.subscribeToJobNotifications();
        logger.AppLogger.info('Auto-subscribed to job notifications', tag: _tag);
      }
    });

    _messageSubscription = _actionCable.messageStream.listen(_handleIncomingMessage);
    _jobNotificationSubscription = _actionCable.jobNotificationStream.listen(_handleJobNotification);

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

  /// Clear unread team messages count
  void clearUnreadTeamMessages() {
    state = state.copyWith(unreadTeamMessages: 0);
  }

  /// Clear unread direct messages count
  void clearUnreadDirectMessages() {
    state = state.copyWith(unreadDirectMessages: 0);
  }

  /// Clear all unread counts
  void clearAllUnreadCounts() {
    state = state.copyWith(unreadTeamMessages: 0, unreadDirectMessages: 0);
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

    // Check if this is a DM or team message
    final isDm = message.channelId == null;

    // Increment unread count if not viewing the thread
    final shouldIncrement = (_currentScreen != 'team_chat' && _currentScreen != 'dm_chat') ||
        _currentThreadId != message.threadId;

    state = state.copyWith(
      recentMessages: updatedMessages,
      unreadTeamMessages: shouldIncrement && !isDm
          ? state.unreadTeamMessages + 1
          : state.unreadTeamMessages,
      unreadDirectMessages: shouldIncrement && isDm
          ? state.unreadDirectMessages + 1
          : state.unreadDirectMessages,
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

  void _handleJobNotification(JobNotification notification) {
    logger.AppLogger.info('Job notification: ${notification.type} - ${notification.message}', tag: _tag);

    // Add to recent notifications
    final updatedNotifications = [...state.recentJobNotifications, notification];
    if (updatedNotifications.length > 20) {
      updatedNotifications.removeRange(0, updatedNotifications.length - 20);
    }

    state = state.copyWith(recentJobNotifications: updatedNotifications);

    // Show push notification for completed/failed jobs
    if (notification.isComplete || notification.isFailed) {
      _pushNotifications.showJobNotification(
        title: notification.isComplete ? 'Task Complete' : 'Task Failed',
        message: notification.message ?? 'A background task has finished.',
        jobType: notification.jobType,
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

/// Convenience provider for unread direct messages
final unreadDirectMessagesProvider = Provider<int>((ref) {
  return ref.watch(realtimeProvider).unreadDirectMessages;
});

/// Convenience provider for total unread count
final totalUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(realtimeProvider).totalUnreadCount;
});
