import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// AMOS Widget Catalog for AI-generated UI
/// These widgets can be rendered in chat responses to provide
/// interactive, visual representations instead of plain text.

/// Available widget types that AI can generate
enum GenUIWidgetType {
  campaignCard,
  contactCard,
  landingPagePreview,
  statCard,
  taskCard,
  quickActionButton,
}

/// Base class for GenUI widget data
abstract class GenUIWidgetData {
  Map<String, dynamic> toJson();
}

/// Campaign card data
class CampaignCardData extends GenUIWidgetData {
  final int? id;
  final String name;
  final String? subject;
  final String status;
  final int recipientCount;
  final double? openRate;
  final double? clickRate;

  CampaignCardData({
    this.id,
    required this.name,
    this.subject,
    this.status = 'draft',
    this.recipientCount = 0,
    this.openRate,
    this.clickRate,
  });

  factory CampaignCardData.fromJson(Map<String, dynamic> json) {
    return CampaignCardData(
      id: json['id'] as int?,
      name: json['name'] as String? ?? 'Untitled Campaign',
      subject: json['subject'] as String?,
      status: json['status'] as String? ?? 'draft',
      recipientCount: json['recipientCount'] as int? ?? 0,
      openRate: (json['openRate'] as num?)?.toDouble(),
      clickRate: (json['clickRate'] as num?)?.toDouble(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subject': subject,
    'status': status,
    'recipientCount': recipientCount,
    'openRate': openRate,
    'clickRate': clickRate,
  };
}

/// Contact card data
class ContactCardData extends GenUIWidgetData {
  final int? id;
  final String name;
  final String email;
  final String? company;
  final List<String> tags;

  ContactCardData({
    this.id,
    required this.name,
    required this.email,
    this.company,
    this.tags = const [],
  });

  factory ContactCardData.fromJson(Map<String, dynamic> json) {
    return ContactCardData(
      id: json['id'] as int?,
      name: json['name'] as String? ?? 'Unknown',
      email: json['email'] as String? ?? '',
      company: json['company'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'company': company,
    'tags': tags,
  };
}

/// Stat card data for analytics
class StatCardData extends GenUIWidgetData {
  final String label;
  final String value;
  final double? change;
  final String icon;
  final String color;

  StatCardData({
    required this.label,
    required this.value,
    this.change,
    this.icon = 'trending-up',
    this.color = 'blue',
  });

  factory StatCardData.fromJson(Map<String, dynamic> json) {
    return StatCardData(
      label: json['label'] as String? ?? '',
      value: json['value'] as String? ?? '0',
      change: (json['change'] as num?)?.toDouble(),
      icon: json['icon'] as String? ?? 'trending-up',
      color: json['color'] as String? ?? 'blue',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'label': label,
    'value': value,
    'change': change,
    'icon': icon,
    'color': color,
  };
}

/// Landing page preview data
class LandingPagePreviewData extends GenUIWidgetData {
  final int? id;
  final String name;
  final String? headline;
  final String status;
  final int visits;
  final int conversions;

  LandingPagePreviewData({
    this.id,
    required this.name,
    this.headline,
    this.status = 'draft',
    this.visits = 0,
    this.conversions = 0,
  });

  factory LandingPagePreviewData.fromJson(Map<String, dynamic> json) {
    return LandingPagePreviewData(
      id: json['id'] as int?,
      name: json['name'] as String? ?? 'Untitled Page',
      headline: json['headline'] as String?,
      status: json['status'] as String? ?? 'draft',
      visits: json['visits'] as int? ?? 0,
      conversions: json['conversions'] as int? ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'headline': headline,
    'status': status,
    'visits': visits,
    'conversions': conversions,
  };
}

/// Task card data
class TaskCardData extends GenUIWidgetData {
  final int? id;
  final String name;
  final String? taskType;
  final String status;
  final String? scheduleType;

  TaskCardData({
    this.id,
    required this.name,
    this.taskType,
    this.status = 'active',
    this.scheduleType,
  });

  factory TaskCardData.fromJson(Map<String, dynamic> json) {
    return TaskCardData(
      id: json['id'] as int?,
      name: json['name'] as String? ?? 'Untitled Task',
      taskType: json['taskType'] as String?,
      status: json['status'] as String? ?? 'active',
      scheduleType: json['scheduleType'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'taskType': taskType,
    'status': status,
    'scheduleType': scheduleType,
  };
}

/// Widget builder utilities
class GenUIWidgetBuilder {
  /// Build a campaign card widget
  static Widget buildCampaignCard(
    BuildContext context,
    CampaignCardData data, {
    void Function(String action, Map<String, dynamic> data)? onAction,
  }) {
    Color statusColor;
    IconData statusIcon;
    switch (data.status) {
      case 'sent':
        statusColor = Colors.green;
        statusIcon = LucideIcons.circleCheck;
        break;
      case 'scheduled':
        statusColor = Colors.blue;
        statusIcon = LucideIcons.clock;
        break;
      case 'sending':
        statusColor = Colors.orange;
        statusIcon = LucideIcons.loader;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = LucideIcons.pencil;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () {
          if (data.id != null) {
            onAction?.call('view_campaign', data.toJson());
            context.push('/campaigns/${data.id}');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.mail, size: 20, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          data.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (data.subject != null) ...[
                const SizedBox(height: 8),
                Text(
                  data.subject!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildStatChip(context, LucideIcons.users, '${data.recipientCount} recipients'),
                  if (data.openRate != null) ...[
                    const SizedBox(width: 12),
                    _buildStatChip(context, LucideIcons.eye, '${data.openRate!.toStringAsFixed(1)}% opens'),
                  ],
                  if (data.clickRate != null) ...[
                    const SizedBox(width: 12),
                    _buildStatChip(context, LucideIcons.mousePointerClick, '${data.clickRate!.toStringAsFixed(1)}% clicks'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a contact card widget
  static Widget buildContactCard(
    BuildContext context,
    ContactCardData data, {
    void Function(String action, Map<String, dynamic> data)? onAction,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        onTap: () {
          if (data.id != null) {
            onAction?.call('view_contact', data.toJson());
            context.push('/contacts/${data.id}');
          }
        },
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: Text(
            data.name.isNotEmpty ? data.name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(data.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.email),
            if (data.company != null) Text(data.company!, style: Theme.of(context).textTheme.bodySmall),
            if (data.tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: data.tags.take(3).map((tag) => Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            ],
          ],
        ),
        trailing: const Icon(LucideIcons.chevronRight),
      ),
    );
  }

  /// Build a stat card widget
  static Widget buildStatCard(
    BuildContext context,
    StatCardData data, {
    void Function(String action, Map<String, dynamic> data)? onAction,
  }) {
    IconData icon;
    switch (data.icon) {
      case 'mail': icon = LucideIcons.mail; break;
      case 'users': icon = LucideIcons.users; break;
      case 'eye': icon = LucideIcons.eye; break;
      case 'target': icon = LucideIcons.target; break;
      case 'dollar': icon = LucideIcons.dollarSign; break;
      default: icon = LucideIcons.trendingUp;
    }

    Color color;
    switch (data.color) {
      case 'green': color = Colors.green; break;
      case 'orange': color = Colors.orange; break;
      case 'purple': color = Colors.purple; break;
      case 'red': color = Colors.red; break;
      default: color = Colors.blue;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const Spacer(),
                if (data.change != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: data.change! >= 0
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          data.change! >= 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                          size: 14,
                          color: data.change! >= 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${data.change! >= 0 ? '+' : ''}${data.change!.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: data.change! >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              data.value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              data.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Build a landing page preview widget
  static Widget buildLandingPagePreview(
    BuildContext context,
    LandingPagePreviewData data, {
    void Function(String action, Map<String, dynamic> data)? onAction,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            width: double.infinity,
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            child: Center(
              child: Icon(
                LucideIcons.layoutPanelLeft,
                size: 48,
                color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: data.status == 'published'
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: data.status == 'published' ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                if (data.headline != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.headline!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatChip(context, LucideIcons.eye, '${data.visits} visits'),
                    const SizedBox(width: 16),
                    _buildStatChip(context, LucideIcons.target, '${data.conversions} conversions'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (data.id != null) {
                            onAction?.call('edit_page', data.toJson());
                            context.push('/landing-pages/${data.id}');
                          }
                        },
                        icon: const Icon(LucideIcons.pencil, size: 16),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          onAction?.call('view_page', data.toJson());
                        },
                        icon: const Icon(LucideIcons.externalLink, size: 16),
                        label: const Text('View'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a task card widget
  static Widget buildTaskCard(
    BuildContext context,
    TaskCardData data, {
    void Function(String action, Map<String, dynamic> data)? onAction,
  }) {
    Color statusColor;
    IconData statusIcon;
    switch (data.status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = LucideIcons.circleCheck;
        break;
      case 'paused':
        statusColor = Colors.orange;
        statusIcon = LucideIcons.pause;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = LucideIcons.circleX;
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = LucideIcons.play;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        onTap: () {
          if (data.id != null) {
            onAction?.call('view_task', data.toJson());
            context.push('/tasks/${data.id}');
          }
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.calendarClock, color: statusColor, size: 20),
        ),
        title: Text(data.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.taskType != null) Text(data.taskType!),
            if (data.scheduleType != null) Text('Runs ${data.scheduleType}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: Icon(statusIcon, color: statusColor),
      ),
    );
  }

  static Widget _buildStatChip(BuildContext context, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
