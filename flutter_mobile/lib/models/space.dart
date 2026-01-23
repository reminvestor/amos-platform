/// Space model representing Personal or Operations modes
/// Matches the 2-mode architecture on web
class Space {
  final String slug;
  final String name;
  final String? description;
  final String? icon;
  final bool enabled;
  final int displayOrder;

  Space({
    required this.slug,
    required this.name,
    this.description,
    this.icon,
    this.enabled = true,
    this.displayOrder = 0,
  });

  factory Space.fromJson(Map<String, dynamic> json) {
    return Space(
      slug: json['slug'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      icon: json['icon'],
      enabled: json['enabled'] ?? true,
      displayOrder: json['display_order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slug': slug,
      'name': name,
      'description': description,
      'icon': icon,
      'enabled': enabled,
      'display_order': displayOrder,
    };
  }

  bool get isPersonal => slug == 'personal';
  bool get isOperations => slug == 'operations';

  // Legacy aliases for backward compatibility
  bool get isWork => slug == 'operations';
  bool get isTeam => false; // No longer used
  bool get isDesign => false; // No longer used

  // Predefined spaces matching web 2-mode architecture
  static Space personal = Space(
    slug: 'personal',
    name: 'Personal',
    description: 'Your private workspace',
    icon: '👤',
    displayOrder: 0,
  );

  static Space operations = Space(
    slug: 'operations',
    name: 'Operations',
    description: 'Business tools and workflows',
    icon: '⚙️',
    displayOrder: 1,
  );

  // Legacy aliases
  static Space get work => operations;

  static List<Space> all = [personal, operations];
}

/// Team channel for group communication
class TeamChannel {
  final int id;
  final String name;
  final String? description;
  final String channelType;
  final String? icon;
  final bool isPrivate;
  final int memberCount;
  final int agentCount;
  final int unreadCount;
  final DateTime? lastActivityAt;
  final int? mainThreadId;

  TeamChannel({
    required this.id,
    required this.name,
    this.description,
    this.channelType = 'general',
    this.icon,
    this.isPrivate = false,
    this.memberCount = 0,
    this.agentCount = 0,
    this.unreadCount = 0,
    this.lastActivityAt,
    this.mainThreadId,
  });

  factory TeamChannel.fromJson(Map<String, dynamic> json) {
    return TeamChannel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      channelType: json['channel_type'] ?? 'general',
      icon: json['icon'],
      isPrivate: json['is_private'] ?? false,
      memberCount: json['member_count'] ?? 0,
      agentCount: json['agent_count'] ?? 0,
      unreadCount: json['unread'] ?? json['unread_count'] ?? 0,
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'])
          : null,
      mainThreadId: json['main_thread_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'channel_type': channelType,
      'icon': icon,
      'is_private': isPrivate,
      'member_count': memberCount,
      'agent_count': agentCount,
      'unread': unreadCount,
      'last_activity_at': lastActivityAt?.toIso8601String(),
    };
  }

  String get displayIcon {
    // If icon is a Lucide icon name (like "hash"), convert to character
    // Otherwise use the icon value directly (for emojis)
    if (icon != null && icon!.isNotEmpty) {
      // Map common Lucide icon names to characters
      switch (icon!.toLowerCase()) {
        case 'hash':
          return '#';
        case 'lock':
          return '🔒';
        case 'megaphone':
        case 'announcements':
          return '📢';
        case 'headphones':
        case 'support':
          return '🎧';
        case 'users':
          return '👥';
        case 'star':
          return '⭐';
        case 'heart':
          return '❤️';
        case 'message-circle':
          return '💬';
        default:
          // If it's a single character or emoji, use it directly
          if (icon!.length <= 2 || icon!.contains(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true))) {
            return icon!;
          }
          // Unknown icon name, fall back to hash
          return '#';
      }
    }
    if (isPrivate) return '🔒';
    switch (channelType) {
      case 'general':
        return '#';
      case 'announcements':
        return '📢';
      case 'support':
        return '🎧';
      default:
        return '#';
    }
  }
}

/// Hub thread for DMs and channels
class HubThread {
  final int id;
  final String threadType;
  final String? subject;
  final String displayName;
  final String status;
  final DateTime? lastActivityAt;
  final int messageCount;
  final int unreadCount;
  final List<HubParticipant> participants;

  HubThread({
    required this.id,
    required this.threadType,
    this.subject,
    required this.displayName,
    this.status = 'active',
    this.lastActivityAt,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.participants = const [],
  });

  factory HubThread.fromJson(Map<String, dynamic> json) {
    return HubThread(
      id: json['id'] ?? 0,
      threadType: json['thread_type'] ?? 'dm',
      subject: json['subject'],
      displayName: json['display_name'] ?? '',
      status: json['status'] ?? 'active',
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'])
          : null,
      messageCount: json['message_count'] ?? 0,
      unreadCount: json['unread_count'] ?? 0,
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => HubParticipant.fromJson(p))
              .toList() ??
          [],
    );
  }

