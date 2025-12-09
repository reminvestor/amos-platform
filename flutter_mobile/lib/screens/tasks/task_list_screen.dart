import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/scheduled_task.dart';
import 'package:amos_mobile/services/scheduled_tasks_service.dart';
import 'package:amos_mobile/utils/error_handler.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen>
    with ErrorHandler, SingleTickerProviderStateMixin {
  final ScheduledTasksService _service = ScheduledTasksService();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  List<ScheduledTask> _tasks = [];
  ScheduledTaskCounts _counts = ScheduledTaskCounts(
    active: 0,
    paused: 0,
    completed: 0,
    failed: 0,
    total: 0,
  );
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _totalPages = 1;
  String? _currentStatus;

  final List<_StatusTab> _tabs = [
    _StatusTab(null, 'All', LucideIcons.list),
    _StatusTab('active', 'Active', LucideIcons.play),
    _StatusTab('paused', 'Paused', LucideIcons.pause),
    _StatusTab('completed', 'Done', LucideIcons.circleCheck),
    _StatusTab('failed', 'Failed', LucideIcons.circleX),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _loadTasks();
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
    final newStatus = _tabs[_tabController.index].status;
    if (newStatus != _currentStatus) {
      _currentStatus = newStatus;
      _currentPage = 1;
      _loadTasks();
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

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _service.getScheduledTasks(
        status: _currentStatus,
        page: 1,
        perPage: 20,
      );

      if (mounted) {
        setState(() {
          _tasks = response.tasks;
          _counts = response.counts;
          _currentPage = response.currentPage;
          _totalPages = response.totalPages;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load tasks', error: e, stackTrace: stackTrace);
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
      final response = await _service.getScheduledTasks(
        status: _currentStatus,
        page: _currentPage + 1,
        perPage: 20,
      );

      if (mounted) {
        setState(() {
          _tasks.addAll(response.tasks);
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

  Future<void> _pauseTask(ScheduledTask task) async {
    try {
      await _service.pauseTask(task.id);
      if (mounted) {
        showSuccess(context, 'Task paused');
        _loadTasks();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _resumeTask(ScheduledTask task) async {
    try {
      await _service.resumeTask(task.id);
      if (mounted) {
        showSuccess(context, 'Task resumed');
        _loadTasks();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _runNow(ScheduledTask task) async {
    try {
      await _service.runNow(task.id);
      if (mounted) {
        showSuccess(context, 'Task queued for execution');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteTask(ScheduledTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteScheduledTask(task.id);
        if (mounted) {
          showSuccess(context, 'Task deleted');
          _loadTasks();
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  int _getCountForStatus(String? status) {
    switch (status) {
      case 'active':
        return _counts.active;
      case 'paused':
        return _counts.paused;
      case 'completed':
        return _counts.completed;
      case 'failed':
        return _counts.failed;
      default:
        return _counts.total;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Scheduled Tasks'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadTasks,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((tab) {
            final count = _getCountForStatus(tab.status);
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
            Text('Failed to load tasks', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadTasks,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.calendarClock, size: 64, color: context.textSecondary),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scheduled tasks will appear here when you create them',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _tasks.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _tasks.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final task = _tasks[index];
          return _ScheduledTaskCard(
            task: task,
            onPause: () => _pauseTask(task),
            onResume: () => _resumeTask(task),
            onRunNow: () => _runNow(task),
            onDelete: () => _deleteTask(task),
          );
        },
      ),
    );
  }

  String _getEmptyMessage() {
    switch (_currentStatus) {
      case 'active':
        return 'No active tasks';
      case 'paused':
        return 'No paused tasks';
      case 'completed':
        return 'No completed tasks';
      case 'failed':
        return 'No failed tasks';
      default:
        return 'No scheduled tasks';
    }
  }
}

class _StatusTab {
  final String? status;
  final String label;
  final IconData icon;

  _StatusTab(this.status, this.label, this.icon);
}

class _ScheduledTaskCard extends StatelessWidget {
  final ScheduledTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRunNow;
  final VoidCallback onDelete;

  const _ScheduledTaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRunNow,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIcon(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (task.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                _buildStatusBadge(context),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetadata(context),
            if (task.hasFailures) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.triangleAlert, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${task.consecutiveFailures} consecutive failure${task.consecutiveFailures == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _getStatusBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          task.taskTypeInfo.icon.isNotEmpty ? task.taskTypeInfo.icon : '',
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }

  Color _getStatusBackgroundColor(BuildContext context) {
    switch (task.status) {
      case 'active':
        return Colors.green.shade50;
      case 'paused':
        return Colors.orange.shade50;
      case 'failed':
        return Colors.red.shade50;
      case 'completed':
        return Colors.blue.shade50;
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  Widget _buildStatusBadge(BuildContext context) {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (task.status) {
      case 'active':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        icon = LucideIcons.play;
        break;
      case 'paused':
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        icon = LucideIcons.pause;
        break;
      case 'failed':
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade700;
        icon = LucideIcons.circleX;
        break;
      case 'completed':
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade700;
        icon = LucideIcons.circleCheck;
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        icon = LucideIcons.circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            task.statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _MetadataItem(
          icon: LucideIcons.repeat,
          label: task.scheduleLabel,
        ),
        _MetadataItem(
          icon: LucideIcons.hash,
          label: '${task.runCount} runs',
        ),
        if (task.nextRunAt != null)
          _MetadataItem(
            icon: LucideIcons.clock,
            label: 'Next: ${DateFormat('MMM d, h:mm a').format(task.nextRunAt!)}',
          ),
        if (task.lastRunAt != null)
          _MetadataItem(
            icon: LucideIcons.history,
            label: 'Last: ${DateFormat('MMM d, h:mm a').format(task.lastRunAt!)}',
          ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        if (task.status == 'active') ...[
          OutlinedButton.icon(
            onPressed: onPause,
            icon: const Icon(LucideIcons.pause, size: 16),
            label: const Text('Pause'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (task.status == 'paused') ...[
          OutlinedButton.icon(
            onPressed: onResume,
            icon: const Icon(LucideIcons.play, size: 16),
            label: const Text('Resume'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (task.canRun) ...[
          ElevatedButton.icon(
            onPressed: onRunNow,
            icon: const Icon(LucideIcons.zap, size: 16),
            label: const Text('Run Now'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        IconButton(
          icon: Icon(LucideIcons.trash2, size: 18, color: Colors.red.shade400),
          onPressed: onDelete,
          tooltip: 'Delete',
        ),
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.textSecondary,
              ),
        ),
      ],
    );
  }
}
