import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/chat.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/models/uploaded_file.dart';
import 'package:amos_mobile/providers/app_providers.dart';

void main() {
  group('ChatMessagesNotifier', () {
    test('initial state is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final messages = container.read(chatMessagesProvider);
      expect(messages, isEmpty);
    });

    test('addMessage appends message to state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'Hello',
        timestamp: DateTime.now(),
      );

      container.read(chatMessagesProvider.notifier).addMessage(message);

      final messages = container.read(chatMessagesProvider);
      expect(messages.length, equals(1));
      expect(messages.first.id, equals('1'));
      expect(messages.first.content, equals('Hello'));
    });

    test('addMessage preserves existing messages', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message1 = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'First',
        timestamp: DateTime.now(),
      );
      final message2 = ChatMessage(
        id: '2',
        role: MessageRole.assistant,
        content: 'Second',
        timestamp: DateTime.now(),
      );

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addMessage(message1);
      notifier.addMessage(message2);

      final messages = container.read(chatMessagesProvider);
      expect(messages.length, equals(2));
      expect(messages[0].id, equals('1'));
      expect(messages[1].id, equals('2'));
    });

    test('updateMessage updates existing message by id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'Original',
        timestamp: DateTime.now(),
      );

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addMessage(message);

      final updated = message.copyWith(content: 'Updated');
      notifier.updateMessage(updated);

      final messages = container.read(chatMessagesProvider);
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('Updated'));
    });

    test('updateMessage does nothing when id not found', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'Original',
        timestamp: DateTime.now(),
      );

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addMessage(message);

      final nonExistent = ChatMessage(
        id: '999',
        role: MessageRole.user,
        content: 'Updated',
        timestamp: DateTime.now(),
      );
      notifier.updateMessage(nonExistent);

      final messages = container.read(chatMessagesProvider);
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('Original'));
    });

    test('updateLastMessage updates last message in list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message1 = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'First',
        timestamp: DateTime.now(),
      );
      final message2 = ChatMessage(
        id: '2',
        role: MessageRole.assistant,
        content: 'Second',
        timestamp: DateTime.now(),
      );

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addMessage(message1);
      notifier.addMessage(message2);

      final updated = message2.copyWith(content: 'Updated Second');
      notifier.updateLastMessage(updated);

      final messages = container.read(chatMessagesProvider);
      expect(messages.length, equals(2));
      expect(messages[0].content, equals('First'));
      expect(messages[1].content, equals('Updated Second'));
    });

    test('updateLastMessage does nothing when list is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'Test',
        timestamp: DateTime.now(),
      );

      container.read(chatMessagesProvider.notifier).updateLastMessage(message);

      final messages = container.read(chatMessagesProvider);
      expect(messages, isEmpty);
    });

    test('clear removes all messages', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final message = ChatMessage(
        id: '1',
        role: MessageRole.user,
        content: 'Test',
        timestamp: DateTime.now(),
      );

      final notifier = container.read(chatMessagesProvider.notifier);
      notifier.addMessage(message);
      notifier.clear();

      final messages = container.read(chatMessagesProvider);
      expect(messages, isEmpty);
    });
  });

  group('ChatLoadingNotifier', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loading = container.read(chatLoadingProvider);
      expect(loading, isFalse);
    });

    test('setLoading updates state to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatLoadingProvider.notifier).setLoading(true);

      final loading = container.read(chatLoadingProvider);
      expect(loading, isTrue);
    });

    test('setLoading updates state to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatLoadingProvider.notifier);
      notifier.setLoading(true);
      notifier.setLoading(false);

      final loading = container.read(chatLoadingProvider);
      expect(loading, isFalse);
    });
  });

  group('ChatSessionNotifier', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final session = container.read(chatSessionProvider);
      expect(session, isNull);
    });

    test('setSession updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatSessionProvider.notifier).setSession('session-123');

      final session = container.read(chatSessionProvider);
      expect(session, equals('session-123'));
    });

    test('clear resets state to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatSessionProvider.notifier);
      notifier.setSession('session-123');
      notifier.clear();

      final session = container.read(chatSessionProvider);
      expect(session, isNull);
    });
  });

  group('SelectedModelNotifier', () {
    test('initial state is default model id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final modelId = container.read(selectedModelProvider);
      expect(modelId, equals(ModelOption.defaultModel.id));
    });

    test('setModel updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedModelProvider.notifier).setModel('claude-opus-4-5');

      final modelId = container.read(selectedModelProvider);
      expect(modelId, equals('claude-opus-4-5'));
    });
  });

  group('ChatStatusNotifier', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final status = container.read(chatStatusProvider);
      expect(status, isNull);
    });

    test('setStatus updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatStatusProvider.notifier).setStatus('Thinking...');

      final status = container.read(chatStatusProvider);
      expect(status, equals('Thinking...'));
    });

    test('setStatus to null clears status', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStatusProvider.notifier);
      notifier.setStatus('Processing...');
      notifier.setStatus(null);

      final status = container.read(chatStatusProvider);
      expect(status, isNull);
    });

    test('clear resets state to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(chatStatusProvider.notifier);
      notifier.setStatus('Processing...');
      notifier.clear();

      final status = container.read(chatStatusProvider);
      expect(status, isNull);
    });
  });

  group('AttachedFilesNotifier', () {
    test('initial state is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final files = container.read(attachedFilesProvider);
      expect(files, isEmpty);
    });

    test('addFile appends file to state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const file = UploadedFile(
        assetId: 'asset-1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      container.read(attachedFilesProvider.notifier).addFile(file);

      final files = container.read(attachedFilesProvider);
      expect(files.length, equals(1));
      expect(files.first.assetId, equals('asset-1'));
    });

    test('addFiles appends multiple files to state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const file1 = UploadedFile(
        assetId: 'asset-1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );
      const file2 = UploadedFile(
        assetId: 'asset-2',
        filename: 'image.png',
        contentType: 'image/png',
      );

      container.read(attachedFilesProvider.notifier).addFiles([file1, file2]);

      final files = container.read(attachedFilesProvider);
      expect(files.length, equals(2));
      expect(files[0].assetId, equals('asset-1'));
      expect(files[1].assetId, equals('asset-2'));
    });

    test('removeFile removes file by assetId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const file1 = UploadedFile(
        assetId: 'asset-1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );
      const file2 = UploadedFile(
        assetId: 'asset-2',
        filename: 'image.png',
        contentType: 'image/png',
      );

      final notifier = container.read(attachedFilesProvider.notifier);
      notifier.addFiles([file1, file2]);
      notifier.removeFile('asset-1');

      final files = container.read(attachedFilesProvider);
      expect(files.length, equals(1));
      expect(files.first.assetId, equals('asset-2'));
    });

    test('removeFile does nothing when assetId not found', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const file = UploadedFile(
        assetId: 'asset-1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      final notifier = container.read(attachedFilesProvider.notifier);
      notifier.addFile(file);
      notifier.removeFile('non-existent');

      final files = container.read(attachedFilesProvider);
      expect(files.length, equals(1));
    });

    test('clear removes all files', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const file = UploadedFile(
        assetId: 'asset-1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      final notifier = container.read(attachedFilesProvider.notifier);
      notifier.addFile(file);
      notifier.clear();

      final files = container.read(attachedFilesProvider);
      expect(files, isEmpty);
    });
  });

  group('AgentsNotifier', () {
    test('initial state is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final agents = container.read(agentsProvider);
      expect(agents, isEmpty);
    });
  });

  group('AgentsLoadingNotifier', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loading = container.read(agentsLoadingProvider);
      expect(loading, isFalse);
    });

    test('setLoading updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(agentsLoadingProvider.notifier).setLoading(true);

      final loading = container.read(agentsLoadingProvider);
      expect(loading, isTrue);
    });
  });

  group('CampaignsNotifier', () {
    test('initial state is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final campaigns = container.read(campaignsProvider);
      expect(campaigns, isEmpty);
    });
  });

  group('CampaignsLoadingNotifier', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loading = container.read(campaignsLoadingProvider);
      expect(loading, isFalse);
    });

    test('setLoading updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(campaignsLoadingProvider.notifier).setLoading(true);

      final loading = container.read(campaignsLoadingProvider);
      expect(loading, isTrue);
    });
  });

  group('ContactsNotifier', () {
    test('initial state is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final contacts = container.read(contactsProvider);
      expect(contacts, isEmpty);
    });
  });

  group('ContactsLoadingNotifier', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loading = container.read(contactsLoadingProvider);
      expect(loading, isFalse);
    });

    test('setLoading updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(contactsLoadingProvider.notifier).setLoading(true);

      final loading = container.read(contactsLoadingProvider);
      expect(loading, isTrue);
    });
  });

  group('LandingPagesNotifier', () {
    test('initial state is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final pages = container.read(landingPagesProvider);
      expect(pages, isEmpty);
    });
  });

  group('LandingPagesLoadingNotifier', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loading = container.read(landingPagesLoadingProvider);
      expect(loading, isFalse);
    });

    test('setLoading updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(landingPagesLoadingProvider.notifier).setLoading(true);

      final loading = container.read(landingPagesLoadingProvider);
      expect(loading, isTrue);
    });
  });
}