  bool get isDm => threadType == 'dm';
  bool get isChannel => threadType == 'channel';
  bool get isWorkStream => threadType == 'work_stream';
}

/// Participant in a hub thread
class HubParticipant {
  final int id;
  final String participantType;
  final int participantId;
  final String? name;
  final String role;
  final bool isAgent;

  HubParticipant({
    required this.id,
    required this.participantType,
    required this.participantId,
    this.name,
    this.role = 'member',
    this.isAgent = false,
  });

  factory HubParticipant.fromJson(Map<String, dynamic> json) {
    return HubParticipant(
      id: json['id'] ?? 0,
      participantType: json['participant_type'] ?? json['type'] ?? 'User',
      participantId: json['participant_id'] ?? json['id'] ?? 0,
      name: json['name'],
      role: json['role'] ?? 'member',
      isAgent: json['is_agent'] ?? json['participant_type'] == 'AgentPlugin',
    );
  }
}

/// Message in a hub thread
class HubMessage {
  final int id;
  final String content;
  final String messageType;
  final int senderId;
  final String senderType;
  final String senderName;
  final DateTime createdAt;
  final bool edited;
  final Map<String, dynamic>? reactions;
  final int? replyToId;
  final List<Map<String, dynamic>>? attachments;
  final int? threadId;
  final int? channelId;

  HubMessage({
    required this.id,
    required this.content,
    this.messageType = 'text',
    required this.senderId,
    required this.senderType,
    required this.senderName,
    required this.createdAt,
    this.edited = false,
    this.reactions,
    this.replyToId,
    this.attachments,
    this.threadId,
    this.channelId,
  });

  factory HubMessage.fromJson(Map<String, dynamic> json) {
    // Handle nested sender object (server format) or flat fields (legacy/test format)
    final sender = json['sender'] as Map<String, dynamic>?;
    final senderId = sender?['id'] ?? json['sender_id'] ?? 0;
    final senderType = sender?['type'] ?? json['sender_type'] ?? 'User';
    final senderName = sender?['name'] ?? json['sender_name'] ?? 'Unknown';

    return HubMessage(
      id: json['id'] ?? 0,
      content: json['content'] ?? '',
      messageType: json['message_type'] ?? 'text',
      senderId: senderId is int ? senderId : int.tryParse(senderId.toString()) ?? 0,
      senderType: senderType.toString(),
      senderName: senderName.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      edited: json['edited'] ?? false,
      // Server may return reactions as [] (list) or {} (map) - normalize to map
      reactions: json['reactions'] is Map ? json['reactions'] as Map<String, dynamic> : null,
      replyToId: json['reply_to_id'],
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from(json['attachments'])
          : null,
      threadId: json['thread_id'] ?? json['hub_thread_id'],
      channelId: json['channel_id'] ?? json['hub_channel_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'message_type': messageType,
      'sender_id': senderId,
      'sender_type': senderType,
      'sender_name': senderName,
      'created_at': createdAt.toIso8601String(),
      'edited': edited,
      'reactions': reactions,
      'reply_to_id': replyToId,
      'attachments': attachments,
      'thread_id': threadId,
      'channel_id': channelId,
    };
  }

  bool get isFromUser => senderType == 'User';
  bool get isFromAgent => senderType == 'AgentPlugin';
  bool get isGif => messageType == 'gif';
  bool get hasAttachments => attachments != null && attachments!.isNotEmpty;
}

/// Team member (user in the entity)
class TeamMember {
  final int id;  // EntityUser id
  final int userId;  // User id (for DMs)
  final String firstName;
  final String lastName;
  final String email;
  final String? role;
  final String? avatarUrl;
  final String status;
  final String? statusMessage;
  final bool isOnline;

  TeamMember({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.role,
    this.avatarUrl,
    this.status = 'offline',
    this.statusMessage,
    this.isOnline = false,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? json['id'] ?? 0,  // Prefer user_id, fallback to id
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'],
      avatarUrl: json['avatar_url'],
      status: json['status'] ?? 'offline',
      statusMessage: json['status_message'],
      isOnline: json['is_online'] ?? json['status'] == 'online',
    );
  }

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }
}

/// DM thread info for listing
class DmThread {
  final int id;
  final String displayName;
  final HubParticipant? otherParticipant;
  final int unreadCount;
  final DateTime? lastActivityAt;
  final String? lastMessage;

  DmThread({
    required this.id,
    required this.displayName,
    this.otherParticipant,
    this.unreadCount = 0,
    this.lastActivityAt,
    this.lastMessage,
  });

  factory DmThread.fromJson(Map<String, dynamic> json) {
    return DmThread(
      id: json['id'] ?? 0,
      displayName: json['display_name'] ?? '',
      otherParticipant: json['participant'] != null
          ? HubParticipant.fromJson(json['participant'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'])
          : null,
      lastMessage: json['last_message'],
    );
  }
}
