import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/api_client.dart';

class ContactService {
  final ApiClient _api = ApiClient();

  Future<ContactsResponse> getContacts({
    int page = 1,
    int perPage = 20,
    String? search,
    int? groupId,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    if (groupId != null) {
      queryParams['group_id'] = groupId.toString();
    }

    final response = await _api.get(
      '/api/v1/contacts_list',
      queryParameters: queryParams,
    );

    return ContactsResponse.fromJson(response.data);
  }

  Future<Contact> getContact(int id) async {
    final response = await _api.get('/api/v1/contacts_list/$id');
    return Contact.fromJson(response.data);
  }
}
