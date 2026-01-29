import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    // Navigation (4 tabs): Amos, Messages, Toolbox, Profile
    if (location.startsWith('/chat')) return 0;
    if (location.startsWith('/messages') || location.startsWith('/dm')) return 1;
    // Toolbox contains: Scanner, Notes, Inbox, Tasks, Documents, Contacts
    if (location.startsWith('/tools') ||
        location.startsWith('/scanner') ||
        location.startsWith('/personal-notes') ||
        location.startsWith('/inbox') ||
        location.startsWith('/tasks') ||
        location.startsWith('/documents') ||
        location.startsWith('/contacts')) return 2;
    if (location.startsWith('/profile') ||
        location.startsWith('/settings') ||
        location.startsWith('/more')) return 3;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed('chat');
        break;
      case 1:
        context.goNamed('messages');
        break;
      case 2:
        context.goNamed('tools-hub');
        break;
      case 3:
        context.goNamed('profile');
        break;
    }
  }

  List<NavigationDestination> _getNavigationDestinations() {
    return const [
      NavigationDestination(
        icon: Icon(LucideIcons.bot, size: 22),
        selectedIcon: Icon(LucideIcons.bot, size: 22),
        label: 'Amos',
      ),
      NavigationDestination(
        icon: Icon(LucideIcons.messagesSquare, size: 22),
        selectedIcon: Icon(LucideIcons.messagesSquare, size: 22),
        label: 'Messages',
      ),
      NavigationDestination(
        icon: Icon(LucideIcons.briefcase, size: 22),
        selectedIcon: Icon(LucideIcons.briefcase, size: 22),
        label: 'Toolbox',
      ),
      NavigationDestination(
        icon: Icon(LucideIcons.user, size: 22),
        selectedIcon: Icon(LucideIcons.user, size: 22),
        label: 'Profile',
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => _onItemTapped(context, index),
        destinations: _getNavigationDestinations(),
      ),
    );
  }
}
