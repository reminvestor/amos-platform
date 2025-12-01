import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/models/voice_credentials.dart';
import 'package:amos_mobile/utils/logger.dart';

enum VoiceState {
  idle,
  initializing,
  listening,
  processing,
  error,
}

class VoiceService {
  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AudioRecorder _recorder = AudioRecorder();

  WebSocketChannel? _elevenLabsChannel;
  WebSocketChannel? _deepgramChannel;
  String? _sessionId;
  VoiceState _state = VoiceState.idle;
  bool _useDeepgramFallback = false;

  // Stream controllers
  final _transcriptController = StreamController<TranscriptResult>.broadcast();
  final _stateController = StreamController<VoiceState>.broadcast();

  VoiceService() : _dio = Dio();

  // Public getters
  VoiceState get state => _state;
  Stream<TranscriptResult> get transcriptStream => _transcriptController.stream;
  Stream<VoiceState> get stateStream => _stateController.stream;
  bool get isListening => _state == VoiceState.listening;

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return false;
  }

  /// Check if microphone is available
  Future<bool> isMicrophoneAvailable() async {
    return await _recorder.hasPermission();
  }

  /// Create a voice session
  Future<VoiceSession> createSession() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await _dio.post(
        '${Env.apiBaseUrl}/api/voice/sessions',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      final session = VoiceSession.fromJson(response.data);
      _sessionId = session.sessionId;
      AppLogger.info('Voice session created: $_sessionId');
      return session;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create voice session', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get Eleven Labs credentials
  Future<ElevenLabsCredentials> getElevenLabsCredentials() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || _sessionId == null) {
        throw Exception('Not authenticated or no session');
      }

      final response = await _dio.get(
        '${Env.apiBaseUrl}/api/voice/sessions/$_sessionId/eleven_labs_credentials',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return ElevenLabsCredentials.fromJson(response.data);
    } catch (e) {
      AppLogger.error('Failed to get Eleven Labs credentials', error: e);
      rethrow;
    }
  }

  /// Get Deepgram credentials (fallback)
  Future<DeepgramCredentials> getDeepgramCredentials() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null || _sessionId == null) {
        throw Exception('Not authenticated or no session');
      }

      final response = await _dio.get(
        '${Env.apiBaseUrl}/api/voice/sessions/$_sessionId/deepgram_key',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return DeepgramCredentials.fromJson(response.data);
    } catch (e) {
      AppLogger.error('Failed to get Deepgram credentials', error: e);
      rethrow;
    }
  }

  /// Start voice input
  Future<void> startListening() async {
    if (_state == VoiceState.listening) return;

    _setState(VoiceState.initializing);

    try {
      // Check permission
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Microphone permission denied');
      }

      // Create session if needed
      if (_sessionId == null) {
        await createSession();
      }

      // Try Eleven Labs first, fall back to Deepgram
      try {
        final creds = await getElevenLabsCredentials();
        await _connectToElevenLabs(creds);
        _useDeepgramFallback = false;
      } catch (e) {
        AppLogger.warning('Eleven Labs unavailable, trying Deepgram fallback');
        final creds = await getDeepgramCredentials();
        await _connectToDeepgram(creds);
        _useDeepgramFallback = true;
      }

      // Start recording
      await _startRecording();

      _setState(VoiceState.listening);
      AppLogger.info('Voice listening started (${_useDeepgramFallback ? "Deepgram" : "Eleven Labs"})');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to start listening', error: e, stackTrace: stackTrace);
      _setState(VoiceState.error);
      rethrow;
    }
  }

  /// Stop voice input
  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;

    _setState(VoiceState.processing);

    try {
      // Stop recording
      await _recorder.stop();

      // Close WebSocket connections
      await _elevenLabsChannel?.sink.close();
      await _deepgramChannel?.sink.close();
      _elevenLabsChannel = null;
      _deepgramChannel = null;

      _setState(VoiceState.idle);
      AppLogger.info('Voice listening stopped');
    } catch (e) {
      AppLogger.error('Error stopping voice', error: e);
      _setState(VoiceState.idle);
    }
  }

  /// End voice session
  Future<void> endSession() async {
    await stopListening();

    if (_sessionId != null) {
      try {
        final token = await _storage.read(key: 'auth_token');
        await _dio.patch(
          '${Env.apiBaseUrl}/api/voice/sessions/$_sessionId/end',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        AppLogger.info('Voice session ended: $_sessionId');
      } catch (e) {
        AppLogger.warning('Failed to end voice session: $e');
      }
      _sessionId = null;
    }
  }

  /// Connect to Eleven Labs WebSocket
  Future<void> _connectToElevenLabs(ElevenLabsCredentials creds) async {
    final uri = Uri.parse(creds.effectiveWebsocketUrl);
    _elevenLabsChannel = WebSocketChannel.connect(uri);

    // Send configuration
    _elevenLabsChannel!.sink.add(jsonEncode({
      'type': 'config',
      'api_key': creds.apiKey,
      'encoding': 'pcm_16000',
      'sample_rate': 16000,
      'channels': 1,
      'model': 'scribe-v3-realtime',
      'language': 'en',
      'punctuate': true,
      'include_partial_results': true,
      'latency_optimized': true,
    }));

    // Listen for responses
    _elevenLabsChannel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String);
          if (json['transcript'] != null) {
            final result = TranscriptResult.fromElevenLabs(json);
            _transcriptController.add(result);
          }
        } catch (e) {
          AppLogger.warning('Error parsing Eleven Labs response: $e');
        }
      },
      onError: (error) {
        AppLogger.error('Eleven Labs WebSocket error', error: error);
        _setState(VoiceState.error);
      },
      onDone: () {
        AppLogger.info('Eleven Labs WebSocket closed');
      },
    );
  }

  /// Connect to Deepgram WebSocket (fallback)
  Future<void> _connectToDeepgram(DeepgramCredentials creds) async {
    final uri = Uri.parse(
      '${creds.effectiveWebsocketUrl}?encoding=linear16&sample_rate=16000&channels=1&punctuate=true&interim_results=true'
    );

    _deepgramChannel = WebSocketChannel.connect(
      uri,
      protocols: ['token', creds.apiKey],
    );

    // Listen for responses
    _deepgramChannel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String);
          if (json['channel'] != null) {
            final result = TranscriptResult.fromDeepgram(json);
            if (result.text.isNotEmpty) {
              _transcriptController.add(result);
            }
          }
        } catch (e) {
          AppLogger.warning('Error parsing Deepgram response: $e');
        }
      },
      onError: (error) {
        AppLogger.error('Deepgram WebSocket error', error: error);
        _setState(VoiceState.error);
      },
      onDone: () {
        AppLogger.info('Deepgram WebSocket closed');
      },
    );
  }

  /// Start audio recording and stream to STT
  Future<void> _startRecording() async {
    // Configure for 16kHz mono PCM
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    // Stream audio to appropriate service
    stream.listen((data) {
      _sendAudioChunk(Uint8List.fromList(data));
    });
  }

  /// Send audio chunk to active STT service
  void _sendAudioChunk(Uint8List audioData) {
    if (_useDeepgramFallback) {
      _deepgramChannel?.sink.add(audioData);
    } else {
      _elevenLabsChannel?.sink.add(audioData);
    }
  }

  void _setState(VoiceState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Dispose resources
  void dispose() {
    endSession();
    _transcriptController.close();
    _stateController.close();
    _recorder.dispose();
  }
}
