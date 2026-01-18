import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/voice_credentials.dart';

void main() {
  group('ElevenLabsCredentials', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'api_key': 'el-api-key-123',
        'websocket_url': 'wss://custom.elevenlabs.io/v1/scribe',
        'config': {'language': 'en-US'},
      };

      final credentials = ElevenLabsCredentials.fromJson(json);

      expect(credentials.apiKey, equals('el-api-key-123'));
      expect(credentials.websocketUrl, equals('wss://custom.elevenlabs.io/v1/scribe'));
      expect(credentials.config, equals({'language': 'en-US'}));
    });

    test('fromJson handles camelCase keys', () {
      final json = {
        'apiKey': 'el-api-key-456',
        'websocketUrl': 'wss://custom.url.io',
      };

      final credentials = ElevenLabsCredentials.fromJson(json);

      expect(credentials.apiKey, equals('el-api-key-456'));
      expect(credentials.websocketUrl, equals('wss://custom.url.io'));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final credentials = ElevenLabsCredentials.fromJson(json);

      expect(credentials.apiKey, equals(''));
      expect(credentials.websocketUrl, isNull);
      expect(credentials.config, isNull);
    });

    test('effectiveWebsocketUrl returns custom URL when provided', () {
      const credentials = ElevenLabsCredentials(
        apiKey: 'key',
        websocketUrl: 'wss://custom.url.io',
      );

      expect(credentials.effectiveWebsocketUrl, equals('wss://custom.url.io'));
    });

    test('effectiveWebsocketUrl returns default URL when not provided', () {
      const credentials = ElevenLabsCredentials(apiKey: 'key');

      expect(
        credentials.effectiveWebsocketUrl,
        equals('wss://api.elevenlabs.io/v1/scribe/v3/realtime'),
      );
    });
  });

  group('DeepgramCredentials', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'api_key': 'dg-api-key-123',
        'websocket_url': 'wss://custom.deepgram.io/v1/listen',
      };

      final credentials = DeepgramCredentials.fromJson(json);

      expect(credentials.apiKey, equals('dg-api-key-123'));
      expect(credentials.websocketUrl, equals('wss://custom.deepgram.io/v1/listen'));
    });

    test('fromJson handles camelCase apiKey', () {
      final json = {
        'apiKey': 'dg-api-key-456',
      };

      final credentials = DeepgramCredentials.fromJson(json);

      expect(credentials.apiKey, equals('dg-api-key-456'));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final credentials = DeepgramCredentials.fromJson(json);

      expect(credentials.apiKey, equals(''));
      expect(credentials.websocketUrl, isNull);
    });

    test('effectiveWebsocketUrl returns custom URL when provided', () {
      const credentials = DeepgramCredentials(
        apiKey: 'key',
        websocketUrl: 'wss://custom.deepgram.io',
      );

      expect(credentials.effectiveWebsocketUrl, equals('wss://custom.deepgram.io'));
    });

    test('effectiveWebsocketUrl returns default URL when not provided', () {
      const credentials = DeepgramCredentials(apiKey: 'key');

      expect(
        credentials.effectiveWebsocketUrl,
        equals('wss://api.deepgram.com/v1/listen'),
      );
    });
  });

  group('VoiceSession', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'session_id': 'session-123',
        'status': 'active',
        'websocket_channel': 'channel-456',
      };

      final session = VoiceSession.fromJson(json);

      expect(session.sessionId, equals('session-123'));
      expect(session.status, equals('active'));
      expect(session.websocketChannel, equals('channel-456'));
    });

    test('fromJson handles id as fallback for session_id', () {
      final json = {
        'id': 'session-789',
        'status': 'created',
      };

      final session = VoiceSession.fromJson(json);

      expect(session.sessionId, equals('session-789'));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final session = VoiceSession.fromJson(json);

      expect(session.sessionId, equals(''));
      expect(session.status, equals('created'));
      expect(session.websocketChannel, isNull);
    });
  });

  group('TranscriptResult', () {
    test('fromElevenLabs parses complete JSON correctly', () {
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

    test('fromElevenLabs handles alternate key names', () {
      final json = {
        'text': 'Hi there',
        'isFinal': true,
      };

      final result = TranscriptResult.fromElevenLabs(json);

      expect(result.text, equals('Hi there'));
      expect(result.isFinal, isTrue);
    });

    test('fromElevenLabs handles missing values', () {
      final json = <String, dynamic>{};

      final result = TranscriptResult.fromElevenLabs(json);

      expect(result.text, equals(''));
      expect(result.isFinal, isFalse);
      expect(result.confidence, isNull);
    });

    test('fromDeepgram parses complete JSON correctly', () {
      final json = {
        'channel': {
          'alternatives': [
            {'transcript': 'Hello from Deepgram', 'confidence': 0.98}
          ]
        },
        'is_final': true,
      };

      final result = TranscriptResult.fromDeepgram(json);

      expect(result.text, equals('Hello from Deepgram'));
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
      final json = {
        'is_final': false,
      };

      final result = TranscriptResult.fromDeepgram(json);

      expect(result.text, equals(''));
      expect(result.isFinal, isFalse);
      expect(result.confidence, isNull);
    });

    test('constructor creates instance correctly', () {
      const result = TranscriptResult(
        text: 'Test text',
        isFinal: true,
        confidence: 0.99,
        startTime: 1000,
        endTime: 2000,
      );

      expect(result.text, equals('Test text'));
      expect(result.isFinal, isTrue);
      expect(result.confidence, equals(0.99));
      expect(result.startTime, equals(1000));
      expect(result.endTime, equals(2000));
    });
  });
}
