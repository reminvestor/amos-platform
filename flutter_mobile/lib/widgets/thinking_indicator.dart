import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Thinking indicator widget that shows what Amos is doing
/// Similar to web's tool-thinking-window
class ThinkingIndicator extends StatefulWidget {
  final List<String> steps;
  final bool isVisible;
  final String? currentStatus;

  const ThinkingIndicator({
    super.key,
    this.steps = const [],
    this.isVisible = false,
    this.currentStatus,
  });

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedOpacity(
      opacity: widget.isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    Colors.purple.withOpacity(0.15),
                    Colors.blue.withOpacity(0.1),
                  ]
                : [
                    Colors.purple.withOpacity(0.08),
                    Colors.blue.withOpacity(0.05),
                  ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.purple.withOpacity(0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  topRight: Radius.circular(11),
                ),
              ),
              child: Row(
                children: [
                  _SpinningIcon(),
                  const SizedBox(width: 10),
                  Text(
                    'Amos is thinking...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.purple.shade300,
                    ),
                  ),
                ],
              ),
            ),

            // Steps list
            if (widget.steps.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 80),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.steps.length,
                  itemBuilder: (context, index) {
                    final isLatest = index == widget.steps.length - 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          _StepDot(isActive: isLatest),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.steps[index],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isLatest
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Current status (if different from steps)
            if (widget.currentStatus != null && widget.steps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    _StepDot(isActive: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.currentStatus!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Progress bar
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(11),
                bottomRight: Radius.circular(11),
              ),
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  return Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.withOpacity(0.2),
                          Colors.purple,
                          Colors.purple.shade300,
                          Colors.purple.withOpacity(0.2),
                        ],
                        stops: [
                          0.0,
                          _progressController.value,
                          _progressController.value + 0.1,
                          1.0,
                        ].map((v) => v.clamp(0.0, 1.0)).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spinning icon for the header
class _SpinningIcon extends StatefulWidget {
  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Icon(
            LucideIcons.loader,
            size: 16,
            color: Colors.purple.shade300,
          ),
        );
      },
    );
  }
}

/// Animated dot for step items
class _StepDot extends StatefulWidget {
  final bool isActive;

  const _StepDot({required this.isActive});

  @override
  State<_StepDot> createState() => _StepDotState();
}

class _StepDotState extends State<_StepDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StepDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.value = 0.5;
    }
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
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isActive
                ? Colors.purple.withOpacity(_animation.value)
                : Colors.purple.withOpacity(0.3),
          ),
        );
      },
    );
  }
}

/// Helper to format tool names for display
String formatToolName(String toolName) {
  // Map of tool names to friendly descriptions
  const toolDescriptions = {
    'get_data': 'Getting data...',
    'create_object': 'Creating...',
    'update_object': 'Updating...',
    'delete_object': 'Deleting...',
    'get_workflow_context': 'Loading context...',
    'manage_task_list': 'Managing tasks...',
    'generate_ai_landing_page': 'Generating landing page...',
    'send_email': 'Sending email...',
    'web_search': 'Searching the web...',
    'delegate_to_planner_tool': 'Planning workflow...',
    'list_connections': 'Listing connections...',
    'invoke_operation': 'Running operation...',
    'analyze_dataset': 'Analyzing data...',
    'recall_context': 'Recalling context...',
  };

  if (toolDescriptions.containsKey(toolName)) {
    return toolDescriptions[toolName]!;
  }

  // Convert snake_case to Title Case with "..."
  final words = toolName.split('_');
  final formatted = words.map((w) => w.isNotEmpty
    ? '${w[0].toUpperCase()}${w.substring(1)}'
    : w
  ).join(' ');
  return '$formatted...';
}
