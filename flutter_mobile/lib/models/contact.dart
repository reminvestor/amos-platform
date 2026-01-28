class Contact {
  final int id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? name;
  final String? status;
  final List<String>? tags;
  final List<ContactGroup>? groups;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Contact({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.name,
    this.status,
    this.tags,
    this.groups,
    this.createdAt,
    this.updatedAt,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as int,
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      name: json['name'] as String?,
      status: json['status'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      groups: (json['groups'] as List<dynamic>?)
          ?.map((g) => ContactGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}

class ContactGroup {
  final int id;
  final String name;

  ContactGroup({
    required this.id,
    required this.name,
  });

  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    return ContactGroup(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );
  }
}

class ContactsResponse {
  final List<Contact> data;
  final ContactsPagination pagination;

  ContactsResponse({
    required this.data,
    required this.pagination,
  });

  factory ContactsResponse.fromJson(Map<String, dynamic> json) {
    return ContactsResponse(
      data: (json['data'] as List<dynamic>?)
          ?.map((c) => Contact.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      pagination: ContactsPagination.fromJson(
          json['pagination'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class ContactsPagination {
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int perPage;

  ContactsPagination({
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.perPage,
  });

  factory ContactsPagination.fromJson(Map<String, dynamic> json) {
    return ContactsPagination(
      currentPage: json['current_page'] as int? ?? 1,
      totalPages: json['total_pages'] as int? ?? 1,
      totalCount: json['total_count'] as int? ?? 0,
      perPage: json['per_page'] as int? ?? 20,
    );
  }
}
