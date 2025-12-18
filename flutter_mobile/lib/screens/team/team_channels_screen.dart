import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/services/hub_service.dart';
import 'package:amos_mobile/widgets/space_switcher.dart';

/// Provider for team channels - only fetches when authenticated
final teamChannelsProvider = FutureProvider<List<TeamChannel>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (!authState.isAuthenticated) {
    return []; // Return empty if not authenticated
  }
  final hubService = HubService();
  return await hubService.getChannels();
});

/// Provider for DM threads - only fetches when authenticated
final dmThreadsProvider = FutureProvider<List<DmThread>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (!authState.isAuthenticated) {
    return []; // Return empty if not authenticated
  }
  final hubService = HubService();
  return await hubService.getDmThreads();
});

class TeamChannelsScreen extends ConsumerStatefulWidget {
  const TeamChannelsScreen({super.key});

  @override
  ConsumerState<TeamChannelsScreen> createState() => _TeamChannelsScreenState();
}

class _TeamChannelsScreenState extends ConsumerState<TeamChannelsScreen>
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Space'),
        centerTitle: false,
        actions: [
          const SpaceSwitcher(showLabel: false, compact: true),
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showCreateChannelDialog(context),
            tooltip: 'New Channel',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Channels'),
            Tab(text: 'Direct Messages'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChannelsList(),
          _buildDmsList(),
        ],
      ),
    );
  }

  Widget _buildChannelsList() {
    final channelsAsync = ref.watch(teamChannelsProvider);

    return channelsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load channels'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(teamChannelsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (channels) {
        if (channels.isEmpty) {
          return _buildEmptyChannels();
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(teamChannelsProvider);
          },
          child: ListView.builder(
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              return _ChannelListTile(
                channel: channel,
                onTap: () {
                  context.goNamed('team-chat', pathParameters: {
                    'channelId': channel.id.toString(),
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDmsList() {
    final dmsAsync = ref.watch(dmThreadsProvider);

    return dmsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load messages'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(dmThreadsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (dms) {
        if (dms.isEmpty) {
          return _buildEmptyDms();
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dmThreadsProvider);
          },
          child: ListView.builder(
            itemCount: dms.length,
            itemBuilder: (context, index) {
              final dm = dms[index];
              return _DmListTile(
                dm: dm,
                onTap: () {
                  context.goNamed('team-dm', pathParameters: {
                    'threadId': dm.id.toString(),
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyChannels() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.hash,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No channels yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a channel to start collaborating',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showCreateChannelDialog(context),
            icon: const Icon(LucideIcons.plus),
            label: const Text('Create Channel'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDms() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.messageCircle,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No direct messages',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation with a team member',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.goNamed('team-members'),
            icon: const Icon(LucideIcons.users),
            label: const Text('View Team'),
          ),
        ],
      ),
    );
  }

  void _showCreateChannelDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Channel name',
                hintText: 'e.g. general, marketing, support',
                prefixText: '# ',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What is this channel for?',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;

              final hubService = HubService();
              try {
                await hubService.createChannel(
                  name: nameController.text.trim(),
                  description: descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ref.invalidate(teamChannelsProvider);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create channel: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ChannelListTile extends StatelessWidget {
  final TeamChannel channel;
  final VoidCallback onTap;

  const _ChannelListTile({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = channel.unreadCount > 0;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            channel.displayIcon,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            channel.name,
            style: TextStyle(
              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (channel.isPrivate)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                LucideIcons.lock,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
      subtitle: channel.description != null
          ? Text(
              channel.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                channel.unreadCount.toString(),
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _DmListTile extends StatelessWidget {
  final DmThread dm;
  final VoidCallback onTap;

  const _DmListTile({
    required this.dm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = dm.unreadCount > 0;
    final isAgent = dm.otherParticipant?.isAgent ?? false;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isAgent
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        child: Text(
          dm.displayName.isNotEmpty ? dm.displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: isAgent
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              dm.displayName,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isAgent)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Agent',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: dm.lastMessage != null
          ? Text(
              dm.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (dm.lastActivityAt != null)
            Text(
              _formatTime(dm.lastActivityAt!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasUnread ? theme.colorScheme.primary : null,
              ),
            ),
          if (hasUnread)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                dm.unreadCount.toString(),
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${time.month}/${time.day}';
  }
}
