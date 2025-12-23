import 'package:amos_mobile/models/email_template.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class EmailTemplatesService {
  final ApiClient _api = ApiClient();

  /// Fetch all email templates with optional search
  Future<List<EmailTemplate>> getEmailTemplates({String? search}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _api.get('/api/v1/email_templates', queryParameters: queryParams);
      final templatesList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${templatesList.length} email templates');
      return templatesList.map((json) => EmailTemplate.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load email templates', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single email template details
  Future<EmailTemplate> getEmailTemplate(String id) async {
    try {
      final response = await _api.get('/api/v1/email_templates/$id');
      return EmailTemplate.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load email template $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete an email template
  Future<void> deleteEmailTemplate(String id) async {
    try {
      await _api.delete('/api/v1/email_templates/$id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete email template $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create a new email template
  Future<EmailTemplate> createEmailTemplate({
    required String name,
    required String subject,
    required String body,
  }) async {
    try {
      final response = await _api.post('/api/v1/email_templates', data: {
        'name': name,
        'subject': subject,
        'body': body,
      });
      AppLogger.info('Created email template: $name');
      return EmailTemplate.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create email template', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update an existing email template
  Future<EmailTemplate> updateEmailTemplate(
    String id, {
    String? name,
    String? subject,
    String? body,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (subject != null) data['subject'] = subject;
      if (body != null) data['body'] = body;

      final response = await _api.patch('/api/v1/email_templates/$id', data: data);
      AppLogger.info('Updated email template: $id');
      return EmailTemplate.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update email template $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Duplicate an email template
  Future<EmailTemplate> duplicateEmailTemplate(String id) async {
    try {
      final template = await getEmailTemplate(id);
      return createEmailTemplate(
        name: '${template.name} (Copy)',
        subject: template.subject,
        body: template.body,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to duplicate email template $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
