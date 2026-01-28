import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/services/voice_service.dart';
import 'package:amos_mobile/models/voice_credentials.dart';

/// Voice input button with animated states
class VoiceInputButton extends ConsumerStatefulWidget {
  final void Function(String transcript) onTranscript;
  final VoidCallback? onError;

  const VoiceInputButton({
    super.key,
    required this.onTranscript,
    this.onError,
  });

  @override
  ConsumerState<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends ConsumerState<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription<TranscriptResult>? _transcriptSubscription;
  StreamSubscription<VoiceState>? _stateSubscription;

  VoiceState _state = VoiceState.idle;
  String _transcriptBuffer = '';
  Timer? _bufferTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to voice state changes
    _stateSubscription = _voiceService.stateStream.listen((state) {
      if (mounted) {
        setState(() => _state = state);

        if (state == VoiceState.listening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });

    // Listen to transcripts
    _transcriptSubscription = _voiceService.transcriptStream.listen((result) {
      if (mounted) {
        if (result.isFinal) {
          _addToBuffer(result.text);
        }
      }
    });
  }

  void _addToBuffer(String text) {
    _transcriptBuffer += (_transcriptBuffer.isEmpty ? '' : ' ') + text;

    // Wait for silence before sending
    _bufferTimer?.cancel();
    _bufferTimer = Timer(const Duration(milliseconds: 800), () {
      if (_transcriptBuffer.isNotEmpty) {
        widget.onTranscript(_transcriptBuffer);
        _transcriptBuffer = '';
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transcriptSubscription?.cancel();
    _stateSubscription?.cancel();
    _bufferTimer?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    try {
      if (_state == VoiceState.listening) {
        await _voiceService.stopListening();
        // Send any remaining buffer
        if (_transcriptBuffer.isNotEmpty) {
          widget.onTranscript(_transcriptBuffer);
          _transcriptBuffer = '';
        }
      } else {
        await _voiceService.startListening();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        widget.onError?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isListening = _state == VoiceState.listening;
    final isInitializing = _state == VoiceState.initializing;
    final hasError = _state == VoiceState.error;

    // Compact voice button only
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isListening ? _pulseAnimation.value : 1.0,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: context.primaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: IconButton(
              onPressed: isInitializing ? null : _toggleVoice,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: isInitializing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.primaryColor,
                      ),
                    )
                  : Icon(
                      isListening
                          ? LucideIcons.micOff
                          : hasError
                              ? LucideIcons.micOff
                              : LucideIcons.mic,
                      size: 20,
                      color: isListening
                          ? Colors.red
                          : hasError
                              ? Colors.red.withOpacity(0.5)
                              : context.textSecondary,
                    ),
              tooltip: isListening ? 'Stop listening' : 'Start voice input',
            ),
          ),
        );
      },
    );
  }
}
