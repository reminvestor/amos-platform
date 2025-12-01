import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/services/chat_service.dart';
import 'package:amos_mobile/services/file_upload_service.dart';
import 'package:amos_mobile/widgets/model_selector.dart';
import 'package:amos_mobile/widgets/file_attachment_chip.dart';
import 'package:amos_mobile/widgets/voice_input_button.dart';
import 'package:amos_mobile/utils/logger.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _chatService = ChatService();
  final _fileUploadService = FileUploadService();

  bool _isUploading = false;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    final existingSession = ref.read(chatSessionProvider);
    if (existingSession == null) {
      final sessionId = await _chatService.createNewSession();
      ref.read(chatSessionProvider.notifier).setSession(sessionId);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _startNewChat() async {
    // Clear messages
    ref.read(chatMessagesProvider.notifier).clear();
    ref.read(attachedFilesProvider.notifier).clear();
    ref.read(chatStatusProvider.notifier).clear();

    // Create new session
    final sessionId = await _chatService.createNewSession();
    ref.read(chatSessionProvider.notifier).setSession(sessionId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Started new conversation'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickAndUploadFiles() async {
    final files = await _fileUploadService.pickFiles();
    if (files == null || files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final uploaded = await _fileUploadService.uploadFiles(
        files,
        onProgress: (sent, total) {
          setState(() => _uploadProgress = sent / total);
        },
      );

      ref.read(attachedFilesProvider.notifier).addFiles(uploaded);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploaded ${uploaded.length} file(s)'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0;
      });
    }
  }

  Future<void> _sendMessage({String? voiceText}) async {
    final text = voiceText ?? _textController.text.trim();
    if (text.isEmpty) return;

    final sessionId = ref.read(chatSessionProvider);
    final selectedModel = ref.read(selectedModelProvider);
    final attachedFiles = ref.read(attachedFilesProvider);

    // Add user message
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );

    ref.read(chatMessagesProvider.notifier).addMessage(userMessage);
    _textController.clear();
    ref.read(attachedFilesProvider.notifier).clear();

    // Scroll to bottom
    _scrollToBottom();

    // Set loading
    ref.read(chatLoadingProvider.notifier).setLoading(true);

    try {
      // Create assistant message with initial content
      final assistantMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
      );

      // Add the message immediately
      ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

      // Stream the response from Scout
      final responseBuffer = StringBuffer();

      await for (final event in _chatService.sendMessage(
        text,
        sessionId: sessionId,
        model: selectedModel,
        files: attachedFiles.isNotEmpty ? attachedFiles : null,
      )) {
        switch (event.type) {
          case ChatStreamEventType.content:
            responseBuffer.write(event.content);
            final updatedMessage = ChatMessage(
              id: assistantMessage.id,
              role: MessageRole.assistant,
              content: responseBuffer.toString(),
              timestamp: assistantMessage.timestamp,
            );
            ref.read(chatMessagesProvider.notifier).updateMessage(updatedMessage);
            _scrollToBottom();
            break;

          case ChatStreamEventType.status:
            ref.read(chatStatusProvider.notifier).setStatus(event.content);
            break;

          case ChatStreamEventType.toolStart:
            ref.read(chatStatusProvider.notifier).setStatus(
                  'Running ${event.toolName}...',
                );
            break;

          case ChatStreamEventType.toolEnd:
            ref.read(chatStatusProvider.notifier).clear();
            break;

          case ChatStreamEventType.error:
            throw Exception(event.content);

          case ChatStreamEventType.canvas:
            // Handle canvas events (landing page editor, etc.)
            AppLogger.info('Canvas event: ${event.canvasType}');
            break;
        }
      }

      AppLogger.info('Chat response completed');
      ref.read(chatStatusProvider.notifier).clear();

    } catch (e) {
      AppLogger.error('Chat error', error: e);

      // Add error message
      final errorMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        content: 'Sorry, I encountered an error: ${e.toString()}\n\nPlease try again.',
        timestamp: DateTime.now(),
      );

      ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
    } finally {
      ref.read(chatLoadingProvider.notifier).setLoading(false);
      ref.read(chatStatusProvider.notifier).clear();
      _scrollToBottom();
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
    final messages = ref.watch(chatMessagesProvider);
    final isLoading = ref.watch(chatLoadingProvider);
    final status = ref.watch(chatStatusProvider);
    final attachedFiles = ref.watch(attachedFilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                LucideIcons.bot,
                color: context.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('AMOS Assistant'),
          ],
        ),
        actions: [
          // Tasks button
          IconButton(
            icon: const Icon(LucideIcons.listTodo),
            onPressed: () => context.push('/tasks'),
            tooltip: 'View Tasks',
          ),
          // New chat button
          IconButton(
            icon: const Icon(LucideIcons.circlePlus),
            onPressed: _startNewChat,
            tooltip: 'New Chat',
          ),
          // Clear button
          IconButton(
            icon: const Icon(LucideIcons.trash2),
            onPressed: () {
              ref.read(chatMessagesProvider.notifier).clear();
              ref.read(attachedFilesProvider.notifier).clear();
            },
            tooltip: 'Clear messages',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status indicator
          if (status != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: context.primaryColor.withOpacity(0.1),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.primaryColor,
                        ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + (isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length && isLoading) {
                        return _buildTypingIndicator();
                      }
                      return _MessageBubble(message: messages[index]);
                    },
                  ),
          ),

          // Attached files
          if (attachedFiles.isNotEmpty)
            FileAttachmentList(
              files: attachedFiles,
              onRemove: (assetId) {
                ref.read(attachedFilesProvider.notifier).removeFile(assetId);
              },
            ),

          // Upload progress
          if (_isUploading)
            LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: context.borderColor,
              color: context.primaryColor,
            ),

          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                LucideIcons.messageSquare,
                size: 48,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Start a conversation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask AMOS to help you with marketing tasks, content creation, and more.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                  label: 'Create a campaign',
                  onTap: () {
                    _textController.text = 'Help me create an email campaign';
                    _sendMessage();
                  },
                ),
                _SuggestionChip(
                  label: 'Build a landing page',
                  onTap: () {
                    _textController.text =
                        'Help me build a landing page for my product';
                    _sendMessage();
                  },
                ),
                _SuggestionChip(
                  label: 'Analyze my contacts',
                  onTap: () {
                    _textController.text =
                        'Analyze my contact list and suggest improvements';
                    _sendMessage();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TypingDot(delay: 0),
                const SizedBox(width: 4),
                _TypingDot(delay: 150),
                const SizedBox(width: 4),
                _TypingDot(delay: 300),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(
          top: BorderSide(color: context.borderColor),
        ),
      ),
      child: Row(
        children: [
          // Model selector (brain icon)
          const ModelSelector(),
          const SizedBox(width: 4),

          // File attachment button
          IconButton(
            onPressed: _isUploading ? null : _pickAndUploadFiles,
            icon: _isUploading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.primaryColor,
                    ),
                  )
                : const Icon(LucideIcons.paperclip),
            tooltip: 'Attach files',
          ),

          // Voice input button
          VoiceInputButton(
            onTranscript: (transcript) {
              _sendMessage(voiceText: transcript);
            },
          ),

          const SizedBox(width: 8),

          // Text input
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: context.backgroundColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          IconButton.filled(
            onPressed: () => _sendMessage(),
            icon: const Icon(LucideIcons.send, size: 20),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                LucideIcons.bot,
                size: 16,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? context.primaryColor : context.surfaceColor,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? Radius.zero : null,
                  bottomLeft: !isUser ? Radius.zero : null,
                ),
              ),
              child: SelectableText(
                message.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isUser ? Colors.white : null,
                    ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int delay;

  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: context.textTertiary.withOpacity(0.5 + _animation.value * 0.5),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
