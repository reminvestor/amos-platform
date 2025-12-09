enum ContactStatus {
  active,
  inactive,
  unsubscribed,
}

extension ContactStatusX on ContactStatus {
  String get value {
    switch (this) {
      case ContactStatus.active:
        return 'active';
      case ContactStatus.inactive:
        return 'inactive';
      case ContactStatus.unsubscribed:
        return 'unsubscribed';
    }
  }

  static ContactStatus fromString(String value) {
    switch (value) {
      case 'active':
        return ContactStatus.active;
      case 'inactive':
        return ContactStatus.inactive;
      case 'unsubscribed':
        return ContactStatus.unsubscribed;
      default:
        return ContactStatus.active;
    }
  }
}

class Contact {
  final String id;
  final String? entityId;
  final String email;
  final ContactStatus status;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? name;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? company;
  final List<String>? tags;
  final List<Map<String, dynamic>>? groups;

  Contact({
    required this.id,
    this.entityId,
    required this.email,
    required this.status,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.name,
    this.firstName,
    this.lastName,
    this.phone,
    this.company,
    this.tags,
    this.groups,
  });

  String get displayName => name ?? firstName ?? email.split('@').first;

  String get initials {
    if (name != null && name!.isNotEmpty) {
      final parts = name!.split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return name![0].toUpperCase();
    }
    return email[0].toUpperCase();
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    List<String>? tagsList;
    if (json['tags'] != null) {
      if (json['tags'] is String) {
        tagsList = (json['tags'] as String).split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      } else if (json['tags'] is List) {
        tagsList = List<String>.from(json['tags']);
      }
    }

    return Contact(
      id: json['id'].toString(),
      entityId: json['entity_id']?.toString(),
      email: json['email'] ?? '',
      status: ContactStatusX.fromString(json['status'] ?? 'active'),
      metadata: json['metadata'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      name: json['name'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      phone: json['phone'],
      company: json['company'],
      tags: tagsList,
      groups: json['groups'] != null ? List<Map<String, dynamic>>.from(json['groups']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_id': entityId,
      'email': email,
      'status': status.value,
      if (metadata != null) 'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (name != null) 'name': name,
      if (company != null) 'company': company,
    };
  }
}

class ContactGroup {
  final String id;
  final String entityId;
  final String name;
  final String? description;
  final int? contactCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContactGroup({
    required this.id,
    required this.entityId,
    required this.name,
    this.description,
    this.contactCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    return ContactGroup(
      id: json['id'],
      entityId: json['entity_id'],
      name: json['name'],
      description: json['description'],
      contactCount: json['contact_count'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_id': entityId,
      'name': name,
      if (description != null) 'description': description,
      if (contactCount != null) 'contact_count': contactCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
