import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class BusinessProfileService {
  final ApiClient _api = ApiClient.instance;

  /// Get current business profile
  Future<BusinessProfile> getProfile() async {
    try {
      final response = await _api.get('/api/business_profile');
      return BusinessProfile.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get business profile', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update business profile
  Future<BusinessProfile> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await _api.patch('/api/business_profile', data: {
        'business_profile': data,
      });
      return BusinessProfile.fromJson(response['profile']);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update business profile', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}

class BusinessProfile {
  final int id;
  final String? name;
  final String? industry;
  final String? description;
  final int? foundedYear;
  final String? website;
  final String? values;
  final String? targetAudience;
  final String? toneOfVoice;
  final Map<String, dynamic>? styleGuidelines;
  final String? entityName;

  BusinessProfile({
    required this.id,
    this.name,
    this.industry,
    this.description,
    this.foundedYear,
    this.website,
    this.values,
    this.targetAudience,
    this.toneOfVoice,
    this.styleGuidelines,
    this.entityName,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: json['id'] as int,
      name: json['name'] as String?,
      industry: json['industry'] as String?,
      description: json['description'] as String?,
      foundedYear: json['founded_year'] as int?,
      website: json['website'] as String?,
      values: json['values'] as String?,
      targetAudience: json['target_audience'] as String?,
      toneOfVoice: json['tone_of_voice'] as String?,
      styleGuidelines: json['style_guidelines'] as Map<String, dynamic>?,
      entityName: json['entity_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'industry': industry,
      'description': description,
      'founded_year': foundedYear,
      'website': website,
      'values': values,
      'target_audience': targetAudience,
      'tone_of_voice': toneOfVoice,
    };
  }
}
