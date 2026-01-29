import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/services/hub_service.dart';
import 'package:amos_mobile/services/dictation_service.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/utils/error_handler.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:amos_mobile/services/notification_sound_service.dart';

/// Direct message chat screen - iMessage-like experience
class DmChatScreen extends ConsumerStatefulWidget {
  final int threadId;
  final String? participantName;

  const DmChatScreen({
    super.key,
    required this.threadId,
    this.participantName,
  });

  @override
  ConsumerState<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends ConsumerState<DmChatScreen>
    with ErrorHandler, SingleTickerProviderStateMixin {
  final HubService _hubService = HubService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  List<HubMessage> _messages = [];
  HubThread? _thread;
  List<HubParticipant> _participants = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  int? _currentUserId;

  // Dictation support
  DictationService? _dictationService;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<DictationState>? _dictationStateSubscription;
  StreamSubscription<String>? _interimSubscription;
  DictationState _dictationState = DictationState.idle;
  String _interimText = '';

  // Store ref to the notifier for safe cleanup in dispose
  RealtimeNotifier? _realtimeNotifier;

  @override
  void initState() {
    super.initState();
    _loadThread();
    // Capture notifier reference for safe dispose cleanup
    _realtimeNotifier = ref.read(realtimeProvider.notifier);
    // Tell realtime provider we're viewing this thread (for notification filtering)
    _realtimeNotifier?.setCurrentScreen('dm_chat', threadId: widget.threadId);
    // Subscribe to real-time updates
    _realtimeNotifier?.subscribeToThread(widget.threadId);
    // Initialize notification sound
    NotificationSoundService.instance.initialize();

    // Initialize dictation
    _initDictation();
  }

  void _initDictation() {
    _dictationService = DictationService(textController: _messageController);

    // Setup pulse animation for listening state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to dictation state changes
    _dictationStateSubscription =
        _dictationService!.stateStream.listen((state) {
      if (mounted) {
        setState(() => _dictationState = state);
        if (state == DictationState.listening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });

    // Listen to interim text changes
    _interimSubscription = _dictationService!.interimTextStream.listen((text) {
      if (mounted) {
        setState(() => _interimText = text);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    // Clean up dictation
    _pulseController.dispose();
    _dictationStateSubscription?.cancel();
    _interimSubscription?.cancel();
    _dictationService?.dispose();
    // Unsubscribe from thread using stored notifier reference (safe in dispose)
    _realtimeNotifier?.unsubscribeFromThread(widget.threadId);
    _realtimeNotifier?.setCurrentScreen('');
    super.dispose();
  }

  Future<void> _loadThread() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get current user ID
      final authState = ref.read(authStateProvider);
      final userIdStr = authState.user?.id;
      _currentUserId = userIdStr != null ? int.tryParse(userIdStr) : null;

      // Load thread messages
      final response = await _hubService.getThreadMessages(widget.threadId);

      if (mounted) {
        setState(() {
          _thread = response.thread;
          _messages = response.messages;
          _participants = response.participants;
          _isLoading = false;
        });

        // Mark thread as read - iMessage style
        _markAsRead();

        // Scroll to bottom
        _scrollToBottom();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load DM thread', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead() async {
    try {
      // Mark the last message as read
      if (_messages.isNotEmpty) {
        await _hubService.markThreadRead(widget.threadId, messageId: _messages.last.id);
        AppLogger.info('Marked thread ${widget.threadId} as read');
      }
    } catch (e) {
      // Silently fail - not critical
      AppLogger.warning('Failed to mark thread as read: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleDictation() async {
    try {
      await _dictationService?.toggle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dictation error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      // Debug: Check auth token before sending
      final token = await ApiClient.instance.getAuthToken();
      AppLogger.info('Sending message - auth token: ${token != null ? "present (${token.substring(0, 8)}...)" : "MISSING!"}');
      if (token == null) {
        throw Exception('Not authenticated - please log in again');
      }

      final message = await _hubService.sendThreadMessage(widget.threadId, text);

      if (mounted) {
        setState(() {
          _messages.add(message);
          _isSending = false;
        });
        _messageController.clear();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        showError(context, e);
      }
    }
  }

  String get _displayName {
    if (widget.participantName != null) return widget.participantName!;
    if (_thread != null) return _thread!.displayName;

    // Find the other participant
    final otherParticipant = _participants.firstWhere(
      (p) => p.participantId != _currentUserId,
      orElse: () => _participants.isNotEmpty ? _participants.first : HubParticipant(
        id: 0, participantType: 'User', participantId: 0, name: 'Chat',
      ),
    );
    return otherParticipant.name ?? 'Chat';
  }

  @override
  Widget build(BuildContext context) {
    // Listen to realtime messages for this thread
    ref.listen(realtimeProvider, (previous, next) {
      // Check for new messages in this thread
      if (next.recentMessages.length > (previous?.recentMessages.length ?? 0)) {
        final newMessage = next.recentMessages.last;
        if (newMessage.threadId == widget.threadId) {
          // Add the new message if not already present
          if (!_messages.any((m) => m.id == newMessage.id)) {
            setState(() {
              _messages.add(newMessage);
            });
            _scrollToBottom();
            // Mark as read since we're viewing it
            _markAsRead();
            // Play notification sound for incoming messages (not from me)
            if (newMessage.senderId != _currentUserId) {
              NotificationSoundService.instance.playMessageSound();
            }
          }
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (_participants.isNotEmpty)
                    Text(
                      _participants.any((p) => p.isAgent) ? 'AI Agent' : 'Team Member',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final otherParticipant = _participants.firstWhere(
      (p) => p.participantId != _currentUserId,
      orElse: () => _participants.isNotEmpty ? _participants.first : HubParticipant(
        id: 0, participantType: 'User', participantId: 0, name: 'U',
      ),
    );

    final isAgent = otherParticipant.isAgent;
    final initial = (otherParticipant.name?.isNotEmpty ?? false)
        ? otherParticipant.name![0].toUpperCase()
        : 'U';

    return CircleAvatar(
      radius: 18,
      backgroundColor: isAgent ? Colors.purple.shade100 : Colors.blue.shade100,
      child: isAgent
          ? Icon(LucideIcons.bot, size: 18, color: Colors.purple.shade700)
          : Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text('Failed to load messages'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadThread,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.messageSquare, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Start the conversation!',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == _currentUserId;
        final showAvatar = !isMe && (index == 0 || _messages[index - 1].senderId != message.senderId);

        return _MessageBubble(
          message: message,
          isMe: isMe,
          showAvatar: showAvatar,
        );
      },
    );
  }

  Widget _buildInputBar() {
    final theme = Theme.of(context);
    final isListening = _dictationState == DictationState.listening;
    final isInitializing = _dictationState == DictationState.initializing;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show interim text when dictating
          if (isListening && _interimText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.mic,
                    size: 12,
                    color: Colors.red.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _interimText,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    border: isListening
                        ? Border.all(
                            color: Colors.red.withValues(alpha: 0.5), width: 2)
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _inputFocusNode,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Message...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      // Mic button inside the text field
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: isListening ? _pulseAnimation.value : 1.0,
                            child: IconButton(
                              onPressed: isInitializing ? null : _toggleDictation,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              icon: isInitializing
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      isListening
                                          ? LucideIcons.micOff
                                          : LucideIcons.mic,
                                      size: 20,
                                      color: isListening
                                          ? Colors.red
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                              tooltip: isListening
                                  ? 'Stop dictation'
                                  : 'Start dictation',
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.send, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Message bubble widget - iMessage style
class _MessageBubble extends StatelessWidget {
  final HubMessage message;
  final bool isMe;
  final bool showAvatar;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (showAvatar)
              CircleAvatar(
                radius: 14,
                backgroundColor: message.isFromAgent ? Colors.purple.shade100 : Colors.blue.shade100,
                child: message.isFromAgent
                    ? Icon(LucideIcons.bot, size: 14, color: Colors.purple.shade700)
                    : Text(
                        message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : 'U',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                      ),
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white70 : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white60 : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    // Convert to 12-hour format with AM/PM
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final time = '$hour12:$minute $period';

    if (messageDate == today) {
      return time;
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $time';
    } else {
      return '${dateTime.month}/${dateTime.day} $time';
    }
  }
}
