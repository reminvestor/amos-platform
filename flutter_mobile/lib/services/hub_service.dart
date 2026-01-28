import 'dart:async';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Service for Hub/Team Space API interactions
class HubService {
  final ApiClient _api = ApiClient();
  final _logger = Logger('HubService');

  /// Ensure we have a valid auth token before making hub requests
  Future<void> _ensureAuthenticated() async {
    final token = await _api.getAuthToken();
    if (token == null) {
      throw Exception('Not authenticated - please log in');
    }
  }

  // Channels

  /// Get all team channels
  Future<List<TeamChannel>> getChannels() async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/channels');
      // ApiClient.get() returns response.data directly, so response IS the data
      final List<dynamic> data = response is List ? response : (response['data'] ?? []);
      return data.map((json) => TeamChannel.fromJson(json)).toList();
    } catch (e) {
      _logger.error('Failed to get channels: $e');
      rethrow;
    }
  }

  /// Get messages for a channel
  Future<ChannelMessagesResponse> getChannelMessages(int channelId) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/channels/$channelId/messages');
      // ApiClient.get() returns response.data directly
      return ChannelMessagesResponse.fromJson(response);
    } catch (e) {
      _logger.error('Failed to get channel messages: $e');
      rethrow;
    }
  }

  /// Send a message to a channel
  Future<HubMessage> sendChannelMessage(int channelId, String content, {String messageType = 'text'}) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.post('/hub/channels/$channelId/messages', data: {
        'content': content,
        'message_type': messageType,
      });
      // ApiClient.post() returns response.data directly
      return HubMessage.fromJson(response['message']);
    } catch (e) {
      _logger.error('Failed to send channel message: $e');
      rethrow;
    }
  }

  /// Create a new channel
  Future<TeamChannel> createChannel({
    required String name,
    String? description,
    String channelType = 'general',
    bool isPrivate = false,
  }) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.post('/hub/channels', data: {
        'channel': {
          'name': name,
          'description': description,
          'channel_type': channelType,
          'is_private': isPrivate,
        },
      });
      // ApiClient.post() returns response.data directly
      return TeamChannel.fromJson(response['channel']);
    } catch (e) {
      _logger.error('Failed to create channel: $e');
      rethrow;
    }
  }

  /// Delete a channel
  Future<void> deleteChannel(int channelId) async {
    try {
      await _ensureAuthenticated();
      await _api.delete('/hub/channels/$channelId');
    } catch (e) {
      _logger.error('Failed to delete channel: $e');
      rethrow;
    }
  }

  // Direct Messages

  /// Get all DM threads
  Future<List<DmThread>> getDmThreads() async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/dms');
      // ApiClient.get() returns response.data directly, so response IS the data
      final List<dynamic> data = response is List ? response : (response['data'] ?? []);
      return data.map((json) => DmThread.fromJson(json)).toList();
    } catch (e) {
      _logger.error('Failed to get DM threads: $e');
      rethrow;
    }
  }

  /// Start or get a DM thread with a user or agent
  Future<DmThread> createDm({
    required String participantType,
    required int participantId,
    String? initialMessage,
  }) async {
    try {
      await _ensureAuthenticated();
      _logger.info('Creating DM: type=$participantType, id=$participantId');
      final response = await _api.post('/hub/dms', data: {
        'participant_type': participantType,
        'participant_id': participantId,
        'message': initialMessage,
      });
      // ApiClient.post() returns response.data directly
      _logger.info('Create DM response: $response');
      if (response['thread'] == null) {
        throw Exception('No thread returned from server: ${response['error'] ?? 'unknown error'}');
      }
      return DmThread.fromJson(response['thread']);
    } catch (e) {
      _logger.error('Failed to create DM: $e');
      rethrow;
    }
  }

  // Threads

  /// Get messages for a thread
  Future<ThreadMessagesResponse> getThreadMessages(int threadId) async {
    try {
      await _ensureAuthenticated();
      _logger.info('Getting thread messages for threadId: $threadId');
      final response = await _api.get('/hub/thread/$threadId');
      _logger.info('Thread response type: ${response.runtimeType}');
      _logger.info('Thread response: $response');
      // ApiClient.get() returns response.data directly
      return ThreadMessagesResponse.fromJson(response);
    } catch (e, stackTrace) {
      _logger.error('Failed to get thread messages: $e');
      _logger.error('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Send a message to a thread
  Future<HubMessage> sendThreadMessage(
    int threadId,
    String content, {
    String messageType = 'text',
    int? replyToId,
  }) async {
    try {
      await _ensureAuthenticated();
      _logger.info('Sending message to thread $threadId: "$content"');
      final response = await _api.post('/hub/thread/$threadId/messages', data: {
        'content': content,
        'message_type': messageType,
        'reply_to_id': replyToId,
      });
      _logger.info('Send message response type: ${response.runtimeType}');
      _logger.info('Send message response: $response');
      // ApiClient.post() returns response.data directly
      if (response['message'] == null) {
        throw Exception('No message in response: ${response['error'] ?? 'unknown error'}');
      }
      return HubMessage.fromJson(response['message']);
    } catch (e, stackTrace) {
      _logger.error('Failed to send thread message: $e');
      _logger.error('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Mark thread as read
  Future<void> markThreadRead(int threadId, {int? messageId}) async {
    try {
      await _api.post('/hub/thread/$threadId/mark_read', data: {
        'message_id': messageId,
      });
    } catch (e) {
      _logger.error('Failed to mark thread read: $e');
      rethrow;
    }
  }

  /// Archive a thread (hide from active list)
  Future<void> archiveThread(int threadId) async {
    try {
      await _ensureAuthenticated();
      await _api.post('/hub/thread/$threadId/archive');
      _logger.info('Archived thread $threadId');
    } catch (e) {
      _logger.error('Failed to archive thread: $e');
      rethrow;
    }
  }

  /// Unarchive a thread (restore to active list)
  Future<void> unarchiveThread(int threadId) async {
    try {
      await _ensureAuthenticated();
      await _api.post('/hub/thread/$threadId/unarchive');
      _logger.info('Unarchived thread $threadId');
    } catch (e) {
      _logger.error('Failed to unarchive thread: $e');
      rethrow;
    }
  }

  // Team Members

  /// Get team members (entity users)
  Future<List<TeamMember>> getTeamMembers() async {
    try {
      await _ensureAuthenticated();
      // Use /api/v1/team endpoint which returns { members: [...], pending_invites: [...] }
      final response = await _api.get('/api/v1/team');
      // ApiClient.get() returns response.data directly
      final List<dynamic> data = response is List
          ? response
          : response['members'] ?? [];
      return data.map((json) => TeamMember.fromJson(json)).toList();
    } catch (e) {
      _logger.error('Failed to get team members: $e');
      return [];
    }
  }

  // Agents

  /// Get available agents for Hub
  Future<List<Map<String, dynamic>>> getHubAgents() async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/agents');
      // ApiClient.get() returns response.data directly
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.error('Failed to get Hub agents: $e');
      rethrow;
    }
  }

  // Presence

  /// Get presence summary
  Future<Map<String, dynamic>> getPresence() async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/presence');
      // ApiClient.get() returns response.data directly
      return response;
    } catch (e) {
      _logger.error('Failed to get presence: $e');
      rethrow;
    }
  }

  /// Update presence status
  Future<void> updatePresence(String status, {String? message, String? emoji}) async {
    try {
      await _api.post('/hub/presence', data: {
        'status': status,
        'message': message,
        'emoji': emoji,
      });
    } catch (e) {
      _logger.error('Failed to update presence: $e');
      rethrow;
    }
  }

  /// Send heartbeat
  Future<void> heartbeat() async {
    try {
      await _api.post('/hub/heartbeat');
    } catch (e) {
      _logger.error('Failed to send heartbeat: $e');
      // Don't rethrow - heartbeat failures shouldn't break the app
    }
  }

  // Reactions

  /// Add reaction to message
  Future<void> addReaction(int messageId, String emoji) async {
    try {
      await _api.post('/hub/messages/$messageId/react', data: {
        'emoji': emoji,
      });
    } catch (e) {
      _logger.error('Failed to add reaction: $e');
      rethrow;
    }
  }

  /// Remove reaction from message
  Future<void> removeReaction(int messageId, String emoji) async {
    try {
      await _api.delete('/hub/messages/$messageId/react', data: {
        'emoji': emoji,
      });
    } catch (e) {
      _logger.error('Failed to remove reaction: $e');
      rethrow;
    }
  }

  // Activity

  /// Get hub activity feed
  Future<Map<String, dynamic>> getActivity() async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/activity');
      // ApiClient.get() returns response.data directly
      return response;
    } catch (e) {
      _logger.error('Failed to get activity: $e');
      rethrow;
    }
  }

  // Giphy

  /// Search Giphy for GIFs
  Future<List<GiphyGif>> searchGiphy(String query, {int limit = 20}) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/hub/giphy/search', queryParameters: {
        'q': query,
        'limit': limit,
      });
      // ApiClient.get() returns response.data directly
      if (response['success'] == true) {
        final List<dynamic> gifs = response['gifs'] ?? [];
        return gifs.map((g) => GiphyGif.fromJson(g)).toList();
      }
      return [];
    } catch (e) {
      _logger.error('Failed to search Giphy: $e');
      return [];
    }
  }

  // Team Invites

  /// Invite a team member by email
  Future<Map<String, dynamic>> inviteTeamMember({
    required String email,
    String role = 'member',
  }) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.post('/api/v1/team/invite', data: {
        'team_invite': {
          'email': email,
          'role': role,
        },
      });
      // ApiClient.post() returns response.data directly
      return response;
    } catch (e) {
      _logger.error('Failed to invite team member: $e');
      rethrow;
    }
  }

  /// Get team members with pending invites (uses new API)
  Future<Map<String, dynamic>> getTeamWithInvites() async {
    try {
      await _ensureAuthenticated();
      final response = await _api.get('/api/v1/team');
      return response;
    } catch (e) {
      _logger.error('Failed to get team with invites: $e');
      rethrow;
    }
  }

  /// Cancel a pending invite
  Future<Map<String, dynamic>> cancelInvite(int inviteId) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.delete('/api/v1/team/invite/$inviteId');
      return response;
    } catch (e) {
      _logger.error('Failed to cancel invite: $e');
      rethrow;
    }
  }

  /// Resend a pending invite
  Future<Map<String, dynamic>> resendInvite(int inviteId) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.post('/api/v1/team/invite/$inviteId/resend');
      return response;
    } catch (e) {
      _logger.error('Failed to resend invite: $e');
      rethrow;
    }
  }

  /// Remove a team member
  Future<Map<String, dynamic>> removeTeamMember(int entityUserId) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.delete('/api/v1/team/members/$entityUserId');
      return response;
    } catch (e) {
      _logger.error('Failed to remove team member: $e');
      rethrow;
    }
  }

  /// Update a team member's role
  Future<Map<String, dynamic>> updateTeamMemberRole(int entityUserId, String role) async {
    try {
      await _ensureAuthenticated();
      final response = await _api.patch('/api/v1/team/members/$entityUserId', data: {
        'entity_user': {
          'role': role,
        },
      });
      return response;
    } catch (e) {
      _logger.error('Failed to update team member role: $e');
      rethrow;
    }
  }
}

