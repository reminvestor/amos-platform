import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/work_item.dart';
import 'package:amos_mobile/services/work_items_service.dart';
import 'package:amos_mobile/services/questions_service.dart';
import 'package:amos_mobile/utils/error_handler.dart';
import 'package:amos_mobile/utils/logger.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen>
    with ErrorHandler, SingleTickerProviderStateMixin {
  final WorkItemsService _service = WorkItemsService();
  final QuestionsService _questionsService = QuestionsService();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  List<WorkItem> _workItems = [];
  WorkItemCounts _counts = WorkItemCounts(unread: 0, starred: 0, actionRequired: 0, total: 0);
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _totalPages = 1;
  String _currentFilter = 'unread';

  final List<_FilterTab> _tabs = [
    _FilterTab('unread', 'Unread', LucideIcons.mailOpen),
    _FilterTab('all', 'All', LucideIcons.inbox),
    _FilterTab('starred', 'Starred', LucideIcons.star),
    _FilterTab('action_required', 'Action', LucideIcons.circleAlert),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _loadWorkItems();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final newFilter = _tabs[_tabController.index].filter;
    if (newFilter != _currentFilter) {
      _currentFilter = newFilter;
      _currentPage = 1;
      _loadWorkItems();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _totalPages) {
        _loadMore();
      }
    }
  }

  Future<void> _loadWorkItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _service.getWorkItems(
        filter: _currentFilter == 'all' ? null : _currentFilter,
        page: 1,
        perPage: 20,
      );

      if (mounted) {
        setState(() {
          _workItems = response.workItems;
          _counts = response.counts;
          _currentPage = response.currentPage;
          _totalPages = response.totalPages;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load inbox', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final response = await _service.getWorkItems(
        filter: _currentFilter == 'all' ? null : _currentFilter,
        page: _currentPage + 1,
        perPage: 20,
      );

      if (mounted) {
        setState(() {
          _workItems.addAll(response.workItems);
          _currentPage = response.currentPage;
          _totalPages = response.totalPages;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        showError(context, e);
      }
    }
  }

  Future<void> _toggleStarred(WorkItem item) async {
    try {
      final updated = await _service.toggleStarred(item.id);
      _updateItemInList(updated);
      if (mounted) {
        showSuccess(context, updated.starred ? 'Starred' : 'Unstarred');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markAsRead(WorkItem item) async {
    if (item.read) return;

    try {
      final updated = await _service.markAsRead(item.id);
      _updateItemInList(updated);
      _refreshCounts();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _archive(WorkItem item) async {
    try {
      await _service.archive(item.id);
      setState(() {
        _workItems.removeWhere((i) => i.id == item.id);
      });
      _refreshCounts();
      if (mounted) {
        showSuccess(context, 'Archived');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _service.markAllAsRead();
      _loadWorkItems();
      if (mounted) {
        showSuccess(context, 'All marked as read');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _updateItemInList(WorkItem updated) {
    setState(() {
      final index = _workItems.indexWhere((i) => i.id == updated.id);
      if (index != -1) {
        _workItems[index] = updated;
      }
    });
  }

  Future<void> _refreshCounts() async {
    try {
      final response = await _service.getWorkItems(page: 1, perPage: 1);
      if (mounted) {
        setState(() {
          _counts = response.counts;
        });
      }
    } catch (e) {
      // Ignore count refresh errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logo-header.png',
          height: 26,
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xFF1a1a2e)
              : null,
        ),
        actions: [
          if (_counts.unread > 0)
            IconButton(
              icon: const Icon(LucideIcons.checkCheck),
              onPressed: _markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadWorkItems,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(LucideIcons.bell),
            onPressed: () => context.push('/notifications'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((tab) {
            int count = 0;
            switch (tab.filter) {
              case 'unread':
                count = _counts.unread;
                break;
              case 'starred':
                count = _counts.starred;
                break;
              case 'action_required':
                count = _counts.actionRequired;
                break;
              case 'all':
                count = _counts.total;
                break;
            }
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 16),
                  const SizedBox(width: 4),
                  Text(tab.label),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count > 99 ? '99+' : count.toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            Text('Failed to load inbox', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadWorkItems,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_workItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.inbox, size: 64, color: context.textSecondary),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Work items from your agents will appear here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadWorkItems,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _workItems.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _workItems.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final item = _workItems[index];
          return _WorkItemTile(
            item: item,
            onTap: () => _showItemDetails(item),
            onStar: () => _toggleStarred(item),
            onArchive: () => _archive(item),
          );
        },
      ),
    );
  }

  String _getEmptyMessage() {
    switch (_currentFilter) {
      case 'unread':
        return 'No unread items';
      case 'starred':
        return 'No starred items';
      case 'action_required':
        return 'No action required';
      default:
        return 'Your inbox is empty';
    }
  }

  void _showItemDetails(WorkItem item) {
    // Mark as read when opening
    _markAsRead(item);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WorkItemDetailSheet(
        item: item,
        onStar: () {
          Navigator.pop(context);
          _toggleStarred(item);
        },
        onArchive: () {
          Navigator.pop(context);
          _archive(item);
        },
        onAnswer: (inputRequestId, answer) async {
          final success = await _questionsService.submitAnswer(inputRequestId, answer);
          if (success && mounted) {
            // Refresh the work items list
            _loadWorkItems();
            showSuccess(context, 'Answer submitted');
          } else if (mounted) {
            showError(context, 'Failed to submit answer');
          }
        },
        onSkip: (inputRequestId) async {
          final success = await _questionsService.skipQuestion(inputRequestId);
          if (success && mounted) {
            // Refresh the work items list
            _loadWorkItems();
            showSuccess(context, 'Question skipped');
          } else if (mounted) {
            showError(context, 'Failed to skip question');
          }
        },
      ),
    );
  }
}

class _FilterTab {
  final String filter;
  final String label;
  final IconData icon;

  _FilterTab(this.filter, this.label, this.icon);
}

class _WorkItemTile extends StatelessWidget {
  final WorkItem item;
  final VoidCallback onTap;
  final VoidCallback onStar;
  final VoidCallback onArchive;

  const _WorkItemTile({
    required this.item,
    required this.onTap,
    required this.onStar,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('work_item_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(LucideIcons.archive, color: Colors.white),
      ),
      onDismissed: (_) => onArchive(),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildIcon(context),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontWeight: item.read ? FontWeight.normal : FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isHighPriority)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item.priority == 'urgent'
                      ? Colors.red.shade100
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.priority.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: item.priority == 'urgent'
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.summary != null) ...[
              const SizedBox(height: 4),
              Text(
                item.summary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textSecondary),
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.workTypeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.textSecondary,
                    ),
                  ),
                ),
                if (item.agentName != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.bot, size: 12, color: context.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        item.agentName!,
                        style: TextStyle(fontSize: 11, color: context.textSecondary),
                      ),
                    ],
                  ),
                Text(
                  item.timeAgo ?? '',
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            item.starred ? LucideIcons.star : LucideIcons.star,
            color: item.starred ? Colors.amber : context.textSecondary,
            fill: item.starred ? 1 : 0,
            size: 20,
          ),
          onPressed: onStar,
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _getIconBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          item.icon.isNotEmpty ? item.icon : _getDefaultIcon(),
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }

  Color _getIconBackgroundColor(BuildContext context) {
    if (item.requiresAction) {
      return Colors.orange.shade50;
    }
    switch (item.category) {
      case 'tasks':
        return Colors.green.shade50;
      case 'email':
        return Colors.blue.shade50;
      case 'reports':
        return Colors.purple.shade50;
      case 'research':
        return Colors.teal.shade50;
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  String _getDefaultIcon() {
    switch (item.category) {
      case 'tasks':
        return '';
      case 'email':
        return '';
      case 'reports':
        return '';
      case 'research':
        return '';
      default:
        return '';
    }
  }
}

class _WorkItemDetailSheet extends StatefulWidget {
  final WorkItem item;
  final VoidCallback onStar;
  final VoidCallback onArchive;
  final Future<void> Function(int inputRequestId, String answer)? onAnswer;
  final Future<void> Function(int inputRequestId)? onSkip;

  const _WorkItemDetailSheet({
    required this.item,
    required this.onStar,
    required this.onArchive,
    this.onAnswer,
    this.onSkip,
  });

  @override
  State<_WorkItemDetailSheet> createState() => _WorkItemDetailSheetState();
}

class _WorkItemDetailSheetState extends State<_WorkItemDetailSheet> {
  final _answerController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  int? get _inputRequestId {
    final assetData = widget.item.assetData;
    if (assetData == null) return null;
    return assetData['input_request_id'] as int?;
  }

  bool get _canAnswer => widget.item.requiresAction && _inputRequestId != null;

  Future<void> _submitAnswer() async {
    if (_answerController.text.trim().isEmpty) return;
    final inputRequestId = _inputRequestId;
    if (inputRequestId == null || widget.onAnswer == null) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.onAnswer!(inputRequestId, _answerController.text.trim());
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _skipQuestion() async {
    final inputRequestId = _inputRequestId;
    if (inputRequestId == null || widget.onSkip == null) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.onSkip!(inputRequestId);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  WorkItem get item => widget.item;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _getIconBackgroundColor(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        item.icon.isNotEmpty ? item.icon : _getDefaultIcon(),
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (item.agentName != null)
                          Row(
                            children: [
                              Icon(LucideIcons.bot, size: 14, color: context.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                item.agentName!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.timeAgo ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onStar,
                      icon: Icon(
                        item.starred ? LucideIcons.star : LucideIcons.star,
                        size: 18,
                        color: item.starred ? Colors.amber : null,
                      ),
                      label: Text(item.starred ? 'Unstar' : 'Star'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onArchive,
                      icon: const Icon(LucideIcons.archive, size: 18),
                      label: const Text('Archive'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Priority and type badges
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.workTypeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                        if (item.isHighPriority) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.priority == 'urgent'
                                  ? Colors.red.shade100
                                  : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.priority.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: item.priority == 'urgent'
                                    ? Colors.red.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Summary
                    if (item.summary != null) ...[
                      Text(
                        'Summary',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.summary!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Details - format JSON nicely or show plain text
                    if (item.details != null && item.details!.isNotEmpty) ...[
                      Text(
                        'Details',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _buildFormattedDetails(context, item.details!),
                    ],
                    // Asset action buttons (View Landing Page, View Campaign, etc.)
                    if (item.assetType != null && item.assetId != null) ...[
                      const SizedBox(height: 20),
                      _buildAssetActionButton(context, item.assetType!, item.assetId!),
                    ],
                    // Answer form for action_required items
                    if (_canAnswer) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.messageSquare, color: Colors.orange.shade700, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Your Response',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _answerController,
                              maxLines: 4,
                              enabled: !_isSubmitting,
                              decoration: InputDecoration(
                                hintText: 'Type your answer...',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.orange.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.orange.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.orange.shade400, width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
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
                                  label: const Text('Send'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getIconBackgroundColor(BuildContext context) {
    if (item.requiresAction) {
      return Colors.orange.shade50;
    }
    switch (item.category) {
      case 'tasks':
        return Colors.green.shade50;
      case 'email':
        return Colors.blue.shade50;
      case 'reports':
        return Colors.purple.shade50;
      case 'research':
        return Colors.teal.shade50;
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  String _getDefaultIcon() {
    switch (item.category) {
      case 'tasks':
        return '✅';
      case 'email':
        return '📧';
      case 'reports':
        return '📊';
      case 'research':
        return '🔍';
      default:
        return '📋';
    }
  }

  /// Formats details text, handling JSON nicely
  Widget _buildFormattedDetails(BuildContext context, String details) {
    // Try to parse as JSON and format nicely
    try {
      final json = jsonDecode(details);
      if (json is Map<String, dynamic>) {
        return _buildJsonDetails(context, json);
      }
    } catch (_) {
      // Not JSON, show as plain text
    }

    // Plain text fallback
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        details,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  /// Builds a nice display for JSON data
  Widget _buildJsonDetails(BuildContext context, Map<String, dynamic> json) {
    // Keys to display with nice labels
    final displayKeys = <String, String>{
      'title': 'Title',
      'name': 'Name',
      'preview_url': 'Preview URL',
      'edit_url': 'Edit URL',
      'url': 'URL',
      'message': 'Message',
      'summary': 'Summary',
      'description': 'Description',
      'status': 'Status',
      'landing_page_id': 'Landing Page ID',
      'campaign_id': 'Campaign ID',
      'email_id': 'Email ID',
    };

    // Filter to only show useful keys
    final entries = <MapEntry<String, dynamic>>[];
    for (final key in displayKeys.keys) {
      if (json.containsKey(key) && json[key] != null && json[key].toString().isNotEmpty) {
        entries.add(MapEntry(displayKeys[key]!, json[key]));
      }
    }

    // If no recognized keys, try to show all string values
    if (entries.isEmpty) {
      for (final entry in json.entries) {
        if (entry.value is String && entry.value.toString().isNotEmpty) {
          // Convert snake_case to Title Case
          final label = entry.key
              .split('_')
              .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' ');
          entries.add(MapEntry(label, entry.value));
        }
      }
    }

    // If still empty, show message
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.circleCheck, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              'Task completed successfully',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade700,
                  ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((entry) {
          final isUrl = entry.key.toLowerCase().contains('url');
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                        ),
                  ),
                ),
                Expanded(
                  child: isUrl
                      ? Text(
                          entry.value.toString(),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                        )
                      : Text(
                          entry.value.toString(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Builds action button for linked assets (Landing Page, Campaign, etc.)
  Widget _buildAssetActionButton(BuildContext context, String assetType, int assetId) {
    String buttonText;
    IconData buttonIcon;
    String urlPath;

    switch (assetType) {
      case 'LandingPage':
        buttonText = 'View Landing Page';
        buttonIcon = LucideIcons.externalLink;
        urlPath = '/landing_pages/$assetId/preview';
        break;
      case 'Campaign':
        buttonText = 'View Campaign';
        buttonIcon = LucideIcons.mail;
        urlPath = '/campaigns/$assetId';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Asset Created',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _openAssetUrl(urlPath),
            icon: Icon(buttonIcon, size: 18),
            label: Text(buttonText),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAssetUrl(String path) async {
    final baseUrl = Env.apiBaseUrl;
    final url = Uri.parse('$baseUrl$path');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
