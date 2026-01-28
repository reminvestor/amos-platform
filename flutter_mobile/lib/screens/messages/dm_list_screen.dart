import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/hub_service.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';
import 'package:amos_mobile/utils/error_handler.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';

/// List of direct message conversations - like iMessage main screen
class DmListScreen extends ConsumerStatefulWidget {
  const DmListScreen({super.key});

  @override
  ConsumerState<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends ConsumerState<DmListScreen> with ErrorHandler {
  final HubService _hubService = HubService();

  List<DmThread> _threads = [];
  List<TeamMember> _teamMembers = [];
  List<HubAgent> _agents = [];
  List<TeamChannel> _channels = [];
  bool _isLoading = true;
  String? _error;

  // Section expansion state
  bool _channelsExpanded = true;
  bool _teamExpanded = false;
  bool _messagesExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load channels, DM threads, team members, and agents in parallel
      final futures = await Future.wait([
        _hubService.getChannels(),
        _hubService.getDmThreads(),
        _hubService.getTeamMembers(),
        _loadAgents(),
      ]);

      if (mounted) {
        final channels = futures[0] as List<TeamChannel>;
        final threads = futures[1] as List<DmThread>;
        final members = futures[2] as List<TeamMember>;
        final agents = futures[3] as List<HubAgent>;

        AppLogger.info('Loaded ${channels.length} channels, ${threads.length} DM threads, ${members.length} team members, ${agents.length} agents');
        for (final m in members) {
          AppLogger.info('Team member: id=${m.id}, userId=${m.userId}, name=${m.fullName}');
        }

        setState(() {
          _channels = channels;
          _threads = threads;
          _teamMembers = members;
          _agents = agents;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load messages', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<List<HubAgent>> _loadAgents() async {
    try {
      final response = await _hubService.getHubAgents();
      return response.map((json) => HubAgent.fromJson(json)).toList();
    } catch (e) {
      AppLogger.error('Failed to load agents: $e');
      return [];
    }
  }

  Future<void> _startDmWithRecipient({
    required String participantType,
    required int participantId,
    required String displayName,
    String? initialMessage,
  }) async {
    AppLogger.info('Starting DM with: type=$participantType, id=$participantId, name=$displayName');

    try {
      // Create or get existing DM thread
      final dmThread = await _hubService.createDm(
        participantType: participantType,
        participantId: participantId,
        initialMessage: initialMessage,
      );

      AppLogger.info('Created/found DM thread: id=${dmThread.id}');

      if (mounted) {
        AppLogger.info('Navigating to dm-chat with threadId=${dmThread.id}');
        context.pushNamed(
          'dm-chat',
          pathParameters: {'threadId': dmThread.id.toString()},
          extra: displayName,
        );
      } else {
        AppLogger.warning('Widget not mounted after createDm, skipping navigation');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to start DM', error: e, stackTrace: stackTrace);
      if (mounted) showError(context, e);
    }
  }

  void _showNewDmSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NewDmSheet(
        teamMembers: _teamMembers,
        agents: _agents,
        onSelectRecipient: (type, id, name, message) {
          Navigator.pop(context);
          _startDmWithRecipient(
            participantType: type,
            participantId: id,
            displayName: name,
            initialMessage: message,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to realtime updates for unread counts
    // ignore: unused_local_variable
    final _ = ref.watch(realtimeProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewDmSheet,
        tooltip: 'New Message',
        child: const Icon(LucideIcons.squarePen),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text('Failed to load messages'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Channels Section
          _buildExpandableSection(
            icon: LucideIcons.hash,
            title: 'Channels',
            count: _channels.length,
            isExpanded: _channelsExpanded,
            onToggle: () => setState(() => _channelsExpanded = !_channelsExpanded),
            children: _channels.map((channel) => _ChannelTile(
              channel: channel,
              onTap: () {
                // Navigate to channel chat using the channel's main thread
                if (channel.mainThreadId != null) {
                  context.pushNamed(
                    'dm-chat',
                    pathParameters: {'threadId': channel.mainThreadId.toString()},
                    extra: '#${channel.name}',
                  );
                } else {
                  // Create or get channel thread
                  _openChannelChat(channel);
                }
              },
            )).toList(),
          ),

          // Team Section
          _buildExpandableSection(
            icon: LucideIcons.users,
            title: 'Team',
            count: _teamMembers.length,
            isExpanded: _teamExpanded,
            onToggle: () => setState(() => _teamExpanded = !_teamExpanded),
            children: _teamMembers.map((member) => _TeamMemberTile(
              member: member,
              onTap: () => _startDmWithRecipient(
                participantType: 'User',
                participantId: member.userId,
                displayName: member.fullName,
              ),
            )).toList(),
          ),

          // Direct Messages Section
          _buildExpandableSection(
            icon: LucideIcons.messageSquare,
            title: 'Direct Messages',
            count: _threads.length,
            isExpanded: _messagesExpanded,
            onToggle: () => setState(() => _messagesExpanded = !_messagesExpanded),
            emptyMessage: 'No messages yet. Tap + to start a conversation.',
            children: _threads.map((thread) => _DmThreadTile(
              thread: thread,
              onTap: () {
                context.pushNamed(
                  'dm-chat',
                  pathParameters: {'threadId': thread.id.toString()},
                  extra: thread.displayName,
                );
              },
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection({
    required IconData icon,
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    String? emptyMessage,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        // Section Content
        if (isExpanded) ...[
          if (children.isEmpty && emptyMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                emptyMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...children,
        ],
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _openChannelChat(TeamChannel channel) async {
    try {
      // Get channel messages - this will also return the thread ID
      final response = await _hubService.getChannelMessages(channel.id);
      if (mounted) {
        context.pushNamed(
          'dm-chat',
          pathParameters: {'threadId': response.threadId.toString()},
          extra: '#${channel.name}',
        );
      }
    } catch (e) {
      AppLogger.error('Failed to open channel: $e');
      if (mounted) showError(context, e);
    }
  }
}

/// Individual DM thread tile - iMessage style
class _DmThreadTile extends StatelessWidget {
  final DmThread thread;
  final VoidCallback onTap;

  const _DmThreadTile({
    required this.thread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = thread.unreadCount > 0;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _buildAvatar(context),
      title: Row(
        children: [
          Expanded(
            child: Text(
              thread.displayName,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatTime(thread.lastActivityAt),
            style: TextStyle(
              fontSize: 12,
              color: hasUnread ? theme.colorScheme.primary : Colors.grey,
              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              thread.lastMessage ?? 'No messages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread ? theme.colorScheme.onSurface : Colors.grey,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          if (hasUnread) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                thread.unreadCount > 99 ? '99+' : thread.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: hasUnread
          ? null
          : Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: Colors.grey.shade400,
            ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final isAgent = thread.otherParticipant?.isAgent ?? false;
    final initial = thread.displayName.isNotEmpty
        ? thread.displayName[0].toUpperCase()
        : 'U';

    return CircleAvatar(
      radius: 24,
      backgroundColor: isAgent ? Colors.purple.shade100 : Colors.blue.shade100,
      child: isAgent
          ? Icon(LucideIcons.bot, size: 22, color: Colors.purple.shade700)
          : Text(
              initial,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.difference(dateTime).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dateTime.weekday - 1];
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}

/// Channel tile for team channels
class _ChannelTile extends StatelessWidget {
  final TeamChannel channel;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = channel.unreadCount > 0;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          _getChannelIcon(),
          size: 18,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Row(
        children: [
          Text(
            '# ',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontWeight: FontWeight.normal,
            ),
          ),
          Expanded(
            child: Text(
              channel.name,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: channel.description != null
          ? Text(
              channel.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            )
          : null,
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                channel.unreadCount > 99 ? '99+' : channel.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: Colors.grey.shade400,
            ),
    );
  }

  IconData _getChannelIcon() {
    switch (channel.channelType) {
      case 'general':
        return LucideIcons.hash;
      case 'activity':
        return LucideIcons.activity;
      case 'private':
        return LucideIcons.lock;
      default:
        return LucideIcons.hash;
    }
  }
}

/// Team member tile
class _TeamMemberTile extends StatelessWidget {
  final TeamMember member;
  final VoidCallback onTap;

  const _TeamMemberTile({
    required this.member,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              member.initials,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
                fontSize: 14,
              ),
            ),
          ),
          // Online indicator
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: member.isOnline ? Colors.green : Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        member.fullName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        member.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: Icon(
        LucideIcons.messageSquare,
        size: 18,
        color: Colors.grey.shade400,
      ),
    );
  }
}

/// Hub Agent model for messaging
class HubAgent {
  final int id;
  final String name;
  final String? description;
  final String? iconUrl;
  final bool isActive;

  HubAgent({
    required this.id,
    required this.name,
    this.description,
    this.iconUrl,
    this.isActive = true,
  });

  factory HubAgent.fromJson(Map<String, dynamic> json) {
    return HubAgent(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      iconUrl: json['icon_url'],
      isActive: json['is_active'] ?? json['status'] == 'active',
    );
  }
}

/// Bottom sheet for starting new DM - tap to select and open chat directly
class _NewDmSheet extends StatefulWidget {
  final List<TeamMember> teamMembers;
  final List<HubAgent> agents;
  final Function(String type, int id, String name, String? message) onSelectRecipient;

  const _NewDmSheet({
    required this.teamMembers,
    required this.agents,
    required this.onSelectRecipient,
  });

  @override
  State<_NewDmSheet> createState() => _NewDmSheetState();
}

class _NewDmSheetState extends State<_NewDmSheet> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HubAgent> get _filteredAgents {
    if (_searchQuery.isEmpty) return widget.agents;
    return widget.agents
        .where((a) => a.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<TeamMember> get _filteredMembers {
    if (_searchQuery.isEmpty) return widget.teamMembers;
    return widget.teamMembers
        .where((m) =>
            m.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            m.email.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'New Message',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search agents or team members...',
                  prefixIcon: const Icon(LucideIcons.search, size: 20),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),

            // Recipients list
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // Agents Section
                  if (_filteredAgents.isNotEmpty) ...[
                    _SectionHeader(
                      icon: LucideIcons.bot,
                      title: 'Agents',
                      count: _filteredAgents.length,
                    ),
                    ..._filteredAgents.map((agent) => _RecipientTile(
                      icon: LucideIcons.bot,
                      iconColor: Colors.purple,
                      name: agent.name,
                      subtitle: agent.description ?? 'AI Agent',
                      isOnline: agent.isActive,
                      onTap: () => widget.onSelectRecipient('AgentPlugin', agent.id, agent.name, null),
                    )),
                    const SizedBox(height: 8),
                  ],

                  // Team Members Section
                  if (_filteredMembers.isNotEmpty) ...[
                    _SectionHeader(
                      icon: LucideIcons.users,
                      title: 'Team Members',
                      count: _filteredMembers.length,
                    ),
                    ..._filteredMembers.map((member) => _RecipientTile(
                      initials: member.initials,
                      name: member.fullName,
                      subtitle: member.email,
                      isOnline: member.isOnline,
                      onTap: () {
                        AppLogger.info('Tapped on team member: ${member.fullName}, userId=${member.userId}');
                        widget.onSelectRecipient('User', member.userId, member.fullName, null);
                      },
                    )),
                  ],

                  // Empty state
                  if (_filteredAgents.isEmpty && _filteredMembers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(LucideIcons.searchX, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No results found',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header for recipient groups
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recipient tile for agents and team members
class _RecipientTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String? initials;
  final String name;
  final String subtitle;
  final bool isOnline;
  final VoidCallback onTap;

  const _RecipientTile({
    this.icon,
    this.iconColor,
    this.initials,
    required this.name,
    required this.subtitle,
    required this.isOnline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAgent = icon != null;

    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: isAgent
                ? (iconColor ?? Colors.purple).withValues(alpha: 0.15)
                : Colors.blue.shade100,
            child: isAgent
                ? Icon(icon, size: 20, color: iconColor ?? Colors.purple)
                : Text(
                    initials ?? '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
          ),
          // Online indicator
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade600,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: Colors.grey.shade400,
      ),
    );
  }
}
