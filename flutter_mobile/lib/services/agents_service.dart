import 'package:amos_mobile/models/agent.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class AgentsService {
  final ApiClient _api = ApiClient();

  /// Fetch all agents
  Future<List<Agent>> getAgents() async {
    // ignore: avoid_print
    print('[Agents] Starting getAgents()');
    try {
      final response = await _api.get('/api/v1/agents');
      // ignore: avoid_print
      print('[Agents] Got response: ${response.runtimeType}');
      final agentsList = response['agents'] as List? ?? [];
      // ignore: avoid_print
      print('[Agents] Parsed ${agentsList.length} agents');
      AppLogger.info('Loaded ${agentsList.length} agents');
      return agentsList.map((json) => Agent.fromJson(json)).toList();
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[Agents] Error: $e');
      AppLogger.error('Failed to load agents', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single agent details
  Future<Agent> getAgent(String id) async {
    try {
      final response = await _api.get('/api/v1/agents/$id');
      return Agent.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load agent $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Execute an agent with a task
  Future<Map<String, dynamic>> executeAgent(String agentId, String task, {String? model}) async {
    try {
      final response = await _api.post('/api/v1/agents/$agentId/execute', data: {
        'task': task,
        if (model != null) 'model': model,
      });
      return response as Map<String, dynamic>;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to execute agent $agentId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
