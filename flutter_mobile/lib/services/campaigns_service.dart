import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class CampaignsService {
  final ApiClient _api = ApiClient();

  /// Fetch all campaigns with optional filtering
  Future<List<Campaign>> getCampaigns({
    String? search,
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      final response = await _api.get('/api/v1/campaigns', queryParameters: queryParams);
      final campaignsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${campaignsList.length} campaigns');
      return campaignsList.map((json) => Campaign.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load campaigns', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single campaign details
  Future<Campaign> getCampaign(String id) async {
    try {
      final response = await _api.get('/api/v1/campaigns/$id');
      return Campaign.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load campaign $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create a new campaign
  Future<Campaign> createCampaign({
    required String name,
    required String subject,
    String? content,
    String status = 'draft',
  }) async {
    try {
      final response = await _api.post('/api/v1/campaigns', data: {
        'name': name,
        'subject': subject,
        if (content != null) 'content': content,
        'status': status,
      });
      return Campaign.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create campaign', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update a campaign
  Future<Campaign> updateCampaign({
    required String id,
    String? name,
    String? subject,
    String? description,
    String? content,
    String? status,
    DateTime? scheduledAt,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (subject != null) data['subject'] = subject;
      if (description != null) data['description'] = description;
      if (content != null) data['content'] = content;
      if (status != null) data['status'] = status;
      if (scheduledAt != null) data['scheduled_at'] = scheduledAt.toIso8601String();

      final response = await _api.patch('/api/v1/campaigns/$id', data: data);
      return Campaign.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update campaign $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a campaign
  Future<void> deleteCampaign(String id) async {
    try {
      await _api.delete('/api/v1/campaigns/$id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete campaign $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Pause an in-progress campaign
  Future<Campaign> pauseCampaign(String id) async {
    try {
      final response = await _api.post('/api/v1/campaigns/$id/pause');
      return Campaign.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to pause campaign $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Resume a paused campaign
  Future<Campaign> resumeCampaign(String id) async {
    try {
      final response = await _api.post('/api/v1/campaigns/$id/resume');
      return Campaign.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to resume campaign $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
