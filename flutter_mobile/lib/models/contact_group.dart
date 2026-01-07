class ContactGroup {
  final String id;
  final String name;
  final String? description;
  final int contactsCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContactGroup({
    required this.id,
    required this.name,
    this.description,
    this.contactsCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    return ContactGroup(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      description: json['description'],
      contactsCount: json['contacts_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'contacts_count': contactsCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
