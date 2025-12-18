import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/hub_service.dart';
import 'package:amos_mobile/services/action_cable_service.dart';
import 'package:amos_mobile/services/push_notification_service.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

/// Team chat screen for channel or DM messaging
class TeamChatScreen extends ConsumerStatefulWidget {
  final String? channelId;
  final String? threadId;
  final String? title;

  const TeamChatScreen({
    super.key,
    this.channelId,
    this.threadId,
    this.title,
  });

  @override
  ConsumerState<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends ConsumerState<TeamChatScreen> {
  final HubService _hubService = HubService();
  final ActionCableService _actionCable = ActionCableService();
  final PushNotificationService _pushNotifications = PushNotificationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<HubMessage> _messages = [];
  TeamChannel? _channel;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  int? _currentThreadId;
  bool _isScreenActive = true;

  Timer? _pollTimer;
  StreamSubscription<HubMessage>? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _initializePushNotifications();
    _loadMessages();
    _setupActionCable();
    // Fallback polling in case WebSocket disconnects
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_actionCable.isConnected) {
        _pollNewMessages();
      }
    });
  }

  @override
  void dispose() {
    _isScreenActive = false;
    _messageController.dispose();
    _scrollController.dispose();
    _pollTimer?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    // Unsubscribe from thread when leaving screen
    if (_currentThreadId != null) {
      _actionCable.unsubscribeFromThread(_currentThreadId!);
    }
    super.dispose();
  }

  Future<void> _initializePushNotifications() async {
    await _pushNotifications.initialize();
    await _pushNotifications.requestPermissions();
  }

  void _setupActionCable() {
    // Connect to ActionCable
    _actionCable.connect();

    // Listen for new messages
    _messageSubscription = _actionCable.messageStream.listen((message) {
      if (!mounted) return;

      // Only add if message is for our thread
      if (_currentThreadId != null) {
        // Check if we already have this message
        if (!_messages.any((m) => m.id == message.id)) {
          setState(() {
            _messages.add(message);
          });
          _scrollToBottom();

          // Show notification if screen is not active
          if (!_isScreenActive) {
            _showNotificationForMessage(message);
          }
        }
      }
    });

    // Listen for connection state changes
    _connectionSubscription = _actionCable.connectionStateStream.listen((connected) {
      if (!mounted) return;
      if (connected && _currentThreadId != null) {
        // Resubscribe when reconnected
        _actionCable.subscribeToThread(_currentThreadId!);
      }
    });
  }

  void _showNotificationForMessage(HubMessage message) {
    final authState = ref.read(authStateProvider);
    final currentUserId = authState.user?.id;

    // Don't show notification for own messages
    if (message.senderId == currentUserId) return;

    if (widget.channelId != null && _channel != null) {
      _pushNotifications.showTeamMessageNotification(
        messageId: message.id,
        channelName: _channel!.name,
        senderName: message.senderName,
        message: message.content,
        threadId: _currentThreadId,
        channelId: int.tryParse(widget.channelId!),
      );
    } else {
      _pushNotifications.showDirectMessageNotification(
        messageId: message.id,
        senderName: message.senderName,
        message: message.content,
        threadId: _currentThreadId!,
        isFromAgent: message.isFromAgent,
      );
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.channelId != null) {
        final response = await _hubService.getChannelMessages(
          int.parse(widget.channelId!),
        );
        setState(() {
          _channel = response.channel;
          _currentThreadId = response.threadId;
          _messages = response.messages;
          _isLoading = false;
        });
        // Subscribe to thread for real-time updates
        _actionCable.subscribeToThread(response.threadId);
      } else if (widget.threadId != null) {
        final response = await _hubService.getThreadMessages(
          int.parse(widget.threadId!),
        );
        setState(() {
          _currentThreadId = response.thread.id;
          _messages = response.messages;
          _isLoading = false;
        });
        // Subscribe to thread for real-time updates
        _actionCable.subscribeToThread(response.thread.id);
      }

      _scrollToBottom();

      // Mark thread as read
      if (_currentThreadId != null) {
        _hubService.markThreadRead(_currentThreadId!);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pollNewMessages() async {
    if (_currentThreadId == null || _isSending) return;

    try {
      if (widget.channelId != null) {
        final response = await _hubService.getChannelMessages(
          int.parse(widget.channelId!),
        );
        if (mounted && response.messages.length != _messages.length) {
          setState(() {
            _messages = response.messages;
          });
          _scrollToBottom();
        }
      } else if (widget.threadId != null) {
        final response = await _hubService.getThreadMessages(
          int.parse(widget.threadId!),
        );
        if (mounted && response.messages.length != _messages.length) {
          setState(() {
            _messages = response.messages;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      // Silently fail on poll errors
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);

    try {
      HubMessage message;

      if (widget.channelId != null) {
        message = await _hubService.sendChannelMessage(
          int.parse(widget.channelId!),
          content,
        );
      } else if (_currentThreadId != null) {
        message = await _hubService.sendThreadMessage(
          _currentThreadId!,
          content,
        );
      } else {
        throw Exception('No channel or thread specified');
      }

      setState(() {
        _messages.add(message);
        _isSending = false;
      });
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.user?.id;

    String title = widget.title ?? _channel?.name ?? 'Chat';
    if (_channel != null) {
      title = '# ${_channel!.name}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            if (_channel?.description != null)
              Text(
                _channel!.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.info),
            onPressed: () => _showChannelInfo(context),
            tooltip: 'Channel info',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessageList(currentUserId),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageList(String? currentUserId) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loadMessages,
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
            Icon(
              LucideIcons.messageSquare,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Start the conversation!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    // Parse currentUserId to int for comparison
    final currentUserIdInt = currentUserId != null ? int.tryParse(currentUserId) : null;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isOwnMessage = message.senderId == currentUserIdInt;
        final showAvatar = index == 0 ||
            _messages[index - 1].senderId != message.senderId ||
            message.createdAt.difference(_messages[index - 1].createdAt).inMinutes > 5;

        return _MessageBubble(
          message: message,
          isOwnMessage: isOwnMessage,
          showAvatar: showAvatar,
          onReact: (emoji) => _handleReaction(message.id, emoji),
        );
      },
    );
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () {},
            tooltip: 'Attach',
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.send),
            onPressed: _isSending ? null : _sendMessage,
          ),
        ],
      ),
    );
  }

  void _handleReaction(int messageId, String emoji) async {
    try {
      await _hubService.addReaction(messageId, emoji);
      // Refresh messages to show reaction
      _pollNewMessages();
    } catch (e) {
      // Silently fail reactions
    }
  }

  void _showChannelInfo(BuildContext context) {
    if (_channel == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _channel!.displayIcon,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '# ${_channel!.name}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_channel!.isPrivate)
                          Row(
                            children: [
                              Icon(
                                LucideIcons.lock,
                                size: 14,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Private channel',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_channel!.description != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(_channel!.description!),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  _InfoChip(
                    icon: LucideIcons.users,
                    label: '${_channel!.memberCount} members',
                  ),
                  const SizedBox(width: 16),
                  _InfoChip(
                    icon: LucideIcons.bot,
                    label: '${_channel!.agentCount} agents',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final HubMessage message;
  final bool isOwnMessage;
  final bool showAvatar;
  final Function(String) onReact;

  const _MessageBubble({
    required this.message,
    required this.isOwnMessage,
    required this.showAvatar,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        top: showAvatar ? 12 : 2,
        bottom: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isOwnMessage) ...[
            if (showAvatar)
              CircleAvatar(
                radius: 16,
                backgroundColor: message.isFromAgent
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.primaryContainer,
                child: Text(
                  message.senderName.isNotEmpty
                      ? message.senderName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 12,
                    color: message.isFromAgent
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: isOwnMessage
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showAvatar && !isOwnMessage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          message.senderName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (message.isFromAgent) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'AI',
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(message.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                GestureDetector(
                  onLongPress: () => _showReactionPicker(context),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isOwnMessage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomLeft: isOwnMessage
                            ? const Radius.circular(16)
                            : const Radius.circular(4),
                        bottomRight: isOwnMessage
                            ? const Radius.circular(4)
                            : const Radius.circular(16),
                      ),
                    ),
                    child: message.isGif
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              message.content,
                              width: 200,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const SizedBox(
                                  width: 200,
                                  height: 150,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              },
                            ),
                          )
                        : Text(
                            message.content,
                            style: TextStyle(
                              color: isOwnMessage
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                  ),
                ),
                if (message.reactions != null &&
                    message.reactions!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: message.reactions!.entries.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          if (isOwnMessage) ...[
            const SizedBox(width: 8),
            if (showAvatar)
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primary,
                child: const Icon(
                  LucideIcons.user,
                  size: 16,
                  color: Colors.white,
                ),
              )
            else
              const SizedBox(width: 32),
          ],
        ],
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add reaction',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['👍', '❤️', '😄', '🎉', '🤔', '😢', '🔥', '👏']
                    .map((emoji) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onReact(emoji);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
