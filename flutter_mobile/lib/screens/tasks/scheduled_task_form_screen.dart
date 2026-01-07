import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/scheduled_task.dart';
import 'package:amos_mobile/services/scheduled_tasks_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class ScheduledTaskFormScreen extends ConsumerStatefulWidget {
  final String? taskId;

  const ScheduledTaskFormScreen({super.key, this.taskId});

  @override
  ConsumerState<ScheduledTaskFormScreen> createState() => _ScheduledTaskFormScreenState();
}

class _ScheduledTaskFormScreenState extends ConsumerState<ScheduledTaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ScheduledTasksService();

  // Form controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _promptController = TextEditingController();

  // Form state
  bool _isLoading = false;
  bool _isSaving = false;
  List<TaskType> _taskTypes = [];
  String? _selectedTaskType;
  String _scheduleType = 'daily';
  TimeOfDay _runAtTime = const TimeOfDay(hour: 9, minute: 0);
  int _runOnDay = 1; // Day of week (1-7) or day of month (1-31)
  int? _maxRuns;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadTaskTypes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadTaskTypes() async {
    setState(() => _isLoading = true);
    try {
      final types = await _service.getTaskTypes();
      setState(() {
        _taskTypes = types;
        if (types.isNotEmpty) {
          _selectedTaskType = types.first.id;
        }
      });
    } catch (e) {
      AppLogger.error('Failed to load task types', error: e);
      // Use default task type if API fails
      setState(() {
        _selectedTaskType = 'general';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTaskType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a task type')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final timeString = '${_runAtTime.hour.toString().padLeft(2, '0')}:${_runAtTime.minute.toString().padLeft(2, '0')}';

      await _service.createScheduledTask(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        taskType: _selectedTaskType!,
        prompt: _promptController.text.trim(),
        scheduleType: _scheduleType,
        runAtTime: timeString,
        runOnDay: _scheduleType == 'weekly' || _scheduleType == 'monthly' ? _runOnDay : null,
        maxRuns: _maxRuns,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task scheduled successfully'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      AppLogger.error('Failed to create scheduled task', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create task: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskId != null ? 'Edit Task' : 'New Scheduled Task'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveTask,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Task Name
                  _buildSectionTitle('Task Details'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Task Name',
                      hintText: 'e.g., Daily Report Generation',
                      prefixIcon: Icon(LucideIcons.tag),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a task name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'What does this task do?',
                      prefixIcon: Icon(LucideIcons.fileText),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // Task Type
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTaskType,
                    decoration: const InputDecoration(
                      labelText: 'Task Type',
                      prefixIcon: Icon(LucideIcons.layers),
                    ),
                    items: _taskTypes.isEmpty
                        ? [
                            const DropdownMenuItem(
                              value: 'general',
                              child: Text('General Task'),
                            ),
                          ]
                        : _taskTypes.map((type) {
                            return DropdownMenuItem(
                              value: type.id,
                              child: Text(type.name),
                            );
                          }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedTaskType = value);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Prompt
                  _buildSectionTitle('AI Instructions'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _promptController,
                    decoration: const InputDecoration(
                      labelText: 'What should the AI do?',
                      hintText: 'e.g., Generate a summary of yesterday\'s campaign performance',
                      prefixIcon: Icon(LucideIcons.sparkles),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter instructions for the AI';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Schedule
                  _buildSectionTitle('Schedule'),
                  const SizedBox(height: 12),
                  _buildScheduleTypeSelector(),
                  const SizedBox(height: 16),

                  // Time Picker
                  _buildTimePicker(),
                  const SizedBox(height: 16),

                  // Day selector for weekly/monthly
                  if (_scheduleType == 'weekly') _buildDayOfWeekSelector(),
                  if (_scheduleType == 'monthly') _buildDayOfMonthSelector(),

                  const SizedBox(height: 24),

                  // Advanced Options
                  _buildAdvancedOptions(),

                  const SizedBox(height: 32),

                  // Save Button
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveTask,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.check),
                    label: Text(_isSaving ? 'Creating...' : 'Create Task'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildScheduleTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildScheduleChip('once', 'Once', LucideIcons.calendar),
        _buildScheduleChip('daily', 'Daily', LucideIcons.repeat),
        _buildScheduleChip('weekly', 'Weekly', LucideIcons.calendarDays),
        _buildScheduleChip('monthly', 'Monthly', LucideIcons.calendarRange),
      ],
    );
  }

  Widget _buildScheduleChip(String value, String label, IconData icon) {
    final isSelected = _scheduleType == value;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _scheduleType = value);
        }
      },
    );
  }

  Widget _buildTimePicker() {
    return InkWell(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _runAtTime,
        );
        if (time != null) {
          setState(() => _runAtTime = time);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.clock, color: context.textSecondary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Run at',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
                Text(
                  _runAtTime.format(context),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const Spacer(),
            Icon(LucideIcons.chevronRight, color: context.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildDayOfWeekSelector() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repeat on',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(7, (index) {
            final dayNum = index + 1;
            final isSelected = _runOnDay == dayNum;
            return ChoiceChip(
              label: Text(days[index]),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _runOnDay = dayNum);
                }
              },
            );
          }),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDayOfMonthSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day of month',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _runOnDay,
          decoration: const InputDecoration(
            prefixIcon: Icon(LucideIcons.calendar),
          ),
          items: List.generate(31, (index) {
            final day = index + 1;
            return DropdownMenuItem(
              value: day,
              child: Text('Day $day'),
            );
          }),
          onChanged: (value) {
            if (value != null) {
              setState(() => _runOnDay = value);
            }
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAdvancedOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Row(
            children: [
              Icon(
                _showAdvanced ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 20,
                color: context.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Advanced Options',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _maxRuns?.toString(),
            decoration: const InputDecoration(
              labelText: 'Max Runs (optional)',
              hintText: 'Leave empty for unlimited',
              prefixIcon: Icon(LucideIcons.hash),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                _maxRuns = int.tryParse(value);
              });
            },
          ),
        ],
      ],
    );
  }
}
