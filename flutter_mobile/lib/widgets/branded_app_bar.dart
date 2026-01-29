import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Branded app bar with AMOS Labs logo.
/// Use this on all screens for consistent navigation.
class BrandedAppBar extends ConsumerWidget implements PreferredSizeWidget {
  /// Optional title to show instead of logo (for sub-screens)
  final String? title;

  /// Whether to show the back button
  final bool showBackButton;

  /// Optional trailing actions
  final List<Widget>? actions;

  const BrandedAppBar({
    super.key,
    this.title,
    this.showBackButton = false,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      automaticallyImplyLeading: showBackButton,
      titleSpacing: showBackButton ? 0 : 12,
      title: title != null
          ? Text(title!)
          : Image.asset(
              'assets/images/logo-header.png',
              height: 28,
              fit: BoxFit.contain,
            ),
      actions: actions,
    );
  }
}
