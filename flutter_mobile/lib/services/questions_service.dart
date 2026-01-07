import 'package:amos_mobile/models/agent_question.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Response from the pending questions endpoint
class QuestionsResponse {
  final List<AgentQuestion> questions;
  final List<AgentCompletion> completions;

  QuestionsResponse({
    required this.questions,
    required this.completions,
  });
}

/// Service for managing agent questions queue
class QuestionsService {
  final ApiClient _api = ApiClient();
  int? _lastSeenCompletionId;

  /// Fetch pending questions and recent completions for the current session
  Future<QuestionsResponse> fetchPendingQuestionsAndCompletions(String sessionId) async {
    try {
      final queryParams = <String, dynamic>{'session_id': sessionId};
      if (_lastSeenCompletionId != null) {
        queryParams['last_completion_id'] = _lastSeenCompletionId;
      }

      final response = await _api.get(
        '/amos/questions/pending',
        queryParameters: queryParams,
      );

      final questions = <AgentQuestion>[];
      final completions = <AgentCompletion>[];

      if (response['success'] == true) {
        if (response['questions'] != null) {
          questions.addAll(
            (response['questions'] as List)
                .map((q) => AgentQuestion.fromJson(q as Map<String, dynamic>))
                .toList(),
          );
        }

        if (response['completions'] != null) {
          completions.addAll(
            (response['completions'] as List)
                .map((c) => AgentCompletion.fromJson(c as Map<String, dynamic>))
                .toList(),
          );

          // Track the last seen completion ID for incremental polling
          if (completions.isNotEmpty) {
            final maxId = completions.map((c) => c.id).reduce((a, b) => a > b ? a : b);
            _lastSeenCompletionId = maxId;
          }
        }

        AppLogger.info(
          'Fetched ${questions.length} questions, ${completions.length} completions',
        );
      }

      return QuestionsResponse(questions: questions, completions: completions);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch pending questions', error: e, stackTrace: stackTrace);
      return QuestionsResponse(questions: [], completions: []);
    }
  }

  /// Legacy method for backward compatibility
  Future<List<AgentQuestion>> fetchPendingQuestions(String sessionId) async {
    final response = await fetchPendingQuestionsAndCompletions(sessionId);
    return response.questions;
  }

  /// Submit an answer to a question
  Future<bool> submitAnswer(
    int questionId,
    String answer, {
    String? attachmentPath,
  }) async {
    try {
      final data = <String, dynamic>{
        'answer': answer,
      };

      // TODO: Handle file attachment upload if attachmentPath is provided

      final response = await _api.post(
        '/amos/questions/$questionId/answer',
        data: data,
      );

      if (response['success'] == true) {
        AppLogger.info('Answer submitted for question $questionId');
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to submit answer', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Skip a question
  Future<bool> skipQuestion(int questionId, {String? reason}) async {
    try {
      final response = await _api.post(
        '/amos/questions/$questionId/skip',
        data: {'reason': reason},
      );

      if (response['success'] == true) {
        AppLogger.info('Question $questionId skipped');
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to skip question', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Reset the last seen completion ID (e.g., when starting a new session)
  void resetCompletionTracking() {
    _lastSeenCompletionId = null;
  }
}
