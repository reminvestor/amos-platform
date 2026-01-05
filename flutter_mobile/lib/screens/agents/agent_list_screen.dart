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
  final _searchController = TextEditingController();
  String? _error;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Schedule load after first frame to ensure widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAgents();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Agent> _filterAgents(List<Agent> agents) {
    if (_searchQuery.isEmpty) return agents;
    final query = _searchQuery.toLowerCase();
    return agents.where((agent) {
      return agent.name.toLowerCase().contains(query) ||
          agent.description.toLowerCase().contains(query) ||
          agent.agentType.displayName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _loadAgents() async {
    try {
      ref.read(agentsLoadingProvider.notifier).setLoading(true);
    } catch (e) {
      AppLogger.error('Error setting loading state', error: e);
    }

    if (!mounted) return;
    setState(() => _error = null);

    try {
      final agents = await _agentsService.getAgents();
      ref.read(agentsProvider.notifier).setAgents(agents);
    } catch (e) {
      AppLogger.error('Failed to load agents', error: e);
      setState(() => _error = e.toString());
    } finally {
      ref.read(agentsLoadingProvider.notifier).setLoading(false);
    }
  }

  IconData _getAgentIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      // Role-based icons from API
      case 'play-circle':
        return LucideIcons.circlePlay;
      case 'clipboard-list':
        return LucideIcons.clipboardList;
      case 'chart-line':
        return LucideIcons.chartLine;
      case 'check-circle':
        return LucideIcons.circleCheck;
      case 'wrench':
        return LucideIcons.wrench;
      case 'robot':
      case 'bot':
        return LucideIcons.bot;
      // Additional icons for custom agents
      case 'pen-tool':
      case 'pentool':
        return LucideIcons.penTool;
      case 'mail':
        return LucideIcons.mail;
      case 'bar-chart':
      case 'barchart':
        return LucideIcons.chartBar;
      case 'layout':
        return LucideIcons.layoutGrid;
      case 'users':
        return LucideIcons.users;
      case 'zap':
        return LucideIcons.zap;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'brain':
        return LucideIcons.brain;
      case 'cog':
      case 'settings':
        return LucideIcons.settings;
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
    final filteredAgents = _filterAgents(agents);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search agents...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: context.textSecondary),
                ),
                style: Theme.of(context).textTheme.bodyLarge,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              )
            : const Text('Agents'),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_isSearching && _searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            )
          else if (!_isSearching)
            IconButton(
              icon: const Icon(LucideIcons.search),
              onPressed: () {
                setState(() => _isSearching = true);
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
                  : filteredAgents.isEmpty
                      ? _buildNoResultsState()
                      : RefreshIndicator(
                          onRefresh: _loadAgents,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredAgents.length,
                            itemBuilder: (context, index) {
                              final agent = filteredAgents[index];
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

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.searchX,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Results Found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'No agents match "$_searchQuery"',
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
