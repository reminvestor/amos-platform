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
}