/// Response for channel messages request
class ChannelMessagesResponse {
  final TeamChannel channel;
  final int threadId;
  final List<HubMessage> messages;

  ChannelMessagesResponse({
    required this.channel,
    required this.threadId,
    required this.messages,
  });

  factory ChannelMessagesResponse.fromJson(Map<String, dynamic> json) {
    return ChannelMessagesResponse(
      channel: TeamChannel.fromJson(json['channel']),
      threadId: json['thread_id'],
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => HubMessage.fromJson(m))
              .toList() ??
          [],
    );
  }
}

/// Response for thread messages request
class ThreadMessagesResponse {
  final HubThread thread;
  final List<HubMessage> messages;
  final List<HubParticipant> participants;

  ThreadMessagesResponse({
    required this.thread,
    required this.messages,
    required this.participants,
  });

  factory ThreadMessagesResponse.fromJson(Map<String, dynamic> json) {
    return ThreadMessagesResponse(
      thread: HubThread.fromJson(json),
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => HubMessage.fromJson(m))
              .toList() ??
          [],
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => HubParticipant.fromJson(p))
              .toList() ??
          [],
    );
  }
}

/// Giphy GIF model
class GiphyGif {
  final String id;
  final String url;
  final String previewUrl;
  final String title;
  final int width;
  final int height;

  GiphyGif({
    required this.id,
    required this.url,
    required this.previewUrl,
    required this.title,
    required this.width,
    required this.height,
  });

  factory GiphyGif.fromJson(Map<String, dynamic> json) {
    return GiphyGif(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      previewUrl: json['preview_url'] ?? json['url'] ?? '',
      title: json['title'] ?? '',
      width: json['width'] ?? 200,
      height: json['height'] ?? 200,
    );
  }
}
