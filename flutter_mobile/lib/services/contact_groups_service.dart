import 'package:amos_mobile/models/contact_group.dart';
import 'package:amos_mobile/models/contact.dart' hide ContactGroup;
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class ContactGroupsService {
  final ApiClient _api = ApiClient();

  /// Fetch all contact groups with optional search
  Future<List<ContactGroup>> getContactGroups({String? search}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _api.get('/api/v1/contact_groups', queryParameters: queryParams);
      final groupsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${groupsList.length} contact groups');
      return groupsList.map((json) => ContactGroup.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load contact groups', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single contact group with its contacts
  Future<ContactGroupDetail> getContactGroup(String id, {int page = 1}) async {
    try {
      final response = await _api.get('/api/v1/contact_groups/$id', queryParameters: {'page': page});
      return ContactGroupDetail.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load contact group $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create a new contact group
  Future<ContactGroup> createContactGroup({
    required String name,
    String? description,
  }) async {
    try {
      final response = await _api.post('/api/v1/contact_groups', data: {
        'name': name,
        if (description != null) 'description': description,
      });
      AppLogger.info('Created contact group: $name');
      return ContactGroup.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create contact group', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update a contact group
  Future<ContactGroup> updateContactGroup(
    String id, {
    String? name,
    String? description,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;

      final response = await _api.patch('/api/v1/contact_groups/$id', data: data);
      AppLogger.info('Updated contact group: $id');
      return ContactGroup.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update contact group $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a contact group
  Future<void> deleteContactGroup(String id) async {
    try {
      await _api.delete('/api/v1/contact_groups/$id');
      AppLogger.info('Deleted contact group: $id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete contact group $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Add contacts to a group
  Future<void> addContactsToGroup(String groupId, List<String> contactIds) async {
    try {
      await _api.post('/api/v1/contact_groups/$groupId/add_contacts', data: {
        'contact_ids': contactIds,
      });
      AppLogger.info('Added ${contactIds.length} contacts to group $groupId');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to add contacts to group $groupId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Remove contacts from a group
  Future<void> removeContactsFromGroup(String groupId, List<String> contactIds) async {
    try {
      await _api.post('/api/v1/contact_groups/$groupId/remove_contacts', data: {
        'contact_ids': contactIds,
      });
      AppLogger.info('Removed ${contactIds.length} contacts from group $groupId');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to remove contacts from group $groupId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}

/// Extended contact group with contacts list
class ContactGroupDetail {
  final ContactGroup group;
  final List<Contact> contacts;
  final int currentPage;
  final int totalPages;
  final int totalCount;

  ContactGroupDetail({
    required this.group,
    required this.contacts,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
  });

  factory ContactGroupDetail.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? {};
    final contactsList = json['contacts'] as List? ?? [];

    return ContactGroupDetail(
      group: ContactGroup.fromJson(json),
      contacts: contactsList.map((c) => Contact.fromJson(c)).toList(),
      currentPage: meta['current_page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
      totalCount: meta['total_count'] ?? 0,
    );
  }
}
