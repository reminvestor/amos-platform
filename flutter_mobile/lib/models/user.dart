class User {
  final String id;
  final String email;
  final String? name;
  final String? entityId;
  final String? avatarUrl;
  final DateTime? createdAt;
  final bool mfaEnabled;

  const User({
    required this.id,
    required this.email,
    this.name,
    this.entityId,
    this.avatarUrl,
    this.createdAt,
    this.mfaEnabled = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      email: json['email'] as String,
      name: json['name'] as String?,
      entityId: json['entity_id']?.toString(),
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      mfaEnabled: json['mfa_enabled'] == true || json['otp_required_for_login'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'entity_id': entityId,
      'avatar_url': avatarUrl,
      'created_at': createdAt?.toIso8601String(),
      'mfa_enabled': mfaEnabled,
    };
  }

  String get initials {
    if (name == null || name!.isEmpty) {
      return email[0].toUpperCase();
    }
    final parts = name!.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name![0].toUpperCase();
  }
}

class AuthResult {
  final User user;
  final String token;

  const AuthResult({required this.user, required this.token});
}

class LoginResult {
  final AuthResult? authResult;
  final bool mfaRequired;
  final String? mfaSessionToken;

  /// SECURITY: Rotated device token for next biometric login.
  /// Server rotates the token on each use to prevent replay attacks.
  final String? newDeviceToken;

  const LoginResult({
    this.authResult,
    this.mfaRequired = false,
    this.mfaSessionToken,
    this.newDeviceToken,
  });
}
