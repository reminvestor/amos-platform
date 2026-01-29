import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/services/dictation_service.dart';

/// A TextField with integrated dictation (speech-to-text) capability
/// Shows a mic button in the suffix that enables voice input
class DictationTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final int maxLines;
  final int? minLines;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onChanged;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final InputDecoration? decoration;
  final bool showSendButton;
  final VoidCallback? onSend;

  const DictationTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.maxLines = 5,
    this.minLines = 1,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.textInputAction,
    this.decoration,
    this.showSendButton = false,
    this.onSend,
  });

  @override
  State<DictationTextField> createState() => _DictationTextFieldState();
}

class _DictationTextFieldState extends State<DictationTextField>
    with SingleTickerProviderStateMixin {
  late DictationService _dictationService;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription<DictationState>? _stateSubscription;
  StreamSubscription<String>? _interimSubscription;

  DictationState _dictationState = DictationState.idle;
  String _interimText = '';

  @override
  void initState() {
    super.initState();

    _dictationService = DictationService(textController: widget.controller);

    // Setup pulse animation for listening state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to dictation state changes
    _stateSubscription = _dictationService.stateStream.listen((state) {
      if (mounted) {
        setState(() => _dictationState = state);

        if (state == DictationState.listening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });

    // Listen to interim text changes
    _interimSubscription = _dictationService.interimTextStream.listen((text) {
      if (mounted) {
        setState(() => _interimText = text);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stateSubscription?.cancel();
    _interimSubscription?.cancel();
    _dictationService.dispose();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    try {
      await _dictationService.toggle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dictation error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isListening = _dictationState == DictationState.listening;
    final isInitializing = _dictationState == DictationState.initializing;
    final hasError = _dictationState == DictationState.error;

    // Build the mic button
    final micButton = AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isListening ? _pulseAnimation.value : 1.0,
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: IconButton(
              onPressed:
                  (widget.enabled && !isInitializing) ? _toggleDictation : null,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: isInitializing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.primaryColor,
                      ),
                    )
                  : Icon(
                      isListening ? LucideIcons.micOff : LucideIcons.mic,
                      size: 20,
                      color: isListening
                          ? Colors.red
                          : hasError
                              ? Colors.red.withValues(alpha: 0.5)
                              : context.textSecondary,
                    ),
              tooltip: isListening ? 'Stop dictation' : 'Start dictation',
            ),
          ),
        );
      },
    );

    // Build send button if requested
    Widget? sendButton;
    if (widget.showSendButton && widget.onSend != null) {
      sendButton = IconButton(
        onPressed: widget.enabled ? widget.onSend : null,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        icon: Icon(
          LucideIcons.send,
          size: 20,
          color: context.primaryColor,
        ),
        tooltip: 'Send',
      );
    }

    // Combine suffix icons
    final suffixWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        micButton,
        if (sendButton != null) sendButton,
      ],
    );

    // Build decoration
    final effectiveDecoration = (widget.decoration ?? const InputDecoration())
        .copyWith(
      hintText: widget.hintText,
      suffixIcon: suffixWidget,
      // Show listening indicator in border
      enabledBorder: isListening
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.red.withValues(alpha: 0.5),
                width: 2,
              ),
            )
          : null,
      focusedBorder: isListening
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 2,
              ),
            )
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show interim text indicator above field when listening
        if (isListening && _interimText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 12),
            child: Row(
              children: [
                Icon(
                  LucideIcons.mic,
                  size: 12,
                  color: Colors.red.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _interimText,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: context.textSecondary.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // The text field
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          textInputAction: widget.textInputAction,
          decoration: effectiveDecoration,
          onChanged: (_) => widget.onChanged?.call(),
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );
  }
}
