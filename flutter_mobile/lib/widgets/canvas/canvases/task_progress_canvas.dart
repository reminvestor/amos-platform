import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/services/canvas_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Canvas for displaying task progress (single task or parallel tasks)
class TaskProgressCanvas extends ConsumerStatefulWidget {
  final Canvas canvas;

  const TaskProgressCanvas({super.key, required this.canvas});

  @override
  ConsumerState<TaskProgressCanvas> createState() => _TaskProgressCanvasState();
}

class _TaskProgressCanvasState extends ConsumerState<TaskProgressCanvas> {
  final _canvasService = CanvasService();
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check if tasks are embedded in canvas data
      final embeddedTasks = widget.canvas.getData<List>('tasks');
      if (embeddedTasks != null) {
        setState(() {
          _tasks = embeddedTasks.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
        return;
      }

      // Otherwise fetch from API
      final taskSessionId = widget.canvas.getData<dynamic>('task_session_id')?.toString();
      if (taskSessionId != null) {
        final tasks = await _canvasService.fetchResourceList(
          resourceType: 'tasks',
          filters: {'session_id': taskSessionId},
        );
        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      } else {
        setState(() {
          _tasks = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load tasks', error: e);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_tasks.isEmpty) {
      return _buildEmptyState();
    }

    final isParallel = widget.canvas.type == Canvas.parallelTasks;

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isParallel) ...[
            _buildParallelHeader(context),
            const SizedBox(height: 16),
          ],
          ..._tasks.map((task) => _TaskCard(task: task)),
        ],
      ),
    );
  }

  Widget _buildParallelHeader(BuildContext context) {
    final completedCount = _tasks.where((t) => t['status'] == 'completed').length;
    final progress = _tasks.isNotEmpty ? completedCount / _tasks.length : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.layers,
                  size: 20,
                  color: context.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Parallel Tasks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Text(
                  '$completedCount / ${_tasks.length}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: context.borderColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.listTodo,
            size: 48,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No tasks in progress',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 48,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load tasks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loadTasks,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final title = task['title'] ?? task['name'] ?? 'Untitled Task';
    final description = task['description'] ?? task['message'];
    final status = task['status'] ?? 'pending';
    final progress = task['progress']?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusIcon(status: status),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (status == 'in_progress' && progress > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 6,
                        backgroundColor: context.borderColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${progress.toInt()}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
        icon = LucideIcons.circleCheck;
        color = Colors.green;
        break;
      case 'in_progress':
      case 'running':
        icon = LucideIcons.loader;
        color = Colors.blue;
        break;
      case 'failed':
      case 'error':
        icon = LucideIcons.circleX;
        color = Colors.red;
        break;
      case 'pending':
      case 'queued':
      default:
        icon = LucideIcons.clock;
        color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
