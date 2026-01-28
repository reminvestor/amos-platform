import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/connection.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/services/connections_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class ConnectionsListScreen extends ConsumerStatefulWidget {
  const ConnectionsListScreen({super.key});

  @override
  ConsumerState<ConnectionsListScreen> createState() => _ConnectionsListScreenState();
}

class _ConnectionsListScreenState extends ConsumerState<ConnectionsListScreen> {
  final ConnectionsService _connectionsService = ConnectionsService();
  List<Connection> _connections = [];
  List<Integration> _availableIntegrations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    AppLogger.info('ConnectionsListScreen: Loading connections from API');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connections = await _connectionsService.getConnections();
      final integrations = await _connectionsService.getAvailableIntegrations();
      if (!mounted) return;
      setState(() {
        _connections = connections;
        _availableIntegrations = integrations;
      });
      AppLogger.info('ConnectionsListScreen: Loaded ${connections.length} connections');
    } catch (e, stackTrace) {
      AppLogger.error('ConnectionsListScreen: Failed to load data', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load connections. Pull to retry.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testConnection(Connection connection) async {
    try {
      final result = await _connectionsService.testConnection(connection.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Connection tested'),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to test connection: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteConnection(Connection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to delete the connection to ${connection.integration.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _connectionsService.deleteConnection(connection.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection deleted')),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete connection: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Check if MFA is enabled before allowing integration connection
  /// Returns true if user can proceed, false if blocked
  Future<bool> _checkMfaForIntegration() async {
    final authState = ref.read(authStateProvider);
    final mfaEnabled = authState.user?.mfaEnabled ?? false;

    if (!mfaEnabled) {
      // Show dialog explaining MFA requirement
      final shouldSetup = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Two-Factor Authentication Required'),
          content: const Text(
            'Two-factor authentication is required before connecting integrations. '
            'This protects your external accounts.\n\n'
            'Would you like to set it up now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Set Up MFA'),
            ),
          ],
        ),
      );

      if (shouldSetup == true && mounted) {
        context.push('/mfa-setup');
      }
      return false;
    }
    return true;
  }

  Future<void> _navigateToConnectIntegration() async {
    if (!await _checkMfaForIntegration()) return;
    if (!mounted) return;
    context.push('/chat?prompt=${Uri.encodeComponent("I want to connect a new integration")}');
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
      case ConnectionStatus.active:
        return Colors.green;
      case ConnectionStatus.inactive:
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  String _getStatusLabel(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.active:
        return 'Active';
      case ConnectionStatus.inactive:
        return 'Inactive';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Integrations'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: _navigateToConnectIntegration,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _connections.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_connections.isNotEmpty) ...[
                              Text(
                                'Connected',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              ..._connections.map((c) => _ConnectionCard(
                                    connection: c,
                                    statusColor: _getStatusColor(c.status),
                                    statusLabel: _getStatusLabel(c.status),
                                    onTest: () => _testConnection(c),
                                    onDelete: () => _deleteConnection(c),
                                  )),
                            ],
                            if (_availableIntegrations.where((i) => !i.connected).isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text(
                                'Available Integrations',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              ..._availableIntegrations
                                  .where((i) => !i.connected)
                                  .map((i) => _AvailableIntegrationCard(
                                        integration: i,
                                        onConnect: () async {
                                          if (!await _checkMfaForIntegration()) return;
                                          if (!mounted) return;
                                          context.push('/chat?prompt=${Uri.encodeComponent("I want to connect ${i.name}")}');
                                        },
                                      )),
                            ],
                          ],
                        ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleX,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              Icon(
                LucideIcons.plug,
                size: 64,
                color: context.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No Integrations',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Connect your favorite tools and services.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToConnectIntegration,
                icon: const Icon(LucideIcons.plus),
                label: const Text('Connect Integration'),
              ),
              if (_availableIntegrations.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  'Available Integrations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                ..._availableIntegrations.map((i) => _AvailableIntegrationCard(
                      integration: i,
                      onConnect: () async {
                        if (!await _checkMfaForIntegration()) return;
                        if (!mounted) return;
                        context.push('/chat?prompt=${Uri.encodeComponent("I want to connect ${i.name}")}');
                      },
                    )),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final Connection connection;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.statusColor,
    required this.statusLabel,
    required this.onTest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
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
                    color: context.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getIntegrationIcon(connection.integration.slug),
                    color: context.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.integration.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (connection.integration.category != null)
                        Text(
                          connection.integration.category!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (connection.lastHealthCheck != null) ...[
                  Icon(LucideIcons.activity, size: 14, color: context.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    'Last checked: ${dateFormat.format(connection.lastHealthCheck!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textTertiary,
                        ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: onTest,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Test'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIntegrationIcon(String slug) {
    switch (slug.toLowerCase()) {
      case 'stripe':
        return LucideIcons.creditCard;
      case 'hubspot':
        return LucideIcons.users;
      case 'mailgun':
        return LucideIcons.mail;
      case 'slack':
        return LucideIcons.messageSquare;
      case 'google':
        return LucideIcons.globe;
      case 'zapier':
        return LucideIcons.zap;
      default:
        return LucideIcons.plug;
    }
  }
}

class _AvailableIntegrationCard extends StatelessWidget {
  final Integration integration;
  final Future<void> Function() onConnect;

  const _AvailableIntegrationCard({
    required this.integration,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onConnect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getIntegrationIcon(integration.slug),
                  color: context.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      integration.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (integration.description != null)
                      Text(
                        integration.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.plus,
                color: context.primaryColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIntegrationIcon(String slug) {
    switch (slug.toLowerCase()) {
      case 'stripe':
        return LucideIcons.creditCard;
      case 'hubspot':
        return LucideIcons.users;
      case 'mailgun':
        return LucideIcons.mail;
      case 'slack':
        return LucideIcons.messageSquare;
      case 'google':
        return LucideIcons.globe;
      case 'zapier':
        return LucideIcons.zap;
      default:
        return LucideIcons.plug;
    }
  }
}
