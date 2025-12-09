import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/task.dart';
import 'package:amos_mobile/services/tasks_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const TaskDetailScreen({super.key, required this.id});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final TasksService _tasksService = TasksService();
  Task? _task;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTask();
    });
  }

  Future<void> _loadTask() async {
    AppLogger.info('TaskDetailScreen: Loading task ${widget.id}');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final task = await _tasksService.getTask(widget.id);
      if (!mounted) return;
      setState(() => _task = task);
      AppLogger.info('TaskDetailScreen: Loaded task "${task.title}"');
    } catch (e, stackTrace) {
      AppLogger.error('TaskDetailScreen: Failed to load task', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load task: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleTaskStatus() async {
    if (_task == null || _isUpdating) return;

    setState(() => _isUpdating = true);

    try {
      if (_task!.status == TaskStatus.completed) {
        await _tasksService.updateTask(_task!.id, status: 'pending');
      } else {
        await _tasksService.completeTask(_task!.id);
      }
      await _loadTask();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_task!.status == TaskStatus.completed
                ? 'Task marked as pending'
                : 'Task completed'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update task: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _deleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);

    try {
      await _tasksService.deleteTask(widget.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted')),
        );
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete task: $e')),
      );
      setState(() => _isUpdating = false);
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
        title: const Text('Task Details'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _loadTask,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _task == null
                  ? _buildNotFoundState()
                  : _buildTaskContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleX,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTask,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.fileSearch,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Task Not Found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'This task may have been deleted.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(LucideIcons.arrowLeft),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskContent() {
    final task = _task!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task Title
          Text(
            task.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),

          // Status and Priority
          Row(
            children: [
              _StatusChip(status: task.status),
              const SizedBox(width: 8),
              _PriorityChip(priority: task.priority),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          if (task.description != null) ...[
            Text(
              'Description',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              task.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
          ],

          // Details Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (task.dueDate != null)
                    _DetailRow(
                      icon: LucideIcons.calendar,
                      label: 'Due Date',
                      value: DateFormat('MMM d, yyyy').format(task.dueDate!),
                    ),
                  if (task.dueDate != null) const Divider(),
                  _DetailRow(
                    icon: LucideIcons.clock,
                    label: 'Created',
                    value: DateFormat('MMM d, yyyy at h:mm a')
                        .format(task.createdAt),
                  ),
                  const Divider(),
                  _DetailRow(
                    icon: LucideIcons.refreshCw,
                    label: 'Updated',
                    value: DateFormat('MMM d, yyyy at h:mm a')
                        .format(task.updatedAt),
                  ),
                ],
              ),
            ),
          ),

          // Artifacts section (if present)
          if (task.artifacts != null && task.artifacts!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Artifacts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.borderColor),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: task.artifacts!.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final artifact = task.artifacts![index];
                  return ListTile(
                    leading: Icon(
                      _getArtifactIcon(artifact),
                      color: context.primaryColor,
                    ),
                    title: Text(
                      artifact['name'] ?? artifact['type'] ?? 'Artifact ${index + 1}',
                    ),
                    subtitle: artifact['description'] != null
                        ? Text(artifact['description'])
                        : null,
                    trailing: const Icon(LucideIcons.chevronRight),
                    onTap: () {
                      // TODO: Handle artifact tap
                    },
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Action Buttons
          if (task.status != TaskStatus.completed &&
              task.status != TaskStatus.failed &&
              task.status != TaskStatus.cancelled)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUpdating ? null : _toggleTaskStatus,
                icon: _isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.check),
                label: const Text('Mark as Complete'),
              ),
            ),
          if (task.status == TaskStatus.completed) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUpdating ? null : _toggleTaskStatus,
                icon: _isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.rotateCcw),
                label: const Text('Mark as Pending'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isUpdating ? null : _deleteTask,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.errorColor,
              ),
              icon: const Icon(LucideIcons.trash2),
              label: const Text('Delete Task'),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getArtifactIcon(dynamic artifact) {
    final type = artifact['type']?.toString().toLowerCase() ?? '';
    if (type.contains('landing') || type.contains('page')) {
      return LucideIcons.layoutTemplate;
    } else if (type.contains('email')) {
      return LucideIcons.mail;
    } else if (type.contains('image')) {
      return LucideIcons.image;
    } else if (type.contains('campaign')) {
      return LucideIcons.megaphone;
    }
    return LucideIcons.file;
  }
}

class _StatusChip extends StatelessWidget {
  final TaskStatus status;

  const _StatusChip({required this.status});

  Color _getColor() {
    switch (status) {
      case TaskStatus.pending:
        return Colors.grey;
      case TaskStatus.active:
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.failed:
        return Colors.red;
      case TaskStatus.cancelled:
        return Colors.grey.shade600;
      case TaskStatus.paused:
        return Colors.orange;
    }
  }

  IconData _getIcon() {
    switch (status) {
      case TaskStatus.pending:
        return LucideIcons.circle;
      case TaskStatus.active:
      case TaskStatus.inProgress:
        return LucideIcons.clock;
      case TaskStatus.completed:
        return LucideIcons.circleCheck;
      case TaskStatus.failed:
        return LucideIcons.circleX;
      case TaskStatus.cancelled:
        return LucideIcons.circleSlash;
      case TaskStatus.paused:
        return LucideIcons.circlePause;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getIcon(), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final TaskPriority priority;

  const _PriorityChip({required this.priority});

  Color _getColor() {
    switch (priority) {
      case TaskPriority.high:
        return Colors.red;
      case TaskPriority.medium:
        return Colors.orange;
      case TaskPriority.low:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.flag, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            priority.displayName,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.textTertiary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
