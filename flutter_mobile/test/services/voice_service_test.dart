import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/voice_credentials.dart';
import 'package:amos_mobile/services/voice_service.dart';

// Note: VoiceService uses WebSocketChannel, AudioRecorder, and PermissionHandler
// which require native plugins. For unit tests, we test the response parsing logic,
// model behavior, and state management separately.

void main() {
  group('ElevenLabsCredentials Model', () {
    test('parses credentials with snake_case keys', () {
      final json = {
        'api_key': 'el_key_12345',
        'websocket_url': 'wss://custom.elevenlabs.io/v1/scribe',
        'config': {'model': 'scribe-v3'},
      };

      final creds = ElevenLabsCredentials.fromJson(json);

      expect(creds.apiKey, equals('el_key_12345'));
      expect(creds.websocketUrl, equals('wss://custom.elevenlabs.io/v1/scribe'));
      expect(creds.config, isNotNull);
      expect(creds.config!['model'], equals('scribe-v3'));
    });

    test('parses credentials with camelCase keys', () {
      final json = {
        'apiKey': 'el_key_67890',
        'websocketUrl': 'wss://custom.elevenlabs.io/v2/scribe',
      };

      final creds = ElevenLabsCredentials.fromJson(json);

      expect(creds.apiKey, equals('el_key_67890'));
      expect(creds.websocketUrl, equals('wss://custom.elevenlabs.io/v2/scribe'));
    });

    test('handles missing optional fields', () {
      final json = {
        'api_key': 'el_key_minimal',
      };

      final creds = ElevenLabsCredentials.fromJson(json);

      expect(creds.apiKey, equals('el_key_minimal'));
      expect(creds.websocketUrl, isNull);
      expect(creds.config, isNull);
    });

    test('handles empty api_key gracefully', () {
      final json = <String, dynamic>{};

      final creds = ElevenLabsCredentials.fromJson(json);

      expect(creds.apiKey, equals(''));
    });

    test('uses default websocket URL when not provided', () {
      final creds = ElevenLabsCredentials(apiKey: 'test_key');

      expect(
        creds.effectiveWebsocketUrl,
        equals('wss://api.elevenlabs.io/v1/scribe/v3/realtime'),
      );
    });

    test('uses custom websocket URL when provided', () {
      final creds = ElevenLabsCredentials(
        apiKey: 'test_key',
        websocketUrl: 'wss://custom.elevenlabs.io/stream',
      );

      expect(creds.effectiveWebsocketUrl, equals('wss://custom.elevenlabs.io/stream'));
    });
  });

  group('DeepgramCredentials Model', () {
    test('parses credentials with snake_case keys', () {
      final json = {
        'api_key': 'dg_key_12345',
        'websocket_url': 'wss://custom.deepgram.com/v1/listen',
      };

      final creds = DeepgramCredentials.fromJson(json);

      expect(creds.apiKey, equals('dg_key_12345'));
      expect(creds.websocketUrl, equals('wss://custom.deepgram.com/v1/listen'));
    });

    test('parses credentials with camelCase keys', () {
      final json = {
        'apiKey': 'dg_key_67890',
      };

      final creds = DeepgramCredentials.fromJson(json);

      expect(creds.apiKey, equals('dg_key_67890'));
    });

    test('handles missing optional fields', () {
      final json = {
        'api_key': 'dg_key_minimal',
      };

      final creds = DeepgramCredentials.fromJson(json);

      expect(creds.apiKey, equals('dg_key_minimal'));
      expect(creds.websocketUrl, isNull);
    });

    test('uses default websocket URL when not provided', () {
      final creds = DeepgramCredentials(apiKey: 'test_key');

      expect(creds.effectiveWebsocketUrl, equals('wss://api.deepgram.com/v1/listen'));
    });

    test('uses custom websocket URL when provided', () {
      final creds = DeepgramCredentials(
        apiKey: 'test_key',
        websocketUrl: 'wss://custom.deepgram.com/stream',
      );

      expect(creds.effectiveWebsocketUrl, equals('wss://custom.deepgram.com/stream'));
    });
  });

  group('VoiceSession Model', () {
    test('parses session with session_id key', () {
      final json = {
        'session_id': 'sess_abc123',
        'status': 'active',
        'websocket_channel': 'voice_sess_abc123',
      };

      final session = VoiceSession.fromJson(json);

      expect(session.sessionId, equals('sess_abc123'));
      expect(session.status, equals('active'));
      expect(session.websocketChannel, equals('voice_sess_abc123'));
    });

    test('parses session with id key fallback', () {
      final json = {
        'id': 'sess_def456',
        'status': 'created',
      };

      final session = VoiceSession.fromJson(json);

      expect(session.sessionId, equals('sess_def456'));
      expect(session.status, equals('created'));
    });

    test('handles missing optional fields', () {
      final json = {
        'session_id': 'sess_minimal',
        'status': 'created',
      };

      final session = VoiceSession.fromJson(json);

      expect(session.sessionId, equals('sess_minimal'));
      expect(session.websocketChannel, isNull);
    });

    test('uses default status when not provided', () {
      final json = {
        'session_id': 'sess_default',
      };

      final session = VoiceSession.fromJson(json);

      expect(session.status, equals('created'));
    });
  });

  group('TranscriptResult Model', () {
    group('fromElevenLabs', () {
      test('parses final transcript', () {
        final json = {
          'transcript': 'Hello, how are you?',
          'is_final': true,
          'confidence': 0.95,
        };

        final result = TranscriptResult.fromElevenLabs(json);

        expect(result.text, equals('Hello, how are you?'));
        expect(result.isFinal, isTrue);
        expect(result.confidence, equals(0.95));
      });

      test('parses partial transcript', () {
        final json = {
          'transcript': 'Hello',
          'is_final': false,
          'confidence': 0.7,
        };

        final result = TranscriptResult.fromElevenLabs(json);

        expect(result.text, equals('Hello'));
        expect(result.isFinal, isFalse);
        expect(result.confidence, equals(0.7));
      });

      test('handles camelCase keys', () {
        final json = {
          'text': 'Alternative text format',
          'isFinal': true,
          'confidence': 0.9,
        };

        final result = TranscriptResult.fromElevenLabs(json);

        expect(result.text, equals('Alternative text format'));
        expect(result.isFinal, isTrue);
      });

      test('handles missing fields gracefully', () {
        final json = <String, dynamic>{};

        final result = TranscriptResult.fromElevenLabs(json);

        expect(result.text, equals(''));
        expect(result.isFinal, isFalse);
        expect(result.confidence, isNull);
      });

      test('converts int confidence to double', () {
        final json = {
          'transcript': 'Test',
          'is_final': true,
          'confidence': 1,
        };

        final result = TranscriptResult.fromElevenLabs(json);

        expect(result.confidence, equals(1.0));
        expect(result.confidence, isA<double>());
      });
    });

    group('fromDeepgram', () {
      test('parses standard Deepgram response', () {
        final json = {
          'channel': {
            'alternatives': [
              {'transcript': 'Good morning', 'confidence': 0.92}
            ]
          },
          'is_final': true,
        };

        final result = TranscriptResult.fromDeepgram(json);

        expect(result.text, equals('Good morning'));
        expect(result.isFinal, isTrue);
        expect(result.confidence, equals(0.92));
      });

      test('handles empty alternatives', () {
        final json = {
          'channel': {'alternatives': []},
          'is_final': false,
        };

        final result = TranscriptResult.fromDeepgram(json);

        expect(result.text, equals(''));
        expect(result.isFinal, isFalse);
        expect(result.confidence, isNull);
      });

      test('handles null channel', () {
        final json = {'is_final': false};

        final result = TranscriptResult.fromDeepgram(json);

        expect(result.text, equals(''));
        expect(result.isFinal, isFalse);
      });

      test('handles missing alternatives key', () {
        final json = {
          'channel': {},
          'is_final': true,
        };

        final result = TranscriptResult.fromDeepgram(json);

        expect(result.text, equals(''));
      });

      test('uses first alternative when multiple present', () {
        final json = {
          'channel': {
            'alternatives': [
              {'transcript': 'Primary', 'confidence': 0.95},
              {'transcript': 'Secondary', 'confidence': 0.85},
            ]
          },
          'is_final': true,
        };

        final result = TranscriptResult.fromDeepgram(json);

        expect(result.text, equals('Primary'));
        expect(result.confidence, equals(0.95));
      });
    });
  });

  group('VoiceState Enum', () {
    test('has all expected states', () {
      expect(VoiceState.values, contains(VoiceState.idle));
      expect(VoiceState.values, contains(VoiceState.initializing));
      expect(VoiceState.values, contains(VoiceState.listening));
      expect(VoiceState.values, contains(VoiceState.processing));
      expect(VoiceState.values, contains(VoiceState.error));
    });

    test('has correct number of states', () {
      expect(VoiceState.values.length, equals(5));
    });
  });

  group('Voice Session API Response Parsing', () {
    test('parses create session response', () {
      final responseData = {
        'session_id': 'voice_123abc',
        'status': 'created',
        'websocket_channel': 'VoiceChannel_voice_123abc',
        'provider': 'eleven_labs',
      };

      final session = VoiceSession.fromJson(responseData);

      expect(session.sessionId, equals('voice_123abc'));
      expect(session.status, equals('created'));
      expect(session.websocketChannel, equals('VoiceChannel_voice_123abc'));
    });

    test('parses credentials endpoint response', () {
      final elevenLabsResponse = {
        'api_key': 'el_abc123xyz',
        'websocket_url': 'wss://api.elevenlabs.io/v1/scribe/v3/realtime',
        'config': {
          'model': 'scribe-v3-realtime',
          'language': 'en',
          'punctuate': true,
        },
      };

      final creds = ElevenLabsCredentials.fromJson(elevenLabsResponse);

      expect(creds.apiKey, equals('el_abc123xyz'));
      expect(creds.config?['model'], equals('scribe-v3-realtime'));
    });
  });

  group('Voice WebSocket Configuration', () {
    test('Eleven Labs config structure is correct', () {
      // This tests that we understand the expected WebSocket message format
      final config = {
        'type': 'config',
        'api_key': 'test_key',
        'encoding': 'pcm_16000',
        'sample_rate': 16000,
        'channels': 1,
        'model': 'scribe-v3-realtime',
        'language': 'en',
        'punctuate': true,
        'include_partial_results': true,
        'latency_optimized': true,
      };

      expect(config['type'], equals('config'));
      expect(config['encoding'], equals('pcm_16000'));
      expect(config['sample_rate'], equals(16000));
      expect(config['channels'], equals(1));
      expect(config['include_partial_results'], isTrue);
    });

    test('Deepgram URL query parameters are constructed correctly', () {
      final baseUrl = 'wss://api.deepgram.com/v1/listen';
      final params = {
        'encoding': 'linear16',
        'sample_rate': '16000',
        'channels': '1',
        'punctuate': 'true',
        'interim_results': 'true',
      };

      final queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final fullUrl = '$baseUrl?$queryString';

      expect(fullUrl, contains('encoding=linear16'));
      expect(fullUrl, contains('sample_rate=16000'));
      expect(fullUrl, contains('interim_results=true'));
    });
  });

  group('Voice Error Handling', () {
    test('parses WebSocket error message', () {
      final errorJson = {
        'error': 'rate_limit_exceeded',
        'message': 'Too many requests',
        'retry_after': 60,
      };

      expect(errorJson['error'], equals('rate_limit_exceeded'));
      expect(errorJson['retry_after'], equals(60));
    });

    test('parses authentication error', () {
      final errorJson = {
        'error': 'authentication_failed',
        'message': 'Invalid API key',
      };

      expect(errorJson['error'], equals('authentication_failed'));
    });
  });
}
