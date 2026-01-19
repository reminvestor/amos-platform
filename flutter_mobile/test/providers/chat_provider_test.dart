import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/models/uploaded_file.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/providers/chat_provider.dart';

void main() {
  // Test message helper
  ChatMessage createTestMessage({
    String id = '1',
    MessageRole role = MessageRole.user,
    String content = 'Test message',
    bool isStreaming = false,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      timestamp: timestamp ?? DateTime.now(),
      isStreaming: isStreaming,
    );
  }

  // Test file helper
  UploadedFile createTestFile({
    String assetId = 'asset-1',
    String filename = 'test.pdf',
    String contentType = 'application/pdf',
  }) {
    return UploadedFile(
      assetId: assetId,
      filename: filename,
      contentType: contentType,
    );
  }

  group('ChatState', () {
    test('default state has correct initial values', () {
      const state = ChatState();

      expect(state.messages, isEmpty);
      expect(state.sessionId, isNull);
      expect(state.selectedModel, equals(''));
      expect(state.attachedFiles, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.isStreaming, isFalse);
      expect(state.statusMessage, isNull);
      expect(state.error, isNull);
      expect(state.activeTool, isNull);
    });

    test('isEmpty returns true when messages list is empty', () {
      const state = ChatState();

      expect(state.isEmpty, isTrue);
    });

    test('isEmpty returns false when messages exist', () {
      final message = createTestMessage();
      final state = ChatState(messages: [message]);

      expect(state.isEmpty, isFalse);
    });

    test('messageCount returns correct count', () {
      final messages = [
        createTestMessage(id: '1'),
        createTestMessage(id: '2'),
        createTestMessage(id: '3'),
      ];
      final state = ChatState(messages: messages);

      expect(state.messageCount, equals(3));
    });

    test('lastMessage returns the last message', () {
      final messages = [
        createTestMessage(id: '1', content: 'First'),
        createTestMessage(id: '2', content: 'Second'),
        createTestMessage(id: '3', content: 'Third'),
      ];
      final state = ChatState(messages: messages);

      expect(state.lastMessage?.content, equals('Third'));
    });

    test('lastMessage returns null when no messages', () {
      const state = ChatState();

      expect(state.lastMessage, isNull);
    });

    test('lastUserMessage returns the last user message', () {
      final messages = [
        createTestMessage(id: '1', role: MessageRole.user, content: 'User 1'),
        createTestMessage(id: '2', role: MessageRole.assistant, content: 'Assistant 1'),
        createTestMessage(id: '3', role: MessageRole.user, content: 'User 2'),
        createTestMessage(id: '4', role: MessageRole.assistant, content: 'Assistant 2'),
      ];
      final state = ChatState(messages: messages);

      expect(state.lastUserMessage?.content, equals('User 2'));
    });

    test('lastUserMessage returns null when no user messages', () {
      final messages = [
        createTestMessage(id: '1', role: MessageRole.assistant, content: 'Assistant'),
      ];
      final state = ChatState(messages: messages);

      expect(state.lastUserMessage, isNull);
    });

    test('lastAssistantMessage returns the last assistant message', () {
      final messages = [
        createTestMessage(id: '1', role: MessageRole.user, content: 'User 1'),
        createTestMessage(id: '2', role: MessageRole.assistant, content: 'Assistant 1'),
        createTestMessage(id: '3', role: MessageRole.user, content: 'User 2'),
        createTestMessage(id: '4', role: MessageRole.assistant, content: 'Assistant 2'),
      ];
      final state = ChatState(messages: messages);

      expect(state.lastAssistantMessage?.content, equals('Assistant 2'));
    });

    test('lastAssistantMessage returns null when no assistant messages', () {
      final messages = [
        createTestMessage(id: '1', role: MessageRole.user, content: 'User'),
      ];
      final state = ChatState(messages: messages);

      expect(state.lastAssistantMessage, isNull);
    });

    test('isBusy returns true when loading', () {
      const state = ChatState(isLoading: true);

      expect(state.isBusy, isTrue);
    });

    test('isBusy returns true when streaming', () {
      const state = ChatState(isStreaming: true);

      expect(state.isBusy, isTrue);
    });

    test('isBusy returns false when neither loading nor streaming', () {
      const state = ChatState();

      expect(state.isBusy, isFalse);
    });

    test('hasAttachments returns true when files exist', () {
      final file = createTestFile();
      final state = ChatState(attachedFiles: [file]);

      expect(state.hasAttachments, isTrue);
    });

    test('hasAttachments returns false when no files', () {
      const state = ChatState();

      expect(state.hasAttachments, isFalse);
    });

    test('attachmentCount returns correct count', () {
      final files = [
        createTestFile(assetId: 'asset-1'),
        createTestFile(assetId: 'asset-2'),
      ];
      final state = ChatState(attachedFiles: files);

      expect(state.attachmentCount, equals(2));
    });

    test('hasSession returns true when sessionId exists', () {
      const state = ChatState(sessionId: 'session-123');

      expect(state.hasSession, isTrue);
    });

    test('hasSession returns false when sessionId is null', () {
      const state = ChatState();

      expect(state.hasSession, isFalse);
    });

    test('hasSession returns false when sessionId is empty', () {
      const state = ChatState(sessionId: '');

      expect(state.hasSession, isFalse);
    });

    group('copyWith', () {
      test('updates messages', () {
        const initial = ChatState();
        final messages = [createTestMessage()];

        final modified = initial.copyWith(messages: messages);

        expect(modified.messages.length, equals(1));
        expect(initial.messages, isEmpty);
      });

      test('updates sessionId', () {
        const initial = ChatState();

        final modified = initial.copyWith(sessionId: 'session-123');

        expect(modified.sessionId, equals('session-123'));
        expect(initial.sessionId, isNull);
      });

      test('clears sessionId when clearSessionId is true', () {
        const initial = ChatState(sessionId: 'session-123');

        final modified = initial.copyWith(clearSessionId: true);

        expect(modified.sessionId, isNull);
      });

      test('updates selectedModel', () {
        const initial = ChatState();

        final modified = initial.copyWith(selectedModel: 'claude-opus-4-5');

        expect(modified.selectedModel, equals('claude-opus-4-5'));
      });

      test('updates attachedFiles', () {
        const initial = ChatState();
        final files = [createTestFile()];

        final modified = initial.copyWith(attachedFiles: files);

        expect(modified.attachedFiles.length, equals(1));
        expect(initial.attachedFiles, isEmpty);
      });

      test('updates isLoading', () {
        const initial = ChatState();

        final modified = initial.copyWith(isLoading: true);

        expect(modified.isLoading, isTrue);
        expect(initial.isLoading, isFalse);
      });

      test('updates isStreaming', () {
        const initial = ChatState();

        final modified = initial.copyWith(isStreaming: true);

        expect(modified.isStreaming, isTrue);
        expect(initial.isStreaming, isFalse);
      });

      test('updates statusMessage', () {
        const initial = ChatState();

        final modified = initial.copyWith(statusMessage: 'Thinking...');

        expect(modified.statusMessage, equals('Thinking...'));
        expect(initial.statusMessage, isNull);
      });

      test('clears statusMessage when clearStatusMessage is true', () {
        const initial = ChatState(statusMessage: 'Previous status');

        final modified = initial.copyWith(clearStatusMessage: true);

        expect(modified.statusMessage, isNull);
      });

      test('updates error', () {
        const initial = ChatState();

        final modified = initial.copyWith(error: 'Test error');

        expect(modified.error, equals('Test error'));
        expect(initial.error, isNull);
      });

      test('clears error when clearError is true', () {
        const initial = ChatState(error: 'Previous error');

        final modified = initial.copyWith(clearError: true);

        expect(modified.error, isNull);
      });

      test('updates activeTool', () {
        const initial = ChatState();

        final modified = initial.copyWith(activeTool: 'web_search');

        expect(modified.activeTool, equals('web_search'));
        expect(initial.activeTool, isNull);
      });

      test('clears activeTool when clearActiveTool is true', () {
        const initial = ChatState(activeTool: 'previous_tool');

        final modified = initial.copyWith(clearActiveTool: true);

        expect(modified.activeTool, isNull);
      });

      test('preserves unmodified values', () {
        final message = createTestMessage();
        final file = createTestFile();
        final initial = ChatState(
          messages: [message],
          sessionId: 'session-123',
          selectedModel: 'claude-sonnet-4-5',
          attachedFiles: [file],
          isLoading: true,
          statusMessage: 'Loading',
          activeTool: 'tool_name',
        );

        final modified = initial.copyWith(isStreaming: true);

        expect(modified.messages.length, equals(1));
        expect(modified.sessionId, equals('session-123'));
        expect(modified.selectedModel, equals('claude-sonnet-4-5'));
        expect(modified.attachedFiles.length, equals(1));
        expect(modified.isLoading, isTrue);
        expect(modified.isStreaming, isTrue);
        expect(modified.statusMessage, equals('Loading'));
        expect(modified.activeTool, equals('tool_name'));
      });
    });
  });

  group('ChatNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has default model selected', () {
      final state = container.read(chatStateProvider);

      expect(state.messages, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.selectedModel, equals(ModelOption.defaultModel.id));
    });

    test('addMessage appends message to list', () {
      final message = createTestMessage(id: '1', content: 'Hello');

      container.read(chatStateProvider.notifier).addMessage(message);

      final state = container.read(chatStateProvider);
      expect(state.messages.length, equals(1));
      expect(state.messages.first.content, equals('Hello'));
    });

    test('addMessage preserves existing messages', () {
      final message1 = createTestMessage(id: '1', content: 'First');
      final message2 = createTestMessage(id: '2', content: 'Second');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addMessage(message1);
      notifier.addMessage(message2);

      final state = container.read(chatStateProvider);
      expect(state.messages.length, equals(2));
      expect(state.messages[0].content, equals('First'));
      expect(state.messages[1].content, equals('Second'));
    });

    test('updateMessage updates existing message by id', () {
      final message = createTestMessage(id: '1', content: 'Original');
      final updated = createTestMessage(id: '1', content: 'Updated');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addMessage(message);
      notifier.updateMessage(updated);

      final state = container.read(chatStateProvider);
      expect(state.messages.first.content, equals('Updated'));
    });

    test('updateMessage does nothing when id not found', () {
      final message = createTestMessage(id: '1', content: 'Original');
      final nonExistent = createTestMessage(id: '999', content: 'Updated');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addMessage(message);
      notifier.updateMessage(nonExistent);

      final state = container.read(chatStateProvider);
      expect(state.messages.length, equals(1));
      expect(state.messages.first.content, equals('Original'));
    });

    test('updateLastMessage updates last message in list', () {
      final message1 = createTestMessage(id: '1', content: 'First');
      final message2 = createTestMessage(id: '2', content: 'Second');
      final updated = createTestMessage(id: '2', content: 'Updated Second');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addMessage(message1);
      notifier.addMessage(message2);
      notifier.updateLastMessage(updated);

      final state = container.read(chatStateProvider);
      expect(state.messages.length, equals(2));
      expect(state.messages[0].content, equals('First'));
      expect(state.messages[1].content, equals('Updated Second'));
    });

    test('updateLastMessage does nothing when list is empty', () {
      final message = createTestMessage(id: '1', content: 'Test');

      container.read(chatStateProvider.notifier).updateLastMessage(message);

      final state = container.read(chatStateProvider);
      expect(state.messages, isEmpty);
    });

    test('appendToLastMessage appends content to last message', () {
      final message = createTestMessage(id: '1', content: 'Hello');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addMessage(message);
      notifier.appendToLastMessage(' World');

      final state = container.read(chatStateProvider);
      expect(state.messages.first.content, equals('Hello World'));
    });

    test('appendToLastMessage does nothing when list is empty', () {
      container.read(chatStateProvider.notifier).appendToLastMessage('Test');

      final state = container.read(chatStateProvider);
      expect(state.messages, isEmpty);
    });

    test('setSessionId updates session id', () {
      container.read(chatStateProvider.notifier).setSessionId('session-456');

      final state = container.read(chatStateProvider);
      expect(state.sessionId, equals('session-456'));
    });

    test('clearSession clears session id and messages', () {
      final message = createTestMessage();

      final notifier = container.read(chatStateProvider.notifier);
      notifier.setSessionId('session-123');
      notifier.addMessage(message);
      notifier.clearSession();

      final state = container.read(chatStateProvider);
      expect(state.sessionId, isNull);
      expect(state.messages, isEmpty);
    });

    test('setSelectedModel updates selected model', () {
      container.read(chatStateProvider.notifier).setSelectedModel('claude-opus-4-5');

      final state = container.read(chatStateProvider);
      expect(state.selectedModel, equals('claude-opus-4-5'));
    });

    test('addAttachment appends file to list', () {
      final file = createTestFile(assetId: 'asset-1');

      container.read(chatStateProvider.notifier).addAttachment(file);

      final state = container.read(chatStateProvider);
      expect(state.attachedFiles.length, equals(1));
      expect(state.attachedFiles.first.assetId, equals('asset-1'));
    });

    test('addAttachments appends multiple files to list', () {
      final file1 = createTestFile(assetId: 'asset-1');
      final file2 = createTestFile(assetId: 'asset-2');

      container.read(chatStateProvider.notifier).addAttachments([file1, file2]);

      final state = container.read(chatStateProvider);
      expect(state.attachedFiles.length, equals(2));
    });

    test('removeAttachment removes file by assetId', () {
      final file1 = createTestFile(assetId: 'asset-1');
      final file2 = createTestFile(assetId: 'asset-2');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addAttachments([file1, file2]);
      notifier.removeAttachment('asset-1');

      final state = container.read(chatStateProvider);
      expect(state.attachedFiles.length, equals(1));
      expect(state.attachedFiles.first.assetId, equals('asset-2'));
    });

    test('removeAttachment does nothing when assetId not found', () {
      final file = createTestFile(assetId: 'asset-1');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addAttachment(file);
      notifier.removeAttachment('non-existent');

      final state = container.read(chatStateProvider);
      expect(state.attachedFiles.length, equals(1));
    });

    test('clearAttachments removes all files', () {
      final file1 = createTestFile(assetId: 'asset-1');
      final file2 = createTestFile(assetId: 'asset-2');

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addAttachments([file1, file2]);
      notifier.clearAttachments();

      final state = container.read(chatStateProvider);
      expect(state.attachedFiles, isEmpty);
    });

    test('setLoading updates loading state', () {
      container.read(chatStateProvider.notifier).setLoading(true);

      final state = container.read(chatStateProvider);
      expect(state.isLoading, isTrue);
    });

    test('setStreaming updates streaming state', () {
      container.read(chatStateProvider.notifier).setStreaming(true);

      final state = container.read(chatStateProvider);
      expect(state.isStreaming, isTrue);
    });

    test('setStatusMessage updates status message', () {
      container.read(chatStateProvider.notifier).setStatusMessage('Thinking...');

      final state = container.read(chatStateProvider);
      expect(state.statusMessage, equals('Thinking...'));
    });

    test('setStatusMessage with null clears status', () {
      final notifier = container.read(chatStateProvider.notifier);
      notifier.setStatusMessage('Loading');
      notifier.setStatusMessage(null);

      final state = container.read(chatStateProvider);
      expect(state.statusMessage, isNull);
    });

    test('clearStatusMessage clears the status message', () {
      final notifier = container.read(chatStateProvider.notifier);
      notifier.setStatusMessage('Loading');
      notifier.clearStatusMessage();

      final state = container.read(chatStateProvider);
      expect(state.statusMessage, isNull);
    });

    test('setError updates error state', () {
      container.read(chatStateProvider.notifier).setError('Test error');

      final state = container.read(chatStateProvider);
      expect(state.error, equals('Test error'));
    });

    test('clearError clears the error state', () {
      final notifier = container.read(chatStateProvider.notifier);
      notifier.setError('Test error');
      notifier.clearError();

      final state = container.read(chatStateProvider);
      expect(state.error, isNull);
    });

    test('setActiveTool updates active tool', () {
      container.read(chatStateProvider.notifier).setActiveTool('web_search');

      final state = container.read(chatStateProvider);
      expect(state.activeTool, equals('web_search'));
    });

    test('setActiveTool with null clears active tool', () {
      final notifier = container.read(chatStateProvider.notifier);
      notifier.setActiveTool('web_search');
      notifier.setActiveTool(null);

      final state = container.read(chatStateProvider);
      expect(state.activeTool, isNull);
    });

    test('clearActiveTool clears the active tool', () {
      final notifier = container.read(chatStateProvider.notifier);
      notifier.setActiveTool('web_search');
      notifier.clearActiveTool();

      final state = container.read(chatStateProvider);
      expect(state.activeTool, isNull);
    });

    test('clearMessages removes all messages', () {
      final message = createTestMessage();

      final notifier = container.read(chatStateProvider.notifier);
      notifier.addMessage(message);
      notifier.clearMessages();

      final state = container.read(chatStateProvider);
      expect(state.messages, isEmpty);
    });

    test('clear resets state to initial values', () {
      final message = createTestMessage();
      final file = createTestFile();

      final notifier = container.read(chatStateProvider.notifier);
      notifier.setSessionId('session-123');
      notifier.addMessage(message);
      notifier.addAttachment(file);
      notifier.setLoading(true);
      notifier.clear();

      final state = container.read(chatStateProvider);
      expect(state.messages, isEmpty);
      expect(state.sessionId, isNull);
      expect(state.attachedFiles, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.selectedModel, equals(ModelOption.defaultModel.id));
    });
  });

  group('Convenience Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('chatMessagesProvider reflects messages', () {
      expect(container.read(chatMessagesProvider), isEmpty);

      final message = createTestMessage();
      container.read(chatStateProvider.notifier).addMessage(message);

      expect(container.read(chatMessagesProvider).length, equals(1));
    });

    test('chatSessionIdProvider reflects session id', () {
      expect(container.read(chatSessionIdProvider), isNull);

      container.read(chatStateProvider.notifier).setSessionId('session-123');

      expect(container.read(chatSessionIdProvider), equals('session-123'));
    });

    test('chatSelectedModelProvider reflects selected model', () {
      expect(container.read(chatSelectedModelProvider), equals(ModelOption.defaultModel.id));

      container.read(chatStateProvider.notifier).setSelectedModel('claude-opus-4-5');

      expect(container.read(chatSelectedModelProvider), equals('claude-opus-4-5'));
    });

    test('chatAttachedFilesProvider reflects attached files', () {
      expect(container.read(chatAttachedFilesProvider), isEmpty);

      final file = createTestFile();
      container.read(chatStateProvider.notifier).addAttachment(file);

      expect(container.read(chatAttachedFilesProvider).length, equals(1));
    });

    test('chatIsLoadingProvider reflects loading state', () {
      expect(container.read(chatIsLoadingProvider), isFalse);

      container.read(chatStateProvider.notifier).setLoading(true);

      expect(container.read(chatIsLoadingProvider), isTrue);
    });

    test('chatIsStreamingProvider reflects streaming state', () {
      expect(container.read(chatIsStreamingProvider), isFalse);

      container.read(chatStateProvider.notifier).setStreaming(true);

      expect(container.read(chatIsStreamingProvider), isTrue);
    });

    test('chatIsBusyProvider reflects busy state', () {
      expect(container.read(chatIsBusyProvider), isFalse);

      container.read(chatStateProvider.notifier).setLoading(true);
      expect(container.read(chatIsBusyProvider), isTrue);

      container.read(chatStateProvider.notifier).setLoading(false);
      container.read(chatStateProvider.notifier).setStreaming(true);
      expect(container.read(chatIsBusyProvider), isTrue);
    });

    test('chatStatusMessageProvider reflects status message', () {
      expect(container.read(chatStatusMessageProvider), isNull);

      container.read(chatStateProvider.notifier).setStatusMessage('Thinking...');

      expect(container.read(chatStatusMessageProvider), equals('Thinking...'));
    });

    test('chatErrorProvider reflects error state', () {
      expect(container.read(chatErrorProvider), isNull);

      container.read(chatStateProvider.notifier).setError('Error');

      expect(container.read(chatErrorProvider), equals('Error'));
    });

    test('chatActiveToolProvider reflects active tool', () {
      expect(container.read(chatActiveToolProvider), isNull);

      container.read(chatStateProvider.notifier).setActiveTool('web_search');

      expect(container.read(chatActiveToolProvider), equals('web_search'));
    });

    test('chatLastMessageProvider reflects last message', () {
      expect(container.read(chatLastMessageProvider), isNull);

      final message = createTestMessage(content: 'Hello');
      container.read(chatStateProvider.notifier).addMessage(message);

      expect(container.read(chatLastMessageProvider)?.content, equals('Hello'));
    });

    test('chatHasSessionProvider reflects session status', () {
      expect(container.read(chatHasSessionProvider), isFalse);

      container.read(chatStateProvider.notifier).setSessionId('session-123');

      expect(container.read(chatHasSessionProvider), isTrue);
    });

    test('chatHasAttachmentsProvider reflects attachment status', () {
      expect(container.read(chatHasAttachmentsProvider), isFalse);

      final file = createTestFile();
      container.read(chatStateProvider.notifier).addAttachment(file);

      expect(container.read(chatHasAttachmentsProvider), isTrue);
    });
  });
}
