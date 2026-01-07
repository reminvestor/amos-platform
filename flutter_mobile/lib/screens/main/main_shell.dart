import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/providers/space_provider.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context, bool isTeamSpace, bool isPersonalSpace) {
    final location = GoRouterState.of(context).matchedLocation;

    if (isTeamSpace) {
      // Team Space navigation (4 tabs - settings moved to app bar)
      if (location.startsWith('/chat')) return 0;
      if (location.startsWith('/team-channels') || location.startsWith('/team-chat')) return 1;
      if (location.startsWith('/team-members')) return 2;
      if (location.startsWith('/inbox')) return 3;
      return 0;
    } else if (isPersonalSpace) {
      // Personal Space navigation (4 tabs - settings moved to app bar)
      if (location.startsWith('/chat')) return 0;
      if (location.startsWith('/personal-notes')) return 1;
      if (location.startsWith('/tasks')) return 2;
      if (location.startsWith('/inbox')) return 3;
      return 0;
    } else {
      // Workspace navigation (5 tabs)
      if (location.startsWith('/chat')) return 0;
      if (location.startsWith('/marketing') || location.startsWith('/campaigns') || location.startsWith('/templates') || location.startsWith('/pages')) return 1;
      if (location.startsWith('/contacts')) return 2;
      if (location.startsWith('/tools') || location.startsWith('/documents') || location.startsWith('/tasks') || location.startsWith('/agents') || location.startsWith('/home/analytics')) return 3;
      if (location.startsWith('/more') || location.startsWith('/settings')) return 4;
      return 0;
    }
  }

  void _onItemTapped(BuildContext context, WidgetRef ref, int index) {
    final spaceState = ref.read(spaceProvider);
    final isTeamSpace = spaceState.currentSpace.isTeam;
    final isPersonalSpace = spaceState.currentSpace.isPersonal;

    if (isTeamSpace) {
      // Team Space navigation
      switch (index) {
        case 0:
          context.goNamed('chat');
          break;
        case 1:
          context.goNamed('team-channels');
          break;
        case 2:
          context.goNamed('team-members');
          break;
        case 3:
          context.goNamed('inbox');
          break;
      }
    } else if (isPersonalSpace) {
      // Personal Space navigation
      switch (index) {
        case 0:
          context.goNamed('chat');
          break;
        case 1:
          context.goNamed('personal-notes');
          break;
        case 2:
          context.goNamed('tasks');
          break;
        case 3:
          context.goNamed('inbox');
          break;
      }
    } else {
      // Workspace navigation (5 tabs)
      switch (index) {
        case 0:
          context.goNamed('chat');
          break;
        case 1:
          context.goNamed('marketing-hub');
          break;
        case 2:
          context.goNamed('contacts');
          break;
        case 3:
          context.goNamed('tools-hub');
          break;
        case 4:
          context.goNamed('more');
          break;
      }
    }
  }

  List<NavigationDestination> _getNavigationDestinations(bool isTeamSpace, bool isPersonalSpace) {
    if (isTeamSpace) {
      return const [
        NavigationDestination(
          icon: Icon(LucideIcons.bot, size: 22),
          selectedIcon: Icon(LucideIcons.bot, size: 22),
          label: 'Amos',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.messagesSquare, size: 22),
          selectedIcon: Icon(LucideIcons.messagesSquare, size: 22),
          label: 'Channels',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.users, size: 22),
          selectedIcon: Icon(LucideIcons.users, size: 22),
          label: 'Team',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.inbox, size: 22),
          selectedIcon: Icon(LucideIcons.inbox, size: 22),
          label: 'Inbox',
        ),
      ];
    } else if (isPersonalSpace) {
      return const [
        NavigationDestination(
          icon: Icon(LucideIcons.bot, size: 22),
          selectedIcon: Icon(LucideIcons.bot, size: 22),
          label: 'Amos',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.stickyNote, size: 22),
          selectedIcon: Icon(LucideIcons.stickyNote, size: 22),
          label: 'Notes',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.listTodo, size: 22),
          selectedIcon: Icon(LucideIcons.listTodo, size: 22),
          label: 'Tasks',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.inbox, size: 22),
          selectedIcon: Icon(LucideIcons.inbox, size: 22),
          label: 'Inbox',
        ),
      ];
    } else {
      // Workspace (5 tabs)
      return const [
        NavigationDestination(
          icon: Icon(LucideIcons.bot, size: 22),
          selectedIcon: Icon(LucideIcons.bot, size: 22),
          label: 'Amos',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.megaphone, size: 22),
          selectedIcon: Icon(LucideIcons.megaphone, size: 22),
          label: 'Marketing',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.users, size: 22),
          selectedIcon: Icon(LucideIcons.users, size: 22),
          label: 'Contacts',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.wrench, size: 22),
          selectedIcon: Icon(LucideIcons.wrench, size: 22),
          label: 'Tools',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.menu, size: 22),
          selectedIcon: Icon(LucideIcons.menu, size: 22),
          label: 'More',
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceState = ref.watch(spaceProvider);
    final isTeamSpace = spaceState.currentSpace.isTeam;
    final isPersonalSpace = spaceState.currentSpace.isPersonal;
    final selectedIndex = _calculateSelectedIndex(context, isTeamSpace, isPersonalSpace);
    final unreadCount = ref.watch(unreadTeamMessagesProvider);

    // Note: Realtime connection is handled by realtimeProvider which
    // listens to authStateProvider and auto-connects when authenticated

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          // Clear unread when navigating to team channels
          if (isTeamSpace && index == 1) {
            ref.read(realtimeProvider.notifier).clearUnreadMessages();
          }
          _onItemTapped(context, ref, index);
        },
        destinations: _getNavigationDestinationsWithBadge(
          isTeamSpace,
          isPersonalSpace,
          unreadCount,
        ),
      ),
    );
  }

  List<NavigationDestination> _getNavigationDestinationsWithBadge(
    bool isTeamSpace,
    bool isPersonalSpace,
    int unreadCount,
  ) {
    if (isTeamSpace) {
      return [
        const NavigationDestination(
          icon: Icon(LucideIcons.bot, size: 22),
          selectedIcon: Icon(LucideIcons.bot, size: 22),
          label: 'Amos',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(LucideIcons.messagesSquare, size: 22),
          ),
          selectedIcon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(LucideIcons.messagesSquare, size: 22),
          ),
          label: 'Channels',
        ),
        const NavigationDestination(
          icon: Icon(LucideIcons.users, size: 22),
          selectedIcon: Icon(LucideIcons.users, size: 22),
          label: 'Team',
        ),
        const NavigationDestination(
          icon: Icon(LucideIcons.inbox, size: 22),
          selectedIcon: Icon(LucideIcons.inbox, size: 22),
          label: 'Inbox',
        ),
      ];
    }
    // For non-team spaces, use the regular destinations
    return _getNavigationDestinations(isTeamSpace, isPersonalSpace);
  }
}
