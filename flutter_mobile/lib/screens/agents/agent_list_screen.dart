import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/agent.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/services/agents_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class AgentListScreen extends ConsumerStatefulWidget {
  const AgentListScreen({super.key});

  @override
  ConsumerState<AgentListScreen> createState() => _AgentListScreenState();
}

class _AgentListScreenState extends ConsumerState<AgentListScreen> {
  final _agentsService = AgentsService();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Schedule load after first frame to ensure widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: avoid_print
      print('[AgentList] Post frame callback, calling _loadAgents');
      _loadAgents();
    });
  }

  Future<void> _loadAgents() async {
    // ignore: avoid_print
    print('[AgentList] _loadAgents started, mounted=$mounted');
    try {
      ref.read(agentsLoadingProvider.notifier).setLoading(true);
      // ignore: avoid_print
      print('[AgentList] Set loading to true');
    } catch (e) {
      // ignore: avoid_print
      print('[AgentList] Error setting loading: $e');
    }

    if (!mounted) {
      // ignore: avoid_print
      print('[AgentList] Widget not mounted, returning');
      return;
    }
    setState(() => _error = null);
    // ignore: avoid_print
    print('[AgentList] Cleared error state');

    try {
      // ignore: avoid_print
      print('[AgentList] Calling agentsService.getAgents()');
      final agents = await _agentsService.getAgents();
      // ignore: avoid_print
      print('[AgentList] Got ${agents.length} agents');
      ref.read(agentsProvider.notifier).setAgents(agents);
      AppLogger.info('Loaded ${agents.length} agents');
    } catch (e) {
      // ignore: avoid_print
      print('[AgentList] Error: $e');
      AppLogger.error('Failed to load agents', error: e);
      setState(() => _error = e.toString());
    } finally {
      // ignore: avoid_print
      print('[AgentList] Setting loading to false');
      ref.read(agentsLoadingProvider.notifier).setLoading(false);
    }
  }

  IconData _getAgentIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'pentool':
      case 'pen-tool':
        return LucideIcons.penTool;
      case 'mail':
        return LucideIcons.mail;
      case 'barchart':
      case 'bar-chart':
      case 'chart-line':
        return LucideIcons.chartBar;
      case 'layout':
        return LucideIcons.layoutGrid;
      case 'play-circle':
        return LucideIcons.circlePlay;
      case 'clipboard-list':
        return LucideIcons.clipboardList;
      case 'check-circle':
        return LucideIcons.circleCheck;
      case 'wrench':
        return LucideIcons.wrench;
      case 'robot':
      case 'bot':
        return LucideIcons.bot;
      default:
        return LucideIcons.bot;
    }
  }

  Color _getAgentColor(AgentType type) {
    switch (type) {
      case AgentType.executor:
        return Colors.blue;
      case AgentType.planner:
        return Colors.purple;
      case AgentType.analyst:
        return Colors.green;
      case AgentType.verifier:
        return Colors.teal;
      case AgentType.fixer:
        return Colors.orange;
      case AgentType.architect:
        return Colors.indigo;
      case AgentType.engineer:
        return Colors.cyan;
      case AgentType.custom:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentsProvider);
    final isLoading = ref.watch(agentsLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.search),
            onPressed: () {
              // TODO: Search
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : agents.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                  onRefresh: _loadAgents,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: agents.length,
                    itemBuilder: (context, index) {
                      final agent = agents[index];
                      return _AgentCard(
                        agent: agent,
                        icon: _getAgentIcon(agent.icon),
                        color: _getAgentColor(agent.agentType),
                        onTap: () => context.pushNamed(
                          'agent-detail',
                          pathParameters: {'id': agent.id},
                        ),
                      );
                    },
                  ),
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
              LucideIcons.bot,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Agents Available',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'AI agents will appear here once they are configured.',
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Agents',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAgents,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AgentCard({
    required this.agent,
    required this.icon,
    required this.color,
    required this.onTap,
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            agent.name,
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Role badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            agent.agentType.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        if (agent.interactive) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Interactive',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: context.primaryColor,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      agent.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
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
      ),
    );
  }
}
