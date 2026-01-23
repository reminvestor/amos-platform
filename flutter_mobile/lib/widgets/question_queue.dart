import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/agent_question.dart';
import 'package:amos_mobile/services/questions_service.dart';
import 'package:amos_mobile/services/action_cable_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Callback for when a question is answered or skipped
typedef QuestionCallback = void Function(AgentQuestion question, String? answer);

/// Widget that displays a floating badge for agent questions
/// and shows an overlay modal when tapped
class QuestionQueueWidget extends StatefulWidget {
  final String sessionId;
  final QuestionCallback? onQuestionAnswered;
  final QuestionCallback? onQuestionSkipped;

  const QuestionQueueWidget({
    super.key,
    required this.sessionId,
    this.onQuestionAnswered,
    this.onQuestionSkipped,
  });

  @override
  State<QuestionQueueWidget> createState() => QuestionQueueWidgetState();
}

class QuestionQueueWidgetState extends State<QuestionQueueWidget>
    with SingleTickerProviderStateMixin {
  final QuestionsService _questionsService = QuestionsService();
  final ActionCableService _actionCable = ActionCableService();
  List<AgentQuestion> _questions = [];
  List<AgentCompletion> _completions = [];
  bool _isOverlayVisible = false;
  bool _isLoading = false;
  StreamSubscription<QuestionQueueUpdate>? _queueSubscription;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadQuestions();
    _subscribeToWebSocket();
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    _actionCable.unsubscribeFromQuestionQueue(widget.sessionId);
    _pulseController.dispose();
    super.dispose();
  }

  void _subscribeToWebSocket() {
    // Connect to ActionCable and subscribe to question queue
    _actionCable.connect().then((_) {
      _actionCable.subscribeToQuestionQueue(widget.sessionId);
    });

    // Listen for real-time updates
    _queueSubscription = _actionCable.questionQueueStream.listen(_handleQueueUpdate);
  }

  void _handleQueueUpdate(QuestionQueueUpdate update) {
    AppLogger.info('WebSocket question update: ${update.action}');

    switch (update.action) {
      case 'added':
        if (update.question != null) {
          final question = AgentQuestion.fromJson(update.question!);
          addQuestion(question);
        }
        break;
      case 'answered':
      case 'skipped':
      case 'cancelled':
        if (update.questionId != null) {
          removeQuestion(update.questionId!);
        }
        break;
      case 'completed':
        if (update.completion != null) {
          final completion = AgentCompletion.fromJson(update.completion!);
          addCompletion(completion);
        }
        break;
    }
  }

  Future<void> _loadQuestions() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await _questionsService.fetchPendingQuestionsAndCompletions(widget.sessionId);

      final hadQuestions = _questions.isNotEmpty;
      final hasNewQuestions = response.questions.length > _questions.length;
      final hasNewCompletions = response.completions.isNotEmpty;

      setState(() {
        _questions = response.questions;

        // Add new completions (avoid duplicates by checking ID)
        for (final completion in response.completions) {
          if (!_completions.any((c) => c.id == completion.id)) {
            _completions.insert(0, completion);
          }
        }

        _isLoading = false;
      });

      // Pulse animation when new questions or completions arrive
      if (!hadQuestions && response.questions.isNotEmpty || hasNewQuestions || hasNewCompletions) {
        _pulseController.repeat(reverse: true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _pulseController.stop();
        });
      }
    } catch (e) {
      AppLogger.error('Error loading questions', error: e);
      setState(() => _isLoading = false);
    }
  }

  /// Add a question to the queue (called from SSE stream)
  void addQuestion(AgentQuestion question) {
    setState(() {
      // Avoid duplicates
      if (!_questions.any((q) => q.id == question.id)) {
        _questions.insert(0, question);
        _pulseController.repeat(reverse: true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _pulseController.stop();
        });
      }
    });
  }

  /// Add a completion notification
  void addCompletion(AgentCompletion completion) {
    setState(() {
      _completions.insert(0, completion);
      _pulseController.repeat(reverse: true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _pulseController.stop();
      });
    });
  }

  /// Remove a question after it's answered
  void removeQuestion(int questionId) {
    setState(() {
      _questions.removeWhere((q) => q.id == questionId);
    });
  }

  void _toggleOverlay() {
    AppLogger.info('Toggle overlay: questions=${_questions.length}, completions=${_completions.length}');
    for (var q in _questions) {
      AppLogger.info('  Question ${q.id}: ${q.question.substring(0, q.question.length.clamp(0, 50))}...');
    }
    setState(() {
      _isOverlayVisible = !_isOverlayVisible;
    });
  }

  void _closeOverlay() {
    setState(() {
      _isOverlayVisible = false;
    });
  }

  int get _totalCount => _questions.length + _completions.length;

  @override
  Widget build(BuildContext context) {
    // Don't show badge if no questions or completions
    if (_totalCount == 0 && !_isOverlayVisible) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Floating badge
        if (_totalCount > 0)
          Positioned(
            left: 16,
            bottom: 16,
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: _QuestionBadge(
                count: _totalCount,
                onTap: _toggleOverlay,
              ),
            ),
          ),

        // Overlay
        if (_isOverlayVisible)
          _QuestionOverlay(
            questions: _questions,
            completions: _completions,
            onClose: _closeOverlay,
            onAnswer: (question, answer) async {
              final success = await _questionsService.submitAnswer(
                question.id,
                answer,
              );
              if (success) {
                removeQuestion(question.id);
                widget.onQuestionAnswered?.call(question, answer);
                if (_questions.isEmpty) {
                  _closeOverlay();
                }
              }
            },
            onSkip: (question) async {
              final success = await _questionsService.skipQuestion(question.id);
              if (success) {
                removeQuestion(question.id);
                widget.onQuestionSkipped?.call(question, null);
                if (_questions.isEmpty) {
                  _closeOverlay();
                }
              }
            },
            onDismissCompletion: (completion) {
              setState(() {
                _completions.remove(completion);
              });
            },
          ),
      ],
    );
  }
}

