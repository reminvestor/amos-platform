import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/task.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:intl/intl.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    ref.read(tasksLoadingProvider.notifier).setLoading(true);
    // TODO: Implement actual API call
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock data
    ref.read(tasksProvider.notifier).setTasks([
      Task(
        id: '1',
        entityId: 'e1',
        userId: 'u1',
        title: 'Review email campaign draft',
        description: 'Check the welcome series emails before sending',
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
        dueDate: DateTime.now().add(const Duration(days: 1)),
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now(),
      ),
      Task(
        id: '2',
        entityId: 'e1',
        userId: 'u1',
        title: 'Create landing page for product launch',
        status: TaskStatus.pending,
        priority: TaskPriority.high,
        dueDate: DateTime.now().add(const Duration(days: 3)),
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now(),
      ),
      Task(
        id: '3',
        entityId: 'e1',
        userId: 'u1',
        title: 'Update contact list',
        description: 'Remove inactive contacts and add new leads',
        status: TaskStatus.pending,
        priority: TaskPriority.medium,
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        updatedAt: DateTime.now(),
      ),
      Task(
        id: '4',
        entityId: 'e1',
        userId: 'u1',
        title: 'Schedule social media posts',
        status: TaskStatus.completed,
        priority: TaskPriority.low,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now(),
        completedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ]);

    ref.read(tasksLoadingProvider.notifier).setLoading(false);
  }

  List<Task> _getFilteredTasks(List<Task> tasks) {
    switch (_selectedFilter) {
      case 'pending':
        return tasks.where((t) => t.status == TaskStatus.pending).toList();
      case 'in_progress':
        return tasks.where((t) => t.status == TaskStatus.inProgress).toList();
      case 'completed':
        return tasks.where((t) => t.status == TaskStatus.completed).toList();
      default:
        return tasks;
    }
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return Colors.red;
      case TaskPriority.medium:
        return Colors.orange;
      case TaskPriority.low:
        return Colors.green;
    }
  }

  IconData _getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return LucideIcons.circle;
      case TaskStatus.inProgress:
        return LucideIcons.clock;
      case TaskStatus.completed:
        return LucideIcons.circleCheck;
      case TaskStatus.cancelled:
        return LucideIcons.circleX;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final isLoading = ref.watch(tasksLoadingProvider);
    final filteredTasks = _getFilteredTasks(tasks);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () {
              // TODO: Create task
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: _selectedFilter == 'all',
                  onTap: () => setState(() => _selectedFilter = 'all'),
                ),
                _FilterChip(
                  label: 'Pending',
                  isSelected: _selectedFilter == 'pending',
                  onTap: () => setState(() => _selectedFilter = 'pending'),
                ),
                _FilterChip(
                  label: 'In Progress',
                  isSelected: _selectedFilter == 'in_progress',
                  onTap: () => setState(() => _selectedFilter = 'in_progress'),
                ),
                _FilterChip(
                  label: 'Completed',
                  isSelected: _selectedFilter == 'completed',
                  onTap: () => setState(() => _selectedFilter = 'completed'),
                ),
              ],
            ),
          ),

          // Task List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredTasks.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadTasks,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredTasks.length,
                          itemBuilder: (context, index) {
                            final task = filteredTasks[index];
                            return _TaskCard(
                              task: task,
                              priorityColor: _getPriorityColor(task.priority),
                              statusIcon: _getStatusIcon(task.status),
                              onTap: () => context.pushNamed(
                                'task-detail',
                                pathParameters: {'id': task.id},
                              ),
                              onToggle: () {
                                // TODO: Toggle task status
                              },
                            );
                          },
                        ),
                      ),
          ),
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
            Icon(
              LucideIcons.squareCheck,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Tasks',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a task to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final Color priorityColor;
  final IconData statusIcon;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _TaskCard({
    required this.task,
    required this.priorityColor,
    required this.statusIcon,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == TaskStatus.completed;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(
                  statusIcon,
                  color: isCompleted ? context.successColor : context.textTertiary,
                ),
                onPressed: onToggle,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: isCompleted ? context.textTertiary : null,
                          ),
                    ),
                    if (task.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: priorityColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.priority.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: priorityColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (task.dueDate != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.calendar,
                            size: 12,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d').format(task.dueDate!),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: context.textTertiary,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
