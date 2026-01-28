import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/models/agent.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/models/uploaded_file.dart';

// ============ Chat Providers ============
class ChatMessagesNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => [];

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void updateMessage(ChatMessage message) {
    final index = state.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      final newState = [...state];
      newState[index] = message;
      state = newState;
    }
  }

  void updateLastMessage(ChatMessage message) {
    if (state.isEmpty) return;
    state = [...state.sublist(0, state.length - 1), message];
  }

  void clear() => state = [];
}

class ChatLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

// Chat session ID
class ChatSessionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setSession(String sessionId) => state = sessionId;
  void clear() => state = null;
}

// Selected AI model
class SelectedModelNotifier extends Notifier<String> {
  @override
  String build() => ModelOption.defaultModel.id;

  void setModel(String modelId) => state = modelId;
}

// Status message (transient)
class ChatStatusNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setStatus(String? status) => state = status;
  void clear() => state = null;
}

// Attached files for next message
class AttachedFilesNotifier extends Notifier<List<UploadedFile>> {
  @override
  List<UploadedFile> build() => [];

  void addFile(UploadedFile file) {
    state = [...state, file];
  }

  void addFiles(List<UploadedFile> files) {
    state = [...state, ...files];
  }

  void removeFile(String assetId) {
    state = state.where((f) => f.assetId != assetId).toList();
  }

  void clear() => state = [];
}

final chatMessagesProvider =
    NotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
        ChatMessagesNotifier.new);
final chatLoadingProvider =
    NotifierProvider<ChatLoadingNotifier, bool>(ChatLoadingNotifier.new);
final chatSessionProvider =
    NotifierProvider<ChatSessionNotifier, String?>(ChatSessionNotifier.new);
final selectedModelProvider =
    NotifierProvider<SelectedModelNotifier, String>(SelectedModelNotifier.new);
final chatStatusProvider =
    NotifierProvider<ChatStatusNotifier, String?>(ChatStatusNotifier.new);
final attachedFilesProvider =
    NotifierProvider<AttachedFilesNotifier, List<UploadedFile>>(
        AttachedFilesNotifier.new);

// ============ Agent Providers ============
class AgentsNotifier extends Notifier<List<Agent>> {
  @override
  List<Agent> build() => [];

  void setAgents(List<Agent> agents) => state = agents;
}

class AgentsLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) => state = loading;
}

final agentsProvider =
    NotifierProvider<AgentsNotifier, List<Agent>>(AgentsNotifier.new);
final agentsLoadingProvider =
    NotifierProvider<AgentsLoadingNotifier, bool>(AgentsLoadingNotifier.new);

// ============ Canvas Providers ============

/// Manages the currently active canvas
class CurrentCanvasNotifier extends Notifier<Canvas?> {
  @override
  Canvas? build() => null;

  /// Show a canvas from an SSE event
  void showCanvas(String canvasType, dynamic data) {
    state = Canvas.fromEvent(canvasType, data);
  }

  /// Update the current canvas data
  void updateCanvasData(Map<String, dynamic> newData) {
    if (state != null) {
      state = Canvas(
        type: state!.type,
        title: state!.title,
        data: {...state!.data, ...newData},
        loadedAt: state!.loadedAt,
      );
    }
  }

  /// Close the current canvas
  void closeCanvas() => state = null;
}

/// Tracks canvas history for back navigation
class CanvasHistoryNotifier extends Notifier<List<Canvas>> {
  @override
  List<Canvas> build() => [];

  void push(Canvas canvas) {
    state = [...state, canvas];
  }

  Canvas? pop() {
    if (state.isEmpty) return null;
    final last = state.last;
    state = state.sublist(0, state.length - 1);
    return last;
  }

  void clear() => state = [];

  bool get canGoBack => state.isNotEmpty;
}

/// Whether a canvas is currently visible
class CanvasVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
  void toggle() => state = !state;
}

final currentCanvasProvider =
    NotifierProvider<CurrentCanvasNotifier, Canvas?>(CurrentCanvasNotifier.new);
final canvasHistoryProvider =
    NotifierProvider<CanvasHistoryNotifier, List<Canvas>>(
        CanvasHistoryNotifier.new);
final canvasVisibleProvider =
    NotifierProvider<CanvasVisibleNotifier, bool>(CanvasVisibleNotifier.new);