/// Floating badge button
class _QuestionBadge extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _QuestionBadge({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(28),
      color: context.primaryColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.messageSquare,
                color: Colors.white,
                size: 24,
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Question overlay modal
class _QuestionOverlay extends StatefulWidget {
  final List<AgentQuestion> questions;
  final List<AgentCompletion> completions;
  final VoidCallback onClose;
  final Future<void> Function(AgentQuestion question, String answer) onAnswer;
  final Future<void> Function(AgentQuestion question) onSkip;
  final void Function(AgentCompletion completion) onDismissCompletion;

  const _QuestionOverlay({
    required this.questions,
    required this.completions,
    required this.onClose,
    required this.onAnswer,
    required this.onSkip,
    required this.onDismissCompletion,
  });

  @override
  State<_QuestionOverlay> createState() => _QuestionOverlayState();
}

class _QuestionOverlayState extends State<_QuestionOverlay> {
  int _currentQuestionIndex = 0;
  final _answerController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  AgentQuestion? get _currentQuestion {
    if (widget.questions.isEmpty) return null;
    if (_currentQuestionIndex >= widget.questions.length) {
      _currentQuestionIndex = 0;
    }
    return widget.questions[_currentQuestionIndex];
  }

  Future<void> _submitAnswer() async {
    final question = _currentQuestion;
    if (question == null || _answerController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);

    await widget.onAnswer(question, _answerController.text.trim());

    _answerController.clear();
    setState(() {
      _isSubmitting = false;
      _currentQuestionIndex = 0;
    });
  }

  Future<void> _skipQuestion() async {
    final question = _currentQuestion;
    if (question == null) return;

    setState(() => _isSubmitting = true);

    await widget.onSkip(question);

    setState(() {
      _isSubmitting = false;
      _currentQuestionIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: GestureDetector(
                onTap: () {}, // Prevent tap from closing
                child: Container(
                  margin: const EdgeInsets.all(16),
                  width: MediaQuery.of(context).size.width * 0.9,
                  constraints: BoxConstraints(
                    maxWidth: 400,
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      _buildHeader(context),

                      // Content
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Active question FIRST (requires action)
                              if (_currentQuestion != null)
                                _buildActiveQuestion(context, _currentQuestion!),

                              // Question list (if multiple)
                              if (widget.questions.length > 1) ...[
                                const SizedBox(height: 16),
                                _buildQuestionList(context),
                              ],

                              // Completions (info only, shown after questions)
                              if (widget.completions.isNotEmpty) ...[
                                if (widget.questions.isNotEmpty)
                                  const Divider(height: 24),
                                ...widget.completions.map((c) => _buildCompletion(context, c)),
                              ],

                              // Empty state
                              if (widget.questions.isEmpty && widget.completions.isEmpty)
                                _buildEmptyState(context),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.messageSquare, color: context.primaryColor),
          const SizedBox(width: 8),
          Text(
            'Agent Questions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.questions.length} questions waiting',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: widget.questions.length,
            itemBuilder: (context, index) {
              final question = widget.questions[index];
              final isActive = index == _currentQuestionIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(question.agentIcon),
                  selected: isActive,
                  onSelected: (_) {
                    setState(() => _currentQuestionIndex = index);
                    _answerController.clear();
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActiveQuestion(BuildContext context, AgentQuestion question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Agent info
        Row(
          children: [
            Text(
              question.agentIcon,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.agentName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    question.timeAgo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Question content
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.primaryColor.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            question.question,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),

        // Answer input
        TextField(
          controller: _answerController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Type your answer...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
          enabled: !_isSubmitting,
        ),
        const SizedBox(height: 12),

        // Actions
        Row(
          children: [
            TextButton.icon(
              onPressed: _isSubmitting ? null : _skipQuestion,
              icon: const Icon(LucideIcons.skipForward, size: 18),
              label: const Text('Skip'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitAnswer,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: const Text('Send Answer'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletion(BuildContext context, AgentCompletion completion) {
    // If this is the only item (no questions), show prominent completion view
    final isProminent = widget.questions.isEmpty;

    if (isProminent) {
      return Column(
        children: [
          // Prominent completion card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Text('✅', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'Task Completed!',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      completion.agentIcon,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      completion.agentName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  completion.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'View full results in Work Items',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.onDismissCompletion(completion),
                icon: const Icon(LucideIcons.x, size: 18),
                label: const Text('Dismiss'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () {
                  widget.onDismissCompletion(completion);
                  // Close the overlay and navigate to inbox
                  widget.onClose();
                  // Navigate to inbox screen
                  context.goNamed('inbox');
                },
                icon: const Icon(LucideIcons.inbox, size: 18),
                label: const Text('View Work Items'),
              ),
            ],
          ),
        ],
      );
    }

    // Compact completion card when questions are also present
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(completion.agentIcon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.circleCheck, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      completion.agentName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                Text(
                  completion.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18),
            onPressed: () => widget.onDismissCompletion(completion),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleCheck,
            size: 48,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          Text(
            'No questions waiting!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
