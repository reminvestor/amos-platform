/// Eleven Labs API credentials for voice transcription
class ElevenLabsCredentials {
  final String apiKey;
  final String? websocketUrl;
  final Map<String, dynamic>? config;

  const ElevenLabsCredentials({
    required this.apiKey,
    this.websocketUrl,
    this.config,
  });

  factory ElevenLabsCredentials.fromJson(Map<String, dynamic> json) {
    return ElevenLabsCredentials(
      apiKey: json['api_key'] ?? json['apiKey'] ?? '',
      websocketUrl: json['websocket_url'] ?? json['websocketUrl'],
      config: json['config'],
    );
  }

  /// Default WebSocket URL for Eleven Labs Speech-to-Text realtime
  String get effectiveWebsocketUrl =>
      websocketUrl ?? 'wss://api.elevenlabs.io/v1/speech-to-text/realtime';
}

/// Deepgram API credentials (fallback)
class DeepgramCredentials {
  final String apiKey;
  final String? websocketUrl;

  const DeepgramCredentials({
    required this.apiKey,
    this.websocketUrl,
  });

  factory DeepgramCredentials.fromJson(Map<String, dynamic> json) {
    return DeepgramCredentials(
      apiKey: json['api_key'] ?? json['apiKey'] ?? '',
      websocketUrl: json['websocket_url'],
    );
  }

  String get effectiveWebsocketUrl =>
      websocketUrl ?? 'wss://api.deepgram.com/v1/listen';
}

/// Voice session information
class VoiceSession {
  final String sessionId;
  final String status;
  final String? websocketChannel;

  const VoiceSession({
    required this.sessionId,
    required this.status,
    this.websocketChannel,
  });

  factory VoiceSession.fromJson(Map<String, dynamic> json) {
    return VoiceSession(
      sessionId: json['session_id'] ?? json['id'] ?? '',
      status: json['status'] ?? 'created',
      websocketChannel: json['websocket_channel'],
    );
  }
}

/// Transcript result from STT service
class TranscriptResult {
  final String text;
  final bool isFinal;
  final double? confidence;
  final int? startTime;
  final int? endTime;

  const TranscriptResult({
    required this.text,
    required this.isFinal,
    this.confidence,
    this.startTime,
    this.endTime,
  });

  factory TranscriptResult.fromElevenLabs(Map<String, dynamic> json) {
    return TranscriptResult(
      text: json['transcript'] ?? json['text'] ?? '',
      isFinal: json['is_final'] ?? json['isFinal'] ?? false,
      confidence: json['confidence']?.toDouble(),
    );
  }

  factory TranscriptResult.fromDeepgram(Map<String, dynamic> json) {
    final channel = json['channel'];
    final alternatives = channel?['alternatives'] as List?;
    final firstAlt = alternatives?.isNotEmpty == true ? alternatives!.first : null;

    return TranscriptResult(
      text: firstAlt?['transcript'] ?? '',
      isFinal: json['is_final'] ?? false,
      confidence: firstAlt?['confidence']?.toDouble(),
    );
  }
}
