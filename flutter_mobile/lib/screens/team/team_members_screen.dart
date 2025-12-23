import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/hub_service.dart';
import 'package:amos_mobile/widgets/space_switcher.dart';

/// Provider for team members
final teamMembersProvider = FutureProvider<List<TeamMember>>((ref) async {
  final hubService = HubService();
  return await hubService.getTeamMembers();
});

/// Provider for hub agents
final hubAgentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final hubService = HubService();
  return await hubService.getHubAgents();
});

class TeamMembersScreen extends ConsumerStatefulWidget {
  const TeamMembersScreen({super.key});

  @override
  ConsumerState<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

class _TeamMembersScreenState extends ConsumerState<TeamMembersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team'),
        centerTitle: false,
        actions: [
          const SpaceSwitcher(showLabel: false, compact: true),
          IconButton(
            icon: const Icon(LucideIcons.userPlus),
            onPressed: () => _showInviteDialog(context),
            tooltip: 'Invite team member',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'People'),
            Tab(text: 'Agents'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMembersList(),
          _buildAgentsList(),
        ],
      ),
    );
  }

  Widget _buildMembersList() {
    final membersAsync = ref.watch(teamMembersProvider);

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load team members'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(teamMembersProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (members) {
        if (members.isEmpty) {
          return _buildEmptyMembers();
        }

        // Group by online status
        final online = members.where((m) => m.isOnline).toList();
        final offline = members.where((m) => !m.isOnline).toList();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(teamMembersProvider);
          },
          child: ListView(
            children: [
              if (online.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Online',
                  count: online.length,
                  color: Colors.green,
                ),
                ...online.map((member) => _MemberListTile(
                      member: member,
                      onTap: () => _startDm(member),
                    )),
              ],
              if (offline.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Offline',
                  count: offline.length,
                ),
                ...offline.map((member) => _MemberListTile(
                      member: member,
                      onTap: () => _startDm(member),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAgentsList() {
    final agentsAsync = ref.watch(hubAgentsProvider);

    return agentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load agents'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(hubAgentsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (agents) {
        if (agents.isEmpty) {
          return _buildEmptyAgents();
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(hubAgentsProvider);
          },
          child: ListView.builder(
            itemCount: agents.length,
            itemBuilder: (context, index) {
              final agent = agents[index];
              return _AgentListTile(
                agent: agent,
                onTap: () => _startAgentDm(agent),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyMembers() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.users,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No team members yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Invite people to collaborate',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showInviteDialog(context),
            icon: const Icon(LucideIcons.userPlus),
            label: const Text('Invite Team Member'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAgents() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.bot,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No agents available',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add agents from the marketplace',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  void _startDm(TeamMember member) async {
    try {
      final hubService = HubService();
      final dm = await hubService.createDm(
        participantType: 'User',
        participantId: member.id,
      );

      if (mounted) {
        context.goNamed('team-dm', pathParameters: {
          'threadId': dm.id.toString(),
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start conversation: $e')),
        );
      }
    }
  }

  void _startAgentDm(Map<String, dynamic> agent) async {
    try {
      final hubService = HubService();
      final dm = await hubService.createDm(
        participantType: 'AgentPlugin',
        participantId: agent['id'],
      );

      if (mounted) {
        context.goNamed('team-dm', pathParameters: {
          'threadId': dm.id.toString(),
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start conversation: $e')),
        );
      }
    }
  }

  void _showInviteDialog(BuildContext context) {
    final emailController = TextEditingController();
    String selectedRole = 'member';
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invite Team Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'colleague@company.com',
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role',
                ),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedRole = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter an email address')),
                        );
                        return;
                      }

                      setDialogState(() => isLoading = true);

                      try {
                        final hubService = HubService();
                        final result = await hubService.inviteTeamMember(
                          email: email,
                          role: selectedRole,
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['message'] ?? 'Invitation sent!'),
                            ),
                          );
                          // Refresh the team members list
                          ref.invalidate(teamMembersProvider);
                        }
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to send invite: $e')),
                          );
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Invite'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color? color;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

class _MemberListTile extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onTap;

  const _MemberListTile({
    required this.member,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage:
                member.avatarUrl != null ? NetworkImage(member.avatarUrl!) : null,
            child: member.avatarUrl == null
                ? Text(
                    member.initials,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          if (member.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(member.fullName),
      subtitle: Row(
        children: [
          if (member.role != null) ...[
            Text(member.role!),
            const Text(' • '),
          ],
          Text(
            member.isOnline ? 'Active now' : 'Offline',
            style: TextStyle(
              color: member.isOnline ? Colors.green : null,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(LucideIcons.messageCircle),
        onPressed: onTap,
        tooltip: 'Send message',
      ),
      onTap: onTap,
    );
  }
}

class _AgentListTile extends StatelessWidget {
  final Map<String, dynamic> agent;
  final VoidCallback onTap;

  const _AgentListTile({
    required this.agent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = agent['status'] ?? 'offline';
    final isOnline = status == 'online';

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.tertiaryContainer,
            child: Text(
              agent['icon'] ?? '🤖',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(agent['name'] ?? 'Agent'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'AI',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(agent['role'] ?? 'Assistant'),
          if (agent['current_activity'] != null)
            Text(
              agent['current_activity'],
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(LucideIcons.messageCircle),
        onPressed: onTap,
        tooltip: 'Send message',
      ),
      onTap: onTap,
    );
  }
}
