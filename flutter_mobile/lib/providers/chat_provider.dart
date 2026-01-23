import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/models/uploaded_file.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/services/chat_service.dart';

/// State for chat management
class ChatState {
  final List<ChatMessage> messages;
  final String? sessionId;
  final String selectedModel;
  final List<UploadedFile> attachedFiles;
  final bool isLoading;
  final bool isStreaming;
  final String? statusMessage;
  final String? error;
  final String? activeTool;

  const ChatState({
    this.messages = const [],
    this.sessionId,
    this.selectedModel = '',
    this.attachedFiles = const [],
    this.isLoading = false,
    this.isStreaming = false,
    this.statusMessage,
    this.error,
    this.activeTool,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? sessionId,
    String? selectedModel,
    List<UploadedFile>? attachedFiles,
    bool? isLoading,
    bool? isStreaming,
    String? statusMessage,
    String? error,
    String? activeTool,
    bool clearSessionId = false,
    bool clearStatusMessage = false,
    bool clearError = false,
    bool clearActiveTool = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      selectedModel: selectedModel ?? this.selectedModel,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      statusMessage: clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
      error: clearError ? null : (error ?? this.error),
      activeTool: clearActiveTool ? null : (activeTool ?? this.activeTool),
    );
  }

  /// Check if there are any messages
  bool get isEmpty => messages.isEmpty;

  /// Get message count
  int get messageCount => messages.length;

  /// Get the last message
  ChatMessage? get lastMessage => messages.isNotEmpty ? messages.last : null;

  /// Get the last user message
  ChatMessage? get lastUserMessage {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        return messages[i];
      }
    }
    return null;
  }

  /// Get the last assistant message
  ChatMessage? get lastAssistantMessage {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.assistant) {
        return messages[i];
      }
    }
    return null;
  }

  /// Check if chat is busy (loading or streaming)
  bool get isBusy => isLoading || isStreaming;

  /// Check if there are attached files
  bool get hasAttachments => attachedFiles.isNotEmpty;

  /// Get attachment count
  int get attachmentCount => attachedFiles.length;

  /// Check if a session is active
  bool get hasSession => sessionId != null && sessionId!.isNotEmpty;
}

/// Notifier for chat state management
class ChatNotifier extends Notifier<ChatState> {
  late final ChatService _chatService;

  @override
  ChatState build() {
    _chatService = ref.read(chatServiceProvider);
    return ChatState(selectedModel: ModelOption.defaultModel.id);
  }

  /// Create a new chat session
  Future<void> createNewSession() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final sessionId = await _chatService.createNewSession();
      state = state.copyWith(
        sessionId: sessionId,
        messages: [],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Add a message to the chat
  void addMessage(ChatMessage message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Update an existing message by ID
  void updateMessage(ChatMessage message) {
    final index = state.messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      final newMessages = [...state.messages];
      newMessages[index] = message;
      state = state.copyWith(messages: newMessages);
    }
  }

  /// Update the last message in the list
  void updateLastMessage(ChatMessage message) {
    if (state.messages.isEmpty) return;
    state = state.copyWith(
      messages: [...state.messages.sublist(0, state.messages.length - 1), message],
    );
  }

  /// Append content to the last message (for streaming)
  void appendToLastMessage(String content) {
    if (state.messages.isEmpty) return;
    final lastMessage = state.messages.last;
    final updated = lastMessage.copyWith(content: lastMessage.content + content);
    updateLastMessage(updated);
  }

  /// Set session ID
  void setSessionId(String sessionId) {
    state = state.copyWith(sessionId: sessionId);
  }

  /// Clear session
  void clearSession() {
    state = state.copyWith(clearSessionId: true, messages: []);
  }

  /// Set selected AI model
  void setSelectedModel(String modelId) {
    state = state.copyWith(selectedModel: modelId);
  }

  /// Add a file attachment
  void addAttachment(UploadedFile file) {
    state = state.copyWith(attachedFiles: [...state.attachedFiles, file]);
  }

  /// Add multiple file attachments
  void addAttachments(List<UploadedFile> files) {
    state = state.copyWith(attachedFiles: [...state.attachedFiles, ...files]);
  }

  /// Remove a file attachment by asset ID
  void removeAttachment(String assetId) {
    state = state.copyWith(
      attachedFiles: state.attachedFiles.where((f) => f.assetId != assetId).toList(),
    );
  }

  /// Clear all attachments
  void clearAttachments() {
    state = state.copyWith(attachedFiles: []);
  }

  /// Set loading state
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  /// Set streaming state
  void setStreaming(bool streaming) {
    state = state.copyWith(isStreaming: streaming);
  }

  /// Set status message
  void setStatusMessage(String? message) {
    if (message == null) {
      state = state.copyWith(clearStatusMessage: true);
    } else {
      state = state.copyWith(statusMessage: message);
    }
  }

  /// Clear status message
  void clearStatusMessage() {
    state = state.copyWith(clearStatusMessage: true);
  }

  /// Set error message
  void setError(String error) {
    state = state.copyWith(error: error);
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set active tool (for tool execution display)
  void setActiveTool(String? toolName) {
    if (toolName == null) {
      state = state.copyWith(clearActiveTool: true);
    } else {
      state = state.copyWith(activeTool: toolName);
    }
  }

  /// Clear active tool
  void clearActiveTool() {
    state = state.copyWith(clearActiveTool: true);
  }

  /// Clear all messages
  void clearMessages() {
    state = state.copyWith(messages: []);
  }

  /// Clear entire chat state
  void clear() {
    state = ChatState(selectedModel: ModelOption.defaultModel.id);
  }
}

// Service provider
final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

// State provider
final chatStateProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

// Convenience providers
final chatMessagesProvider = Provider<List<ChatMessage>>((ref) {
  return ref.watch(chatStateProvider).messages;
});

final chatSessionIdProvider = Provider<String?>((ref) {
  return ref.watch(chatStateProvider).sessionId;
});

final chatSelectedModelProvider = Provider<String>((ref) {
  return ref.watch(chatStateProvider).selectedModel;
});

final chatAttachedFilesProvider = Provider<List<UploadedFile>>((ref) {
  return ref.watch(chatStateProvider).attachedFiles;
});

final chatIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(chatStateProvider).isLoading;
});

final chatIsStreamingProvider = Provider<bool>((ref) {
  return ref.watch(chatStateProvider).isStreaming;
});

final chatIsBusyProvider = Provider<bool>((ref) {
  return ref.watch(chatStateProvider).isBusy;
});

final chatStatusMessageProvider = Provider<String?>((ref) {
  return ref.watch(chatStateProvider).statusMessage;
});

final chatErrorProvider = Provider<String?>((ref) {
  return ref.watch(chatStateProvider).error;
});

final chatActiveToolProvider = Provider<String?>((ref) {
  return ref.watch(chatStateProvider).activeTool;
});

final chatLastMessageProvider = Provider<ChatMessage?>((ref) {
  return ref.watch(chatStateProvider).lastMessage;
});

final chatHasSessionProvider = Provider<bool>((ref) {
  return ref.watch(chatStateProvider).hasSession;
});

final chatHasAttachmentsProvider = Provider<bool>((ref) {
  return ref.watch(chatStateProvider).hasAttachments;
});
