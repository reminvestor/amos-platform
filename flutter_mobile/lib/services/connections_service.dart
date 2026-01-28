import 'package:amos_mobile/models/connection.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class ConnectionsService {
  final ApiClient _api = ApiClient();

  /// Fetch all connections for the current entity
  Future<List<Connection>> getConnections() async {
    try {
      final response = await _api.get('/api/v1/connections');
      final connectionsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${connectionsList.length} connections');
      return connectionsList.map((json) => Connection.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load connections', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single connection details
  Future<Connection> getConnection(String id) async {
    try {
      final response = await _api.get('/api/v1/connections/$id');
      return Connection.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load connection $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Test a connection's health
  Future<Map<String, dynamic>> testConnection(String id) async {
    try {
      final response = await _api.post('/api/v1/connections/$id/test');
      return {
        'success': response['success'] ?? false,
        'message': response['message'] ?? '',
        'status': response['status'] ?? 'unknown',
      };
    } catch (e, stackTrace) {
      AppLogger.error('Failed to test connection $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a connection
  Future<void> deleteConnection(String id) async {
    try {
      await _api.delete('/api/v1/connections/$id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete connection $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get available integrations that can be connected
  Future<List<Integration>> getAvailableIntegrations() async {
    try {
      final response = await _api.get('/api/v1/connections/available');
      final integrationsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${integrationsList.length} available integrations');
      return integrationsList.map((json) => Integration.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load available integrations', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get OAuth authorization URL for an integration (for mobile OAuth flow)
  Future<OAuthUrlResponse> getOAuthUrl(String integrationSlug) async {
    try {
      final response = await _api.get('/api/v1/connections/oauth_url/$integrationSlug');
      AppLogger.info('Got OAuth URL for $integrationSlug');
      return OAuthUrlResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get OAuth URL for $integrationSlug', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Check if Gmail is connected
  Future<bool> isGmailConnected() async {
    return isEmailProviderConnected('gmail');
  }

  /// Check if any specific email provider is connected
  Future<bool> isEmailProviderConnected(String slug) async {
    try {
      final connections = await getConnections();
      return connections.any((c) => c.integration.slug == slug && c.status.isHealthy);
    } catch (e) {
      return false;
    }
  }

  /// Get connected email provider info (returns first connected email provider)
  Future<EmailProviderStatus> getEmailProviderStatus() async {
    try {
      final connections = await getConnections();

      // Check email providers in order of preference
      const emailSlugs = ['gmail', 'outlook'];

      for (final slug in emailSlugs) {
        final connection = connections.where(
          (c) => c.integration.slug == slug && c.status.isHealthy,
        ).firstOrNull;

        if (connection != null) {
          return EmailProviderStatus(
            isConnected: true,
            provider: slug,
            providerName: connection.integration.name,
            connectionId: connection.id.toString(),
          );
        }
      }

      return EmailProviderStatus(isConnected: false);
    } catch (e) {
      return EmailProviderStatus(isConnected: false);
    }
  }

  /// Get list of available email providers for connection
  Future<List<EmailProvider>> getAvailableEmailProviders() async {
    try {
      final integrations = await getAvailableIntegrations();
      final connections = await getConnections();

      const emailSlugs = ['gmail', 'outlook'];

      return emailSlugs
          .map((slug) {
            final integration = integrations.where((i) => i.slug == slug).firstOrNull;
            if (integration == null) return null;

            final isConnected = connections.any(
              (c) => c.integration.slug == slug && c.status.isHealthy,
            );

            return EmailProvider(
              slug: slug,
              name: integration.name,
              iconUrl: integration.iconUrl,
              isConnected: isConnected,
            );
          })
          .whereType<EmailProvider>()
          .toList();
    } catch (e) {
      // Return hardcoded list as fallback
      return [
        EmailProvider(slug: 'gmail', name: 'Gmail', isConnected: false),
        EmailProvider(slug: 'outlook', name: 'Microsoft Outlook', isConnected: false),
      ];
    }
  }
}

/// Status of the user's email provider connection
class EmailProviderStatus {
  final bool isConnected;
  final String? provider;
  final String? providerName;
  final String? connectionId;

  EmailProviderStatus({
    required this.isConnected,
    this.provider,
    this.providerName,
    this.connectionId,
  });
}

/// Represents an available email provider
class EmailProvider {
  final String slug;
  final String name;
  final String? iconUrl;
  final bool isConnected;

  EmailProvider({
    required this.slug,
    required this.name,
    this.iconUrl,
    required this.isConnected,
  });
}

/// Response from the OAuth URL endpoint
class OAuthUrlResponse {
  final String url;
  final String state;
  final String integrationName;
  final String integrationSlug;

  OAuthUrlResponse({
    required this.url,
    required this.state,
    required this.integrationName,
    required this.integrationSlug,
  });

  factory OAuthUrlResponse.fromJson(Map<String, dynamic> json) {
    final integration = json['integration'] as Map<String, dynamic>? ?? {};
    return OAuthUrlResponse(
      url: json['url'] as String? ?? '',
      state: json['state'] as String? ?? '',
      integrationName: integration['name'] as String? ?? '',
      integrationSlug: integration['slug'] as String? ?? '',
    );
  }
}
