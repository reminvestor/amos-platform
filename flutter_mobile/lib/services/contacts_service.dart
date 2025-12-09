import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class ContactsService {
  final ApiClient _api = ApiClient();

  /// Fetch all contacts with optional filtering
  Future<List<Contact>> getContacts({
    String? search,
    String? groupId,
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
      if (groupId != null && groupId.isNotEmpty) {
        queryParams['group_id'] = groupId;
      }

      final response = await _api.get('/api/v1/contacts_list', queryParameters: queryParams);
      final contactsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${contactsList.length} contacts');
      return contactsList.map((json) => Contact.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load contacts', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single contact details
  Future<Contact> getContact(String id) async {
    try {
      final response = await _api.get('/api/v1/contacts_list/$id');
      return Contact.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load contact $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create a new contact
  Future<Contact> createContact({
    required String email,
    String? firstName,
    String? lastName,
    String? phone,
    String? company,
    String? notes,
    String? status,
    List<String>? tags,
  }) async {
    try {
      final response = await _api.post('/api/v1/contacts_list', data: {
        'email': email,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (phone != null) 'phone': phone,
        if (company != null) 'company': company,
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status,
        if (tags != null) 'tags': tags.join(','),
      });
      return Contact.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create contact', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update a contact
  Future<Contact> updateContact({
    required String id,
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? company,
    String? notes,
    String? status,
    List<String>? tags,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (email != null) data['email'] = email;
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (phone != null) data['phone'] = phone;
      if (company != null) data['company'] = company;
      if (notes != null) data['notes'] = notes;
      if (status != null) data['status'] = status;
      if (tags != null) data['tags'] = tags.join(',');

      final response = await _api.patch('/api/v1/contacts_list/$id', data: data);
      return Contact.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update contact $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a contact
  Future<void> deleteContact(String id) async {
    try {
      await _api.delete('/api/v1/contacts_list/$id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete contact $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
