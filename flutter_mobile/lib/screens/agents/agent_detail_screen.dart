import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/agent.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/services/agents_service.dart';

class AgentDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const AgentDetailScreen({super.key, required this.id});

  @override
  ConsumerState<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends ConsumerState<AgentDetailScreen> {
  final _taskController = TextEditingController();
  final _agentsService = AgentsService();
  bool _isExecuting = false;
  Agent? _fullAgent;
  String? _result;

  // Model selection state
  double _modelPower = 50;
  // ignore: unused_field - Will be used when API call is implemented
  String _selectedModel = 'claude-3-5-sonnet';
  String _selectedModelName = 'Claude 3.5 Sonnet';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAgentDetails();
    });
  }

  Future<void> _loadAgentDetails() async {
    try {
      final agent = await _agentsService.getAgent(widget.id);
      if (mounted) {
        setState(() {
          _fullAgent = agent;
        });
      }
    } catch (e) {
      // Error handled silently - UI uses _fullAgent == null to show fallback
    }
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _updateModelFromPower(double power) {
    setState(() {
      _modelPower = power;
      if (power <= 12.5) {
        _selectedModel = 'claude-3-haiku';
        _selectedModelName = 'Claude 3.5 Haiku';
      } else if (power <= 37.5) {
        _selectedModel = 'claude-haiku-4-5';
        _selectedModelName = 'Claude Haiku 4.5';
      } else if (power <= 75) {
        _selectedModel = 'claude-3-5-sonnet';
        _selectedModelName = 'Claude 3.5 Sonnet';
      } else {
        _selectedModel = 'claude-sonnet-4-5';
        _selectedModelName = 'Claude Sonnet 4.5';
      }
    });
  }

  void _selectPreset(double power, String model, String name) {
    setState(() {
      _modelPower = power;
      _selectedModel = model;
      _selectedModelName = name;
    });
  }

  Future<void> _executeAgent() async {
    if (_taskController.text.trim().isEmpty) return;

    setState(() {
      _isExecuting = true;
      _result = null;
    });

    // TODO: Implement actual API call with _selectedModel
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() {
      _isExecuting = false;
      _result = 'Task completed successfully using $_selectedModelName! Here is the generated content based on your request.';
    });
  }

  IconData _getAgentIcon(String iconName) {
    switch (iconName) {
      case 'PenTool':
        return LucideIcons.penTool;
      case 'Mail':
        return LucideIcons.mail;
      case 'BarChart':
        return LucideIcons.chartBar;
      case 'Layout':
        return LucideIcons.layoutGrid;
      default:
        return LucideIcons.bot;
    }
  }

  String _formatCapabilityName(String cap) {
    // Convert snake_case to Title Case
    return cap
        .split('_')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  void _showModelSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ModelSelectorSheet(
        currentPower: _modelPower,
        currentModelName: _selectedModelName,
        onPowerChanged: _updateModelFromPower,
        onPresetSelected: _selectPreset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use full agent details if loaded, otherwise fallback to list data
    final agents = ref.watch(agentsProvider);
    final listAgent = agents.firstWhere(
      (a) => a.id == widget.id,
      orElse: () => Agent(
        id: widget.id,
        name: 'Unknown Agent',
        description: '',
        agentType: AgentType.custom,
        interactive: false,
        icon: 'Bot',
        createdAt: DateTime.now(),
      ),
    );
    final agent = _fullAgent ?? listAgent;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(agent.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getAgentIcon(agent.icon),
                    color: context.primaryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          agent.agentType.displayName,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              agent.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),

            // Capabilities Section
            if (agent.capabilities != null && agent.capabilities!.isNotEmpty) ...[
              Text(
                'Capabilities',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: agent.capabilities!.map((cap) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: context.primaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.sparkles,
                          size: 14,
                          color: context.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatCapabilityName(cap),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // Tools Section
            if (agent.tools != null && agent.tools!.isNotEmpty) ...[
              Text(
                'Tools',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: agent.tools!.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: context.borderColor,
                  ),
                  itemBuilder: (context, index) {
                    final tool = agent.tools![index];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tool.required
                              ? context.primaryColor.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          LucideIcons.wrench,
                          size: 16,
                          color: tool.required
                              ? context.primaryColor
                              : context.textSecondary,
                        ),
                      ),
                      title: Text(
                        tool.displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      subtitle: Text(
                        tool.name,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textTertiary,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                      ),
                      trailing: tool.required
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Required',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: context.primaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Model Selector
            Text(
              'Model Selection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _ModelSelectorButton(
              modelName: _selectedModelName,
              power: _modelPower,
              onTap: _showModelSelector,
            ),
            const SizedBox(height: 24),

            // Task Input
            Text(
              'What would you like me to do?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _taskController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe your task...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isExecuting ? null : _executeAgent,
                icon: _isExecuting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.play),
                label: Text(_isExecuting ? 'Running...' : 'Run Agent'),
              ),
            ),

            // Result
            if (_result != null) ...[
              const SizedBox(height: 24),
              Text(
                'Result',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.successColor.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.circleCheck,
                          color: context.successColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Completed',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: context.successColor,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _result!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Model selector button with brain icon
class _ModelSelectorButton extends StatelessWidget {
  final String modelName;
  final double power;
  final VoidCallback onTap;

  const _ModelSelectorButton({
    required this.modelName,
    required this.power,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate gradient color based on power
    final Color powerColor = Color.lerp(
      Colors.blue,
      Colors.purple,
      power / 100,
    )!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              powerColor.withOpacity(0.05),
              powerColor.withOpacity(0.1),
            ],
          ),
        ),
        child: Row(
          children: [
            // Brain icon with glow effect
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.withOpacity(0.2),
                    Colors.purple.withOpacity(0.2),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: powerColor.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                LucideIcons.brain,
                size: 24,
                color: powerColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modelName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Power: ${power.round()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: power / 100,
                            backgroundColor: context.borderColor,
                            valueColor: AlwaysStoppedAnimation(powerColor),
                            minHeight: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              color: context.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for model selection
class _ModelSelectorSheet extends StatefulWidget {
  final double currentPower;
  final String currentModelName;
  final ValueChanged<double> onPowerChanged;
  final void Function(double power, String model, String name) onPresetSelected;

  const _ModelSelectorSheet({
    required this.currentPower,
    required this.currentModelName,
    required this.onPowerChanged,
    required this.onPresetSelected,
  });

  @override
  State<_ModelSelectorSheet> createState() => _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends State<_ModelSelectorSheet> {
  late double _power;
  late String _modelName;

  @override
  void initState() {
    super.initState();
    _power = widget.currentPower;
    _modelName = widget.currentModelName;
  }

  void _updateFromSlider(double value) {
    setState(() {
      _power = value;
      if (value <= 12.5) {
        _modelName = 'Claude 3.5 Haiku';
      } else if (value <= 37.5) {
        _modelName = 'Claude Haiku 4.5';
      } else if (value <= 75) {
        _modelName = 'Claude 3.5 Sonnet';
      } else {
        _modelName = 'Claude Sonnet 4.5';
      }
    });
    widget.onPowerChanged(value);
  }

  void _selectPreset(double power, String model, String name) {
    setState(() {
      _power = power;
      _modelName = name;
    });
    widget.onPresetSelected(power, model, name);
  }

  @override
  Widget build(BuildContext context) {
    final powerColor = Color.lerp(Colors.blue, Colors.purple, _power / 100)!;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Header with brain icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.2),
                      Colors.purple.withOpacity(0.2),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: powerColor.withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  LucideIcons.brain,
                  size: 28,
                  color: powerColor,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model Selection',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    _modelName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Slider
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: powerColor,
                  inactiveTrackColor: context.borderColor,
                  thumbColor: powerColor,
                  overlayColor: powerColor.withOpacity(0.2),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: _power,
                  min: 0,
                  max: 100,
                  onChanged: _updateFromSlider,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Faster',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: powerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_power.round()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: powerColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Text(
                      'More Robust',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Preset buttons
          Column(
            children: [
              _PresetButton(
                label: 'Fastest',
                modelName: 'Claude 3.5 Haiku',
                isSelected: _power == 0,
                onTap: () => _selectPreset(0, 'claude-3-haiku', 'Claude 3.5 Haiku'),
              ),
              const SizedBox(height: 8),
              _PresetButton(
                label: 'Fast',
                modelName: 'Claude Haiku 4.5',
                isSelected: _power == 25,
                onTap: () => _selectPreset(25, 'claude-haiku-4-5', 'Claude Haiku 4.5'),
              ),
              const SizedBox(height: 8),
              _PresetButton(
                label: 'Balanced',
                modelName: 'Claude 3.5 Sonnet',
                isSelected: _power == 50,
                onTap: () => _selectPreset(50, 'claude-3-5-sonnet', 'Claude 3.5 Sonnet'),
              ),
              const SizedBox(height: 8),
              _PresetButton(
                label: 'Most Robust',
                modelName: 'Claude Sonnet 4.5',
                isSelected: _power == 100,
                onTap: () => _selectPreset(100, 'claude-sonnet-4-5', 'Claude Sonnet 4.5'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Info text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 16,
                  color: context.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Higher model power provides more accurate and nuanced responses but may be slower.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Done button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final String modelName;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetButton({
    required this.label,
    required this.modelName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.primaryColor : context.borderColor,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? context.primaryColor.withOpacity(0.05) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isSelected ? context.primaryColor : null,
                  ),
            ),
            Text(
              modelName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
