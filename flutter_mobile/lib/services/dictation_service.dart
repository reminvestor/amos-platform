import 'dart:async';
import 'package:flutter/material.dart';
import 'package:amos_mobile/models/voice_credentials.dart';
import 'package:amos_mobile/services/voice_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Dictation state for text field integration
enum DictationState {
  idle,
  initializing,
  listening,
  error,
}

/// Service for dictation (speech-to-text in text fields)
/// Wraps VoiceService with dictation-specific logic for text input
class DictationService {
  final VoiceService _voiceService;
  final TextEditingController textController;

  // Stream controllers for dictation-specific events
  final _stateController = StreamController<DictationState>.broadcast();
  final _interimTextController = StreamController<String>.broadcast();

  DictationState _state = DictationState.idle;
  StreamSubscription<TranscriptResult>? _transcriptSubscription;
  StreamSubscription<VoiceState>? _voiceStateSubscription;

  // Track text for proper appending
  String _baseText = '';
  String _currentInterim = '';
  int _cursorPosition = 0;

  DictationService({
    required this.textController,
    VoiceService? voiceService,
  }) : _voiceService = voiceService ?? VoiceService() {
    _setupListeners();
  }

  // Public getters
  DictationState get state => _state;
  Stream<DictationState> get stateStream => _stateController.stream;
  Stream<String> get interimTextStream => _interimTextController.stream;
  bool get isListening => _state == DictationState.listening;

  void _setupListeners() {
    // Listen to voice state changes
    _voiceStateSubscription = _voiceService.stateStream.listen((voiceState) {
      switch (voiceState) {
        case VoiceState.idle:
          _setState(DictationState.idle);
          break;
        case VoiceState.initializing:
          _setState(DictationState.initializing);
          break;
        case VoiceState.listening:
          _setState(DictationState.listening);
          break;
        case VoiceState.processing:
          // Keep listening state during processing
          break;
        case VoiceState.error:
          _setState(DictationState.error);
          break;
      }
    });

    // Listen to transcripts
    _transcriptSubscription = _voiceService.transcriptStream.listen((result) {
      _handleTranscript(result);
    });
  }

  void _handleTranscript(TranscriptResult result) {
    if (result.text.isEmpty) return;

    if (result.isFinal) {
      // Final transcript - commit to text field
      _commitFinalText(result.text);
    } else {
      // Interim transcript - show preview
      _showInterimText(result.text);
    }
  }

  void _showInterimText(String text) {
    _currentInterim = text;
    _interimTextController.add(text);

    // Update text field with interim (will be replaced by final)
    _updateTextField(_baseText, text);
  }

  void _commitFinalText(String text) {
    // Clear interim and commit final text
    _currentInterim = '';
    _interimTextController.add('');

    // Add space before new text if needed
    String finalText = text;
    if (_baseText.isNotEmpty && !_baseText.endsWith(' ') && !_baseText.endsWith('\n')) {
      finalText = ' $text';
    }

    // Update base text
    _baseText = _baseText + finalText;
    _updateTextField(_baseText, '');

    AppLogger.info('Dictation committed: "$text"');
  }

  void _updateTextField(String baseText, String interimText) {
    final fullText = baseText + interimText;
    textController.text = fullText;

    // Move cursor to end
    textController.selection = TextSelection.fromPosition(
      TextPosition(offset: fullText.length),
    );
  }

  /// Start dictation
  Future<void> start() async {
    if (_state == DictationState.listening) return;

    // Save current text as base
    _baseText = textController.text;
    _cursorPosition = textController.selection.baseOffset;
    if (_cursorPosition < 0) _cursorPosition = _baseText.length;

    // Truncate base text to cursor position for insertion
    if (_cursorPosition < _baseText.length) {
      _baseText = _baseText.substring(0, _cursorPosition);
    }

    try {
      await _voiceService.startListening();
    } catch (e) {
      AppLogger.error('Failed to start dictation', error: e);
      _setState(DictationState.error);
      rethrow;
    }
  }

  /// Stop dictation
  Future<void> stop() async {
    if (_state != DictationState.listening) return;

    // Commit any remaining interim text
    if (_currentInterim.isNotEmpty) {
      _commitFinalText(_currentInterim);
    }

    await _voiceService.stopListening();
  }

  /// Toggle dictation on/off
  Future<void> toggle() async {
    if (isListening) {
      await stop();
    } else {
      await start();
    }
  }

  void _setState(DictationState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Clear the interim text display
  void clearInterim() {
    _currentInterim = '';
    _interimTextController.add('');
    _updateTextField(_baseText, '');
  }

  /// Dispose resources
  void dispose() {
    stop();
    _transcriptSubscription?.cancel();
    _voiceStateSubscription?.cancel();
    _stateController.close();
    _interimTextController.close();
    _voiceService.dispose();
  }
}
