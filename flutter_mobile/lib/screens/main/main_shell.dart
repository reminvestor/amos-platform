import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    // Chat-first architecture: Chat is index 0
    if (location.startsWith('/chat')) return 0;
    if (location.startsWith('/home') || location.startsWith('/marketplace')) return 1;
    if (location.startsWith('/contacts')) return 2;
    if (location.startsWith('/inbox')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed('chat');
        break;
      case 1:
        context.goNamed('home');
        break;
      case 2:
        context.goNamed('contacts');
        break;
      case 3:
        context.goNamed('inbox');
        break;
      case 4:
        context.goNamed('settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => _onItemTapped(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.messageSquare, size: 22),
            selectedIcon: Icon(LucideIcons.messageSquare, size: 22),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.layoutGrid, size: 22),
            selectedIcon: Icon(LucideIcons.layoutGrid, size: 22),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.users, size: 22),
            selectedIcon: Icon(LucideIcons.users, size: 22),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.inbox, size: 22),
            selectedIcon: Icon(LucideIcons.inbox, size: 22),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.settings, size: 22),
            selectedIcon: Icon(LucideIcons.settings, size: 22),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
