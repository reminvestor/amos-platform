import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/providers/space_provider.dart';

/// Space switcher widget for the app bar
class SpaceSwitcher extends ConsumerWidget {
  final bool showLabel;
  final bool compact;

  const SpaceSwitcher({
    super.key,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceState = ref.watch(spaceProvider);
    final currentSpace = spaceState.currentSpace;
    final theme = Theme.of(context);

    return PopupMenuButton<Space>(
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (space) {
        ref.read(spaceProvider.notifier).switchSpace(space);
      },
      itemBuilder: (context) => Space.all.map((space) {
        final isSelected = space.slug == currentSpace.slug;
        return PopupMenuItem<Space>(
          value: space,
          child: Row(
            children: [
              _SpaceIcon(space: space, isSelected: isSelected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      space.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    if (space.description != null)
                      Text(
                        space.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  LucideIcons.check,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 8,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SpaceIcon(space: currentSpace, isSelected: true, size: compact ? 18 : 20),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(
                currentSpace.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: compact ? 14 : 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon for a space
class _SpaceIcon extends StatelessWidget {
  final Space space;
  final bool isSelected;
  final double size;

  const _SpaceIcon({
    required this.space,
    required this.isSelected,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color color;

    if (space.isPersonal) {
      icon = LucideIcons.user;
      color = isSelected ? theme.colorScheme.primary : Colors.blue;
    } else if (space.isOperations) {
      icon = LucideIcons.settings;
      color = isSelected ? theme.colorScheme.primary : Colors.purple;
    } else {
      icon = LucideIcons.circle;
      color = isSelected ? theme.colorScheme.primary : Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        icon,
        size: size,
        color: color,
      ),
    );
  }
}

/// Simple space icon button (for compact views)
class SpaceIconButton extends ConsumerWidget {
  final double size;
  final VoidCallback? onTap;

  const SpaceIconButton({
    super.key,
    this.size = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSpace = ref.watch(currentSpaceProvider);

    IconData icon;
    Color color;

    if (currentSpace.isPersonal) {
      icon = LucideIcons.user;
      color = Colors.blue;
    } else if (currentSpace.isOperations) {
      icon = LucideIcons.settings;
      color = Colors.purple;
    } else {
      icon = LucideIcons.circle;
      color = Colors.grey;
    }

    return IconButton(
      icon: Icon(icon, size: size, color: color),
      onPressed: onTap ?? () => _showSpacePicker(context, ref),
      tooltip: currentSpace.name,
    );
  }

  void _showSpacePicker(BuildContext context, WidgetRef ref) {
    final currentSpace = ref.read(currentSpaceProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Switch Mode',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            ...Space.all.map((space) {
              final isSelected = space.slug == currentSpace.slug;
              return ListTile(
                leading: _SpaceIcon(space: space, isSelected: isSelected),
                title: Text(space.name),
                subtitle: space.description != null ? Text(space.description!) : null,
                trailing: isSelected
                    ? Icon(LucideIcons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(spaceProvider.notifier).switchSpace(space);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
