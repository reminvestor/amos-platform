import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/models/agent_question.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/services/chat_service.dart';
import 'package:amos_mobile/services/file_upload_service.dart';
import 'package:amos_mobile/services/dictation_service.dart';
import 'package:amos_mobile/widgets/file_attachment_chip.dart';
import 'package:amos_mobile/widgets/question_queue.dart';
import 'package:amos_mobile/widgets/thinking_indicator.dart';
import 'package:amos_mobile/widgets/canvas/canvas_overlay.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:amos_mobile/genui/genui_renderer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? initialPrompt;

  const ChatScreen({super.key, this.initialPrompt});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _chatService = ChatService();
  final _fileUploadService = FileUploadService();
  final _questionQueueKey = GlobalKey<QuestionQueueWidgetState>();

  bool _isUploading = false;
  double _uploadProgress = 0;

  bool _initialPromptSent = false;

  // Thinking indicator state
  List<String> _toolSteps = [];
  bool _isThinking = false;

  // Dictation support
  DictationService? _dictationService;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<DictationState>? _dictationStateSubscription;
  StreamSubscription<String>? _interimSubscription;
  DictationState _dictationState = DictationState.idle;
  String _interimText = '';

  @override
  void initState() {
    super.initState();
    _initSession();
    _initDictation();
  }

  void _initDictation() {
    _dictationService = DictationService(textController: _textController);

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

  Future<void> _initSession() async {
    final existingSession = ref.read(chatSessionProvider);
    if (existingSession == null) {
      final sessionId = await _chatService.createNewSession();
      ref.read(chatSessionProvider.notifier).setSession(sessionId);
    }

    // Send initial prompt if provided (after session is ready)
    if (widget.initialPrompt != null && !_initialPromptSent) {
      _initialPromptSent = true;
      // Use addPostFrameCallback to ensure the widget is fully built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(voiceText: widget.initialPrompt);
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    // Clean up dictation
    _pulseController.dispose();
    _dictationStateSubscription?.cancel();
    _interimSubscription?.cancel();
    _dictationService?.dispose();
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

    // Set loading and start thinking
    ref.read(chatLoadingProvider.notifier).setLoading(true);
    setState(() {
      _isThinking = true;
      _toolSteps = [];
    });

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

      // Stream the response from Amos
      final responseBuffer = StringBuffer();

      await for (final event in _chatService.sendMessage(
        text,
        sessionId: sessionId,
        model: selectedModel,
        files: attachedFiles.isNotEmpty ? attachedFiles : null,
      )) {
        switch (event.type) {
          case ChatStreamEventType.content:
            // Hide thinking indicator when actual content starts streaming
            if (_isThinking && mounted) {
              setState(() => _isThinking = false);
            }
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
            // Add tool to thinking steps
            final friendlyName = formatToolName(event.toolName ?? 'working');
            if (mounted) {
              setState(() {
                _toolSteps = [..._toolSteps, friendlyName];
                // Keep only last 5 steps
                if (_toolSteps.length > 5) {
                  _toolSteps = _toolSteps.sublist(_toolSteps.length - 5);
                }
              });
            }
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
            _showCanvas(event.canvasType ?? 'unknown', event.data);
            break;

          case ChatStreamEventType.question:
            // Add question to the queue
            if (event.data != null) {
              final question = AgentQuestion.fromJson(event.data as Map<String, dynamic>);
              _questionQueueKey.currentState?.addQuestion(question);
            }
            break;

          case ChatStreamEventType.completion:
            // Add completion notification to the queue
            if (event.data != null) {
              final completion = AgentCompletion.fromJson(event.data as Map<String, dynamic>);
              _questionQueueKey.currentState?.addCompletion(completion);
            }
            break;

          case ChatStreamEventType.cancelled:
            // User cancelled the request - update last message to show it was stopped
            final messages = ref.read(chatMessagesProvider);
            if (messages.isNotEmpty) {
              final lastMsg = messages.last;
              if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
                final stoppedMessage = ChatMessage(
                  id: lastMsg.id,
                  role: MessageRole.assistant,
                  content: '${lastMsg.content}\n\n_[stopped]_',
                  timestamp: lastMsg.timestamp,
                );
                ref.read(chatMessagesProvider.notifier).updateMessage(stoppedMessage);
              }
            }
            return; // Exit the stream loop
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
      if (mounted) {
        setState(() {
          _isThinking = false;
          _toolSteps = [];
        });
      }
      _scrollToBottom();
    }
  }

  /// Stop the current streaming response
  void _stopStreaming() {
    AppLogger.info('Stop button pressed - cancelling stream');
    _chatService.cancelCurrentRequest();

    // Immediately update UI state
    ref.read(chatLoadingProvider.notifier).setLoading(false);
    if (mounted) {
      setState(() {
        _isThinking = false;
        _toolSteps = [];
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // With reverse: true, bottom is at position 0
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Show a canvas overlay when receiving a canvas event from Amos
  void _showCanvas(String canvasType, dynamic canvasData) {
    // Update canvas state
    ref.read(currentCanvasProvider.notifier).showCanvas(canvasType, canvasData);
    ref.read(canvasVisibleProvider.notifier).show();

    AppLogger.info('Showing canvas: $canvasType');
  }

  /// Close the current canvas overlay
  void _closeCanvas() {
    ref.read(canvasVisibleProvider.notifier).hide();
    ref.read(currentCanvasProvider.notifier).closeCanvas();
    ref.read(canvasHistoryProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final isLoading = ref.watch(chatLoadingProvider);
    final status = ref.watch(chatStatusProvider);
    final attachedFiles = ref.watch(attachedFilesProvider);
    final isCanvasVisible = ref.watch(canvasVisibleProvider);

    final sessionId = ref.watch(chatSessionProvider) ?? '';

    // Show canvas overlay when active
    if (isCanvasVisible) {
      return const CanvasOverlay();
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset(
          'assets/images/logo-header.png',
          height: 28,
          fit: BoxFit.contain,
        ),
        actions: [
          // New chat button
          _ActionButton(
            icon: LucideIcons.circlePlus,
            onTap: _startNewChat,
            tooltip: 'New Chat',
          ),
          const SizedBox(width: 4),
          // Settings button
          _ActionButton(
            icon: LucideIcons.settings,
            onTap: () => context.goNamed('settings'),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Main chat content
          Column(
            children: [
              // Thinking indicator (replaces old status bar)
              ThinkingIndicator(
                isVisible: _isThinking && isLoading,
                steps: _toolSteps,
                currentStatus: status,
              ),

              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length + (isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          // With reverse: true, index 0 is at bottom
                          // Show typing indicator at index 0 (bottom) when loading
                          if (index == 0 && isLoading) {
                            return _buildTypingIndicator();
                          }
                          // Adjust index for typing indicator
                          final messageIndex = isLoading ? index - 1 : index;
                          // Reverse the message index so newest is at bottom
                          final reversedIndex = messages.length - 1 - messageIndex;
                          if (reversedIndex < 0 || reversedIndex >= messages.length) {
                            return const SizedBox.shrink();
                          }
                          return _MessageBubble(message: messages[reversedIndex]);
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

          // Question queue overlay
          if (sessionId.isNotEmpty)
            QuestionQueueWidget(
              key: _questionQueueKey,
              sessionId: sessionId,
              onQuestionAnswered: (question, answer) {
                AppLogger.info('Question ${question.id} answered: $answer');
              },
              onQuestionSkipped: (question, _) {
                AppLogger.info('Question ${question.id} skipped');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
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
                LucideIcons.bot,
                size: 48,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'How can I help?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything or try one of the suggestions below.',
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
                  label: 'Deep research',
                  onTap: () {
                    _textController.text = 'Do deep research on ';
                    _textController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _textController.text.length),
                    );
                    _focusNode.requestFocus();
                  },
                ),
                _SuggestionChip(
                  label: 'What needs attention?',
                  onTap: () {
                    _textController.text = 'What needs my attention today?';
                    _sendMessage();
                  },
                ),
                _SuggestionChip(
                  label: 'Check status',
                  onTap: () {
                    _textController.text = 'Show me the status of my campaigns and tasks';
                    _sendMessage();
                  },
                ),
                _SuggestionChip(
                  label: 'Quick question',
                  onTap: () {
                    _textController.text = '';
                    _focusNode.requestFocus();
                  },
                ),
                _SuggestionChip(
                  label: "What's happening today?",
                  onTap: () {
                    _textController.text = "What's happening today?";
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
    // When thinking indicator is visible at the top, don't show dots
    if (_isThinking) {
      return const SizedBox(height: 8);
    }

    // Show simple dots when streaming content but not actively running tools
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
    // Use viewPadding.bottom (not padding.bottom) to get safe area without keyboard inset
    // This prevents double-padding when keyboard opens since Scaffold handles keyboard avoidance
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;
    final isListening = _dictationState == DictationState.listening;
    final isInitializing = _dictationState == DictationState.initializing;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: bottomSafeArea > 0 ? bottomSafeArea : 8,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(
          top: BorderSide(color: context.borderColor),
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
                        color: context.textSecondary.withValues(alpha: 0.7),
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
              // File attachment button
              SizedBox(
                width: 36,
                height: 40,
                child: IconButton(
                  onPressed: _isUploading ? null : _pickAndUploadFiles,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: _isUploading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.primaryColor,
                          ),
                        )
                      : Icon(LucideIcons.paperclip,
                          size: 18, color: context.textSecondary),
                  tooltip: 'Attach files',
                ),
              ),

              const SizedBox(width: 4),

              // Text input with mic button inside
              Expanded(
                child: Builder(
                  builder: (context) {
                    final isLoading = ref.watch(chatLoadingProvider);
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: isListening
                            ? Border.all(
                                color: Colors.red.withValues(alpha: 0.5),
                                width: 2)
                            : null,
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: isLoading
                              ? 'Type to add context...'
                              : 'Type or speak...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: context.backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                          // Mic button inside text field
                          suffixIcon: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: isListening ? _pulseAnimation.value : 1.0,
                                child: IconButton(
                                  onPressed:
                                      isInitializing ? null : _toggleDictation,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                  icon: isInitializing
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: context.primaryColor,
                                          ),
                                        )
                                      : Icon(
                                          isListening
                                              ? LucideIcons.micOff
                                              : LucideIcons.mic,
                                          size: 18,
                                          color: isListening
                                              ? Colors.red
                                              : context.textSecondary,
                                        ),
                                  tooltip: isListening
                                      ? 'Stop dictation'
                                      : 'Start dictation',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(width: 8),

              // Send/Stop button - compact
              _buildSendOrStopButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendOrStopButton() {
    final isLoading = ref.watch(chatLoadingProvider);

    if (isLoading) {
      // Show stop button during streaming
      return SizedBox(
        width: 40,
        height: 40,
        child: IconButton.filled(
          onPressed: _stopStreaming,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Colors.red.shade400,
          ),
          icon: const Icon(LucideIcons.square, size: 16),
          tooltip: 'Stop generating',
        ),
      );
    }

    // Show send button normally
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.filled(
        onPressed: () => _sendMessage(),
        padding: EdgeInsets.zero,
        icon: const Icon(LucideIcons.send, size: 18),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  String _formatTime(DateTime timestamp) {
    return DateFormat('h:mm a').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    // Check if message contains GenUI widgets
    final hasGenUI = !isUser && GenUIParser.hasWidgets(message.content);
    final genUIWidgets = hasGenUI ? GenUIParser.extractWidgets(message.content) : <GenUIWidgetSpec>[];
    final textContent = hasGenUI ? GenUIParser.stripWidgets(message.content) : message.content;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
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
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Text content (if any)
                if (textContent.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? context.primaryColor : context.surfaceColor,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isUser ? Radius.zero : null,
                        bottomLeft: !isUser ? Radius.zero : null,
                      ),
                    ),
                    child: SelectableText(
                      textContent,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isUser ? Colors.white : null,
                          ),
                    ),
                  ),

                // GenUI widgets
                if (genUIWidgets.isNotEmpty) ...[
                  if (textContent.isNotEmpty) const SizedBox(height: 8),
                  ...genUIWidgets.map((widget) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GenUISimpleWidget(
                      widgetType: widget.widgetType,
                      data: widget.data,
                      onAction: (action, data) {
                        _handleGenUIAction(context, action, data);
                      },
                    ),
                  )),
                ],

                // Timestamp
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textTertiary,
                          fontSize: 11,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _handleGenUIAction(BuildContext context, String action, Map<String, dynamic> data) {
    AppLogger.info('GenUI action: $action with data: $data');

    switch (action) {
      case 'view_campaign':
        final id = data['id'];
        if (id != null) context.push('/campaigns/$id');
        break;
      case 'view_contact':
        final id = data['id'];
        if (id != null) context.push('/contacts/$id');
        break;
      case 'view_page':
      case 'edit_page':
        final id = data['id'];
        if (id != null) context.push('/landing-pages/$id');
        break;
      case 'view_task':
        final id = data['id'];
        if (id != null) context.push('/tasks/$id');
        break;
      default:
        AppLogger.info('Unhandled GenUI action: $action');
    }
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

/// Small action button for the app bar
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
