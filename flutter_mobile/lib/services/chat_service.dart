import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/models/uploaded_file.dart';
import 'package:amos_mobile/services/storage_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class ChatService {
  final Dio _dio;
  final StorageService _storage = StorageService.instance;

  ChatService() : _dio = Dio();

  /// Create a new chat session
  Future<String> createNewSession() async {
    try {
      final token = await _storage.read('auth_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await _dio.post(
        '${Env.apiBaseUrl}/scout/new_session',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      final sessionId = response.data['session_id'] ??
          'mobile_${DateTime.now().millisecondsSinceEpoch}';
      AppLogger.info('Created new chat session: $sessionId');
      return sessionId;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create new session', error: e, stackTrace: stackTrace);
      // Fall back to local session ID generation
      return 'mobile_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Send message to Scout and get streaming response
  ///
  /// Parameters:
  /// - [message]: The user's message
  /// - [sessionId]: Chat session identifier
  /// - [model]: AI model to use (e.g., 'claude-sonnet-4-5')
  /// - [files]: List of uploaded files to include
  Stream<ChatStreamEvent> sendMessage(
    String message, {
    String? sessionId,
    String? model,
    List<UploadedFile>? files,
  }) async* {
    try {
      // Get auth token
      final token = await _storage.read('auth_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Prepare request
      final requestData = {
        'message': message,
        'session_id': sessionId ?? 'mobile_${DateTime.now().millisecondsSinceEpoch}',
        if (model != null) 'model': model,
        if (files != null && files.isNotEmpty)
          'file_urls': files.map((f) => f.toJson()).toList(),
      };

      AppLogger.info('Sending chat message to Scout: $message');
      if (model != null) AppLogger.info('Using model: $model');
      if (files != null && files.isNotEmpty) {
        AppLogger.info('With ${files.length} attached files');
      }

      // Create request with SSE support
      final response = await _dio.post(
        '${Env.apiBaseUrl}/scout/chat_stream',
        data: requestData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'Authorization': 'Bearer $token',
          },
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5), // Longer timeout for AI responses
        ),
      );

      // Process SSE stream
      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (var chunk in stream) {
        buffer += utf8.decode(chunk);

        // Process complete SSE events
        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);

          // Parse SSE data lines
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6);

            try {
              final data = jsonDecode(dataStr);
              final eventType = data['type'];

              // Handle different event types from Scout controller
              if (eventType == 'content' && data['content'] != null) {
                // Streaming content chunks
                yield ChatStreamEvent.content(data['content']);
              } else if (eventType == 'update' && data['message'] != null) {
                // Update messages
                yield ChatStreamEvent.content(data['message']);
              } else if (eventType == 'response' && data['data'] != null) {
                // Final response data
                final responseData = data['data'];
                if (responseData['content'] != null) {
                  yield ChatStreamEvent.content(responseData['content']);
                }
              } else if (eventType == 'transient' && data['message'] != null) {
                // Transient status messages
                yield ChatStreamEvent.status(data['message']);
              } else if (eventType == 'tool_start') {
                // Tool execution started
                yield ChatStreamEvent.toolStart(
                  data['tool_name'] ?? 'tool',
                  data['message'],
                );
              } else if (eventType == 'tool_end') {
                // Tool execution ended
                yield ChatStreamEvent.toolEnd(
                  data['tool_name'] ?? 'tool',
                  data['message'],
                );
              } else if (eventType == 'load_canvas') {
                // Canvas loading event
                yield ChatStreamEvent.canvas(
                  data['canvas_type'] ?? 'unknown',
                  data['data'],
                );
              } else if (eventType == 'error') {
                AppLogger.error('Scout error: ${data['message']}');
                yield ChatStreamEvent.error(data['message'] ?? 'Chat error');
              } else if (eventType == 'question_added') {
                // Agent question added to queue
                AppLogger.info('Question added: ${data['question']}');
                yield ChatStreamEvent.question(data as Map<String, dynamic>);
              } else if (eventType == 'agent_complete') {
                // Agent completed a task
                AppLogger.info('Agent completed: ${data['message']}');
                yield ChatStreamEvent.completion(data as Map<String, dynamic>);
              }
            } catch (e) {
              // If not JSON, might be a plain text message
              if (dataStr.isNotEmpty && dataStr != '[DONE]') {
                yield ChatStreamEvent.content(dataStr);
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Chat service error', error: e, stackTrace: stackTrace);
      yield ChatStreamEvent.error('Failed to send message: ${e.toString()}');
    }
  }

  /// Send message and get complete response (non-streaming)
  Future<String> sendMessageComplete(
    String message, {
    String? sessionId,
    String? model,
    List<UploadedFile>? files,
  }) async {
    final buffer = StringBuffer();

    await for (final event in sendMessage(
      message,
      sessionId: sessionId,
      model: model,
      files: files,
    )) {
      if (event.type == ChatStreamEventType.content) {
        buffer.write(event.content);
      } else if (event.type == ChatStreamEventType.error) {
        throw Exception(event.content);
      }
    }

    return buffer.toString();
  }
}

/// Types of events in the chat stream
enum ChatStreamEventType {
  content,
  status,
  toolStart,
  toolEnd,
  canvas,
  question,
  completion,
  error,
}

/// Event from the chat stream
class ChatStreamEvent {
  final ChatStreamEventType type;
  final String? content;
  final String? toolName;
  final String? canvasType;
  final dynamic data;

  const ChatStreamEvent._({
    required this.type,
    this.content,
    this.toolName,
    this.canvasType,
    this.data,
  });

  factory ChatStreamEvent.content(String content) => ChatStreamEvent._(
        type: ChatStreamEventType.content,
        content: content,
      );

  factory ChatStreamEvent.status(String message) => ChatStreamEvent._(
        type: ChatStreamEventType.status,
        content: message,
      );

  factory ChatStreamEvent.toolStart(String toolName, String? message) =>
      ChatStreamEvent._(
        type: ChatStreamEventType.toolStart,
        toolName: toolName,
        content: message,
      );

  factory ChatStreamEvent.toolEnd(String toolName, String? message) =>
      ChatStreamEvent._(
        type: ChatStreamEventType.toolEnd,
        toolName: toolName,
        content: message,
      );

  factory ChatStreamEvent.canvas(String canvasType, dynamic data) =>
      ChatStreamEvent._(
        type: ChatStreamEventType.canvas,
        canvasType: canvasType,
        data: data,
      );

  factory ChatStreamEvent.error(String message) => ChatStreamEvent._(
        type: ChatStreamEventType.error,
        content: message,
      );

  factory ChatStreamEvent.question(Map<String, dynamic> questionData) =>
      ChatStreamEvent._(
        type: ChatStreamEventType.question,
        data: questionData,
      );

  factory ChatStreamEvent.completion(Map<String, dynamic> completionData) =>
      ChatStreamEvent._(
        type: ChatStreamEventType.completion,
        data: completionData,
      );
}
