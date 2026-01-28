import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    // Unified navigation (4 tabs): Amos, Notes, Messages, Inbox
    if (location.startsWith('/chat')) return 0;
    if (location.startsWith('/personal-notes')) return 1;
    if (location.startsWith('/messages') || location.startsWith('/dm')) return 2;
    if (location.startsWith('/inbox') || location.startsWith('/more') || location.startsWith('/settings') || location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
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
  }

  List<NavigationDestination> _getNavigationDestinations() {
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
