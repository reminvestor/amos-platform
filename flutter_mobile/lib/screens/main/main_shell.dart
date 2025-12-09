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
    if (location.startsWith('/inbox')) return 1;
    if (location.startsWith('/home')) return 2;
    if (location.startsWith('/agents')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed('chat');
        break;
      case 1:
        context.goNamed('inbox');
        break;
      case 2:
        context.goNamed('home');
        break;
      case 3:
        context.goNamed('agents');
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
            icon: Icon(LucideIcons.messageSquare),
            selectedIcon: Icon(LucideIcons.messageSquare),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.inbox),
            selectedIcon: Icon(LucideIcons.inbox),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.layoutGrid),
            selectedIcon: Icon(LucideIcons.layoutGrid),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.bot),
            selectedIcon: Icon(LucideIcons.bot),
            label: 'Agents',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.settings),
            selectedIcon: Icon(LucideIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
