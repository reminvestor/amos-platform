class Integration {
  final String id;
  final String name;
  final String slug;
  final String? icon;
  final String? iconUrl;
  final String? description;
  final String? category;
  final String? authType;
  final bool isActive;
  final bool connected;

  Integration({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.iconUrl,
    this.description,
    this.category,
    this.authType,
    this.isActive = true,
    this.connected = false,
  });

  factory Integration.fromJson(Map<String, dynamic> json) {
    return Integration(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      icon: json['icon'],
      iconUrl: json['icon_url'],
      description: json['description'],
      category: json['category'],
      authType: json['auth_type'],
      isActive: json['is_active'] ?? true,
      connected: json['connected'] ?? false,
    );
  }
}

enum ConnectionStatus {
  connected,
  active,
  inactive,
  error,
  disconnected,
}

extension ConnectionStatusX on ConnectionStatus {
  String get value {
    switch (this) {
      case ConnectionStatus.connected:
        return 'connected';
      case ConnectionStatus.active:
        return 'active';
      case ConnectionStatus.inactive:
        return 'inactive';
      case ConnectionStatus.error:
        return 'error';
      case ConnectionStatus.disconnected:
        return 'disconnected';
    }
  }

  bool get isHealthy => this == ConnectionStatus.connected || this == ConnectionStatus.active;

  static ConnectionStatus fromString(String value) {
    switch (value) {
      case 'connected':
        return ConnectionStatus.connected;
      case 'active':
        return ConnectionStatus.active;
      case 'inactive':
        return ConnectionStatus.inactive;
      case 'error':
        return ConnectionStatus.error;
      case 'disconnected':
        return ConnectionStatus.disconnected;
      default:
        return ConnectionStatus.inactive;
    }
  }
}

class Connection {
  final String id;
  final String name;
  final ConnectionStatus status;
  final Integration integration;
  final DateTime? lastHealthCheck;
  final DateTime createdAt;
  final DateTime updatedAt;

  Connection({
    required this.id,
    required this.name,
    required this.status,
    required this.integration,
    this.lastHealthCheck,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      status: ConnectionStatusX.fromString(json['status'] ?? 'inactive'),
      integration: Integration.fromJson(json['integration'] ?? {}),
      lastHealthCheck: json['last_health_check'] != null
          ? DateTime.parse(json['last_health_check'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
