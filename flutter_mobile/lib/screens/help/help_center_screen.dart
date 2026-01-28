import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';

class HelpCenterScreen extends ConsumerWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const BrandedAppBar(
        title: 'Help Center',
        showBackButton: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App Overview
          _HelpSection(
            title: 'Getting Started',
            icon: LucideIcons.rocket,
            items: const [
              _HelpItem(
                title: 'Welcome to Amos',
                content:
                    'Amos is your business productivity companion. Use it to manage tasks, track analytics, and stay connected with your team.',
              ),
              _HelpItem(
                title: 'Navigation',
                content:
                    'Use the bottom navigation bar to switch between Amos (chat), Tools, Messages, and More screens.',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chat Feature
          _HelpSection(
            title: 'Amos Chat',
            icon: LucideIcons.messageSquare,
            items: const [
              _HelpItem(
                title: 'Starting a Conversation',
                content:
                    'Tap the Amos tab to start a conversation. Type your message or use voice input to interact.',
              ),
              _HelpItem(
                title: 'Voice Input',
                content:
                    'Tap the microphone icon to use voice-to-text. Speak clearly and tap again to stop recording.',
              ),
              _HelpItem(
                title: 'File Attachments',
                content:
                    'Tap the attachment icon to upload documents, images, or files to share in your conversation.',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tasks
          _HelpSection(
            title: 'Tasks',
            icon: LucideIcons.listTodo,
            items: const [
              _HelpItem(
                title: 'Creating Tasks',
                content:
                    'Go to Tools > Tasks and tap "New Task" to create a task. Set a title, description, and due date.',
              ),
              _HelpItem(
                title: 'Managing Tasks',
                content:
                    'Tap on any task to view details, mark it complete, or edit. Swipe left to delete a task.',
              ),
              _HelpItem(
                title: 'Scheduled Tasks',
                content:
                    'Create recurring tasks by setting a schedule when creating a new task.',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Messages
          _HelpSection(
            title: 'Messages',
            icon: LucideIcons.messagesSquare,
            items: const [
              _HelpItem(
                title: 'Channels',
                content:
                    'Join team channels to collaborate with colleagues. Messages are visible to all channel members.',
              ),
              _HelpItem(
                title: 'Direct Messages',
                content:
                    'Start private conversations by tapping on a team member\'s name or the DM tab.',
              ),
              _HelpItem(
                title: 'Real-time Updates',
                content:
                    'Messages sync in real-time across all your devices. You\'ll see new messages instantly.',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Analytics
          _HelpSection(
            title: 'Analytics',
            icon: LucideIcons.chartBar,
            items: const [
              _HelpItem(
                title: 'Viewing Insights',
                content:
                    'Go to Tools > Analytics to view performance metrics and business insights.',
              ),
              _HelpItem(
                title: 'Understanding Metrics',
                content:
                    'Analytics show task completion rates, activity trends, and productivity metrics.',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Account & Settings
          _HelpSection(
            title: 'Account & Settings',
            icon: LucideIcons.settings,
            items: const [
              _HelpItem(
                title: 'Business Profile',
                content:
                    'Update your business information in More > Business Profile. This helps personalize your experience.',
              ),
              _HelpItem(
                title: 'Notifications',
                content:
                    'Manage notification preferences in Settings. Choose which alerts you want to receive.',
              ),
              _HelpItem(
                title: 'Security',
                content:
                    'Enable two-factor authentication (MFA) in Settings for enhanced account security.',
              ),
              _HelpItem(
                title: 'Sign Out',
                content:
                    'To sign out, go to More and tap "Sign Out" at the bottom of the screen.',
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Contact Support
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.primaryColor.withValues(alpha: 0.3)),
            ),
            color: context.primaryColor.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.mail,
                        color: context.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Need More Help?',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.primaryColor,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contact our support team at support@amoslabs.com for additional assistance.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _HelpSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<_HelpItem> items;

  const _HelpSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  State<_HelpSection> createState() => _HelpSectionState();
}

class _HelpSectionState extends State<_HelpSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: Radius.circular(_isExpanded ? 0 : 12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(widget.icon, size: 22, color: context.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    color: context.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.borderColor),
                ),
              ),
              child: Column(
                children: widget.items.map((item) {
                  final isLast = widget.items.last == item;
                  return _HelpItemTile(item: item, isLast: isLast);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _HelpItem {
  final String title;
  final String content;

  const _HelpItem({
    required this.title,
    required this.content,
  });
}

class _HelpItemTile extends StatefulWidget {
  final _HelpItem item;
  final bool isLast;

  const _HelpItemTile({
    required this.item,
    required this.isLast,
  });

  @override
  State<_HelpItemTile> createState() => _HelpItemTileState();
}

class _HelpItemTileState extends State<_HelpItemTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                Icon(
                  _isExpanded ? LucideIcons.minus : LucideIcons.plus,
                  color: context.textTertiary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              widget.item.content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
        if (!widget.isLast)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: context.borderColor,
          ),
      ],
    );
  }
}
