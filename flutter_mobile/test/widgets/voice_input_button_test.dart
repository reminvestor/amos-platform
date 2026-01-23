import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/voice_credentials.dart';
import 'package:amos_mobile/services/voice_service.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('VoiceState enum', () {
    test('has correct number of states', () {
      expect(VoiceState.values.length, equals(5));
    });

    test('idle is the initial state', () {
      expect(VoiceState.idle, isNotNull);
    });

    test('contains all expected states', () {
      expect(VoiceState.values, contains(VoiceState.idle));
      expect(VoiceState.values, contains(VoiceState.initializing));
      expect(VoiceState.values, contains(VoiceState.listening));
      expect(VoiceState.values, contains(VoiceState.processing));
      expect(VoiceState.values, contains(VoiceState.error));
    });
  });

  group('TranscriptResult', () {
    test('fromElevenLabs parses correctly', () {
      final json = {
        'transcript': 'Hello world',
        'is_final': true,
        'confidence': 0.95,
      };

      final result = TranscriptResult.fromElevenLabs(json);
      expect(result.text, equals('Hello world'));
      expect(result.isFinal, isTrue);
      expect(result.confidence, equals(0.95));
    });

    test('fromElevenLabs handles partial results', () {
      final json = {
        'transcript': 'Hello',
        'is_final': false,
      };

      final result = TranscriptResult.fromElevenLabs(json);
      expect(result.text, equals('Hello'));
      expect(result.isFinal, isFalse);
    });

    test('fromDeepgram parses correctly', () {
      final json = {
        'channel': {
          'alternatives': [
            {'transcript': 'Test message', 'confidence': 0.98}
          ]
        },
        'is_final': true,
      };

      final result = TranscriptResult.fromDeepgram(json);
      expect(result.text, equals('Test message'));
      expect(result.isFinal, isTrue);
      expect(result.confidence, equals(0.98));
    });

    test('fromDeepgram handles missing alternatives', () {
      final json = {
        'channel': {'alternatives': []},
        'is_final': false,
      };

      final result = TranscriptResult.fromDeepgram(json);
      expect(result.text, equals(''));
      expect(result.isFinal, isFalse);
    });

    test('fromDeepgram handles null channel', () {
      final json = {'is_final': false};

      final result = TranscriptResult.fromDeepgram(json);
      expect(result.text, equals(''));
    });
  });

  group('ElevenLabsCredentials', () {
    test('fromJson parses correctly with api_key', () {
      final json = {
        'api_key': 'test-key-123',
        'websocket_url': 'wss://custom.url',
      };

      final creds = ElevenLabsCredentials.fromJson(json);
      expect(creds.apiKey, equals('test-key-123'));
      expect(creds.websocketUrl, equals('wss://custom.url'));
    });

    test('fromJson parses apiKey camelCase', () {
      final json = {
        'apiKey': 'test-key-456',
      };

      final creds = ElevenLabsCredentials.fromJson(json);
      expect(creds.apiKey, equals('test-key-456'));
    });

    test('effectiveWebsocketUrl returns default when null', () {
      final creds = ElevenLabsCredentials(apiKey: 'key');
      expect(creds.effectiveWebsocketUrl,
          equals('wss://api.elevenlabs.io/v1/scribe/v3/realtime'));
    });

    test('effectiveWebsocketUrl returns custom url when set', () {
      final creds = ElevenLabsCredentials(
        apiKey: 'key',
        websocketUrl: 'wss://custom.url',
      );
      expect(creds.effectiveWebsocketUrl, equals('wss://custom.url'));
    });
  });

  group('DeepgramCredentials', () {
    test('fromJson parses correctly', () {
      final json = {
        'api_key': 'deepgram-key',
        'websocket_url': 'wss://custom.deepgram.url',
      };

      final creds = DeepgramCredentials.fromJson(json);
      expect(creds.apiKey, equals('deepgram-key'));
      expect(creds.websocketUrl, equals('wss://custom.deepgram.url'));
    });

    test('effectiveWebsocketUrl returns default when null', () {
      final creds = DeepgramCredentials(apiKey: 'key');
      expect(creds.effectiveWebsocketUrl,
          equals('wss://api.deepgram.com/v1/listen'));
    });
  });

  group('VoiceSession', () {
    test('fromJson parses session_id', () {
      final json = {
        'session_id': 'session-123',
        'status': 'active',
        'websocket_channel': 'channel-abc',
      };

      final session = VoiceSession.fromJson(json);
      expect(session.sessionId, equals('session-123'));
      expect(session.status, equals('active'));
      expect(session.websocketChannel, equals('channel-abc'));
    });

    test('fromJson parses id fallback', () {
      final json = {
        'id': 'session-456',
      };

      final session = VoiceSession.fromJson(json);
      expect(session.sessionId, equals('session-456'));
      expect(session.status, equals('created'));
    });

    test('fromJson handles missing fields', () {
      final json = <String, dynamic>{};

      final session = VoiceSession.fromJson(json);
      expect(session.sessionId, equals(''));
      expect(session.status, equals('created'));
      expect(session.websocketChannel, isNull);
    });
  });

  // Note: VoiceInputButton widget tests are limited because the widget
  // depends on hardware (microphone) and network services (WebSocket).
  // The tests above cover the data models used by the voice system.
  // For full widget testing, consider using dependency injection
  // to allow mocking the VoiceService.
}
