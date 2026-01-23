import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/providers/space_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context, bool isPersonalSpace) {
    final location = GoRouterState.of(context).matchedLocation;

    if (isPersonalSpace) {
      // Personal Space navigation (4 tabs)
      if (location.startsWith('/chat')) return 0;
      if (location.startsWith('/personal-notes')) return 1;
      if (location.startsWith('/messages') || location.startsWith('/dm')) return 2;
      if (location.startsWith('/inbox')) return 3;
      return 0;
    } else {
      // Operations navigation (4 tabs)
      if (location.startsWith('/chat')) return 0;
      if (location.startsWith('/tools') || location.startsWith('/documents') || location.startsWith('/agents')) return 1;
      if (location.startsWith('/messages') || location.startsWith('/dm')) return 2;
      if (location.startsWith('/more') || location.startsWith('/settings') || location.startsWith('/profile')) return 3;
      return 0;
    }
  }

  void _onItemTapped(BuildContext context, WidgetRef ref, int index) {
    final spaceState = ref.read(spaceProvider);
    final isPersonalSpace = spaceState.currentSpace.isPersonal;

    if (isPersonalSpace) {
      // Personal Space navigation
      switch (index) {
        case 0:
          context.goNamed('chat');
          break;
        case 1:
          context.goNamed('personal-notes');
          break;
        case 2:
          context.goNamed('messages');
          break;
        case 3:
          context.goNamed('inbox');
          break;
      }
    } else {
      // Operations navigation
      switch (index) {
        case 0:
          context.goNamed('chat');
          break;
        case 1:
          context.goNamed('tools-hub');
          break;
        case 2:
          context.goNamed('messages');
          break;
        case 3:
          context.goNamed('more');
          break;
      }
    }
  }

  List<NavigationDestination> _getNavigationDestinations(bool isPersonalSpace) {
    if (isPersonalSpace) {
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
          icon: Icon(LucideIcons.messagesSquare, size: 22),
          selectedIcon: Icon(LucideIcons.messagesSquare, size: 22),
          label: 'Messages',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.inbox, size: 22),
          selectedIcon: Icon(LucideIcons.inbox, size: 22),
          label: 'Inbox',
        ),
      ];
    } else {
      // Operations (4 tabs)
      return const [
        NavigationDestination(
          icon: Icon(LucideIcons.bot, size: 22),
          selectedIcon: Icon(LucideIcons.bot, size: 22),
          label: 'Amos',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.wrench, size: 22),
          selectedIcon: Icon(LucideIcons.wrench, size: 22),
          label: 'Tools',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.messagesSquare, size: 22),
          selectedIcon: Icon(LucideIcons.messagesSquare, size: 22),
          label: 'Messages',
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
    final isPersonalSpace = spaceState.currentSpace.isPersonal;
    final selectedIndex = _calculateSelectedIndex(context, isPersonalSpace);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => _onItemTapped(context, ref, index),
        destinations: _getNavigationDestinations(isPersonalSpace),
      ),
    );
  }
}
