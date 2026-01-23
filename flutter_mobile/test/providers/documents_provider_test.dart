import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/document.dart';
import 'package:amos_mobile/providers/documents_provider.dart';

void main() {
  // Test document helper
  Document createTestDocument({
    String id = '1',
    String filename = 'test.pdf',
    String title = 'Test Document',
    String contentType = 'application/pdf',
    String processingStatus = 'completed',
    int processingProgress = 100,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Document(
      id: id,
      filename: filename,
      title: title,
      contentType: contentType,
      fileSize: '1.5 MB',
      fileSizeBytes: 1572864,
      processingStatus: processingStatus,
      processingProgress: processingProgress,
      chunksCount: 10,
      viewCount: 5,
      downloadCount: 2,
      collectionName: 'Default',
      collectionId: 'default-collection',
      icon: 'file',
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // Test collection helper
  DocumentCollection createTestCollection({
    String id = '1',
    String name = 'Test Collection',
    String status = 'active',
    int documentCount = 10,
    int chunkCount = 100,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DocumentCollection(
      id: id,
      name: name,
      status: status,
      documentCount: documentCount,
      chunkCount: chunkCount,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  group('DocumentsState', () {
    test('default state has correct initial values', () {
      const state = DocumentsState();

      expect(state.documents, isEmpty);
      expect(state.collections, isEmpty);
      expect(state.selectedDocument, isNull);
      expect(state.selectedCollection, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.isUploading, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, equals(1));
      expect(state.hasMore, isTrue);
      expect(state.searchQuery, isNull);
      expect(state.filterContentType, isNull);
      expect(state.filterStatus, isNull);
      expect(state.uploadProgress, equals(0.0));
    });

    test('isEmpty returns true when documents list is empty', () {
      const state = DocumentsState();

      expect(state.isEmpty, isTrue);
    });

    test('isEmpty returns false when documents exist', () {
      final document = createTestDocument();
      final state = DocumentsState(documents: [document]);

      expect(state.isEmpty, isFalse);
    });

    test('totalCount returns correct count', () {
      final documents = [
        createTestDocument(id: '1'),
        createTestDocument(id: '2'),
        createTestDocument(id: '3'),
      ];
      final state = DocumentsState(documents: documents);

      expect(state.totalCount, equals(3));
    });

    test('readyCount returns count of ready documents', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'completed'),
        createTestDocument(id: '2', processingStatus: 'processing'),
        createTestDocument(id: '3', processingStatus: 'ready'),
      ];
      final state = DocumentsState(documents: documents);

      expect(state.readyCount, equals(2));
    });

    test('processingCount returns count of processing documents', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'completed'),
        createTestDocument(id: '2', processingStatus: 'processing'),
        createTestDocument(id: '3', processingStatus: 'pending'),
      ];
      final state = DocumentsState(documents: documents);

      expect(state.processingCount, equals(2));
    });

    test('isBusy returns true when loading', () {
      const state = DocumentsState(isLoading: true);

      expect(state.isBusy, isTrue);
    });

    test('isBusy returns true when uploading', () {
      const state = DocumentsState(isUploading: true);

      expect(state.isBusy, isTrue);
    });

    test('isBusy returns false when neither loading nor uploading', () {
      const state = DocumentsState();

      expect(state.isBusy, isFalse);
    });

    group('copyWith', () {
      test('updates documents', () {
        const initial = DocumentsState();
        final documents = [createTestDocument()];

        final modified = initial.copyWith(documents: documents);

        expect(modified.documents.length, equals(1));
        expect(initial.documents, isEmpty);
      });

      test('updates collections', () {
        const initial = DocumentsState();
        final collections = [createTestCollection()];

        final modified = initial.copyWith(collections: collections);

        expect(modified.collections.length, equals(1));
        expect(initial.collections, isEmpty);
      });

      test('updates selectedDocument', () {
        const initial = DocumentsState();
        final document = createTestDocument();

        final modified = initial.copyWith(selectedDocument: document);

        expect(modified.selectedDocument, equals(document));
        expect(initial.selectedDocument, isNull);
      });

      test('clears selectedDocument when clearSelectedDocument is true', () {
        final document = createTestDocument();
        final initial = DocumentsState(selectedDocument: document);

        final modified = initial.copyWith(clearSelectedDocument: true);

        expect(modified.selectedDocument, isNull);
      });

      test('updates selectedCollection', () {
        const initial = DocumentsState();
        final collection = createTestCollection();

        final modified = initial.copyWith(selectedCollection: collection);

        expect(modified.selectedCollection, equals(collection));
        expect(initial.selectedCollection, isNull);
      });

      test('clears selectedCollection when clearSelectedCollection is true', () {
        final collection = createTestCollection();
        final initial = DocumentsState(selectedCollection: collection);

        final modified = initial.copyWith(clearSelectedCollection: true);

        expect(modified.selectedCollection, isNull);
      });

      test('updates isLoading', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(isLoading: true);

        expect(modified.isLoading, isTrue);
        expect(initial.isLoading, isFalse);
      });

      test('updates isLoadingMore', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(isLoadingMore: true);

        expect(modified.isLoadingMore, isTrue);
        expect(initial.isLoadingMore, isFalse);
      });

      test('updates isUploading', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(isUploading: true);

        expect(modified.isUploading, isTrue);
        expect(initial.isUploading, isFalse);
      });

      test('updates error', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(error: 'Test error');

        expect(modified.error, equals('Test error'));
        expect(initial.error, isNull);
      });

      test('clears error when clearError is true', () {
        const initial = DocumentsState(error: 'Previous error');

        final modified = initial.copyWith(clearError: true);

        expect(modified.error, isNull);
      });

      test('updates currentPage', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(currentPage: 5);

        expect(modified.currentPage, equals(5));
        expect(initial.currentPage, equals(1));
      });

      test('updates hasMore', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(hasMore: false);

        expect(modified.hasMore, isFalse);
        expect(initial.hasMore, isTrue);
      });

      test('updates searchQuery', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(searchQuery: 'test');

        expect(modified.searchQuery, equals('test'));
        expect(initial.searchQuery, isNull);
      });

      test('clears searchQuery when clearSearchQuery is true', () {
        const initial = DocumentsState(searchQuery: 'previous');

        final modified = initial.copyWith(clearSearchQuery: true);

        expect(modified.searchQuery, isNull);
      });

      test('updates filterContentType', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(filterContentType: 'application/pdf');

        expect(modified.filterContentType, equals('application/pdf'));
        expect(initial.filterContentType, isNull);
      });

      test('clears filterContentType when clearFilterContentType is true', () {
        const initial = DocumentsState(filterContentType: 'application/pdf');

        final modified = initial.copyWith(clearFilterContentType: true);

        expect(modified.filterContentType, isNull);
      });

      test('updates filterStatus', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(filterStatus: 'completed');

        expect(modified.filterStatus, equals('completed'));
        expect(initial.filterStatus, isNull);
      });

      test('clears filterStatus when clearFilterStatus is true', () {
        const initial = DocumentsState(filterStatus: 'completed');

        final modified = initial.copyWith(clearFilterStatus: true);

        expect(modified.filterStatus, isNull);
      });

      test('updates uploadProgress', () {
        const initial = DocumentsState();

        final modified = initial.copyWith(uploadProgress: 0.75);

        expect(modified.uploadProgress, equals(0.75));
        expect(initial.uploadProgress, equals(0.0));
      });

      test('preserves unmodified values', () {
        final document = createTestDocument();
        final collection = createTestCollection();
        final initial = DocumentsState(
          documents: [document],
          collections: [collection],
          selectedDocument: document,
          isLoading: true,
          currentPage: 3,
          hasMore: false,
          searchQuery: 'test',
          filterContentType: 'pdf',
          uploadProgress: 0.5,
        );

        final modified = initial.copyWith(isLoadingMore: true);

        expect(modified.documents.length, equals(1));
        expect(modified.collections.length, equals(1));
        expect(modified.selectedDocument, equals(document));
        expect(modified.isLoading, isTrue);
        expect(modified.isLoadingMore, isTrue);
        expect(modified.currentPage, equals(3));
        expect(modified.hasMore, isFalse);
        expect(modified.searchQuery, equals('test'));
        expect(modified.filterContentType, equals('pdf'));
        expect(modified.uploadProgress, equals(0.5));
      });
    });

    group('filtered documents', () {
      test('processingDocuments returns only processing documents', () {
        final documents = [
          createTestDocument(id: '1', processingStatus: 'processing'),
          createTestDocument(id: '2', processingStatus: 'completed'),
          createTestDocument(id: '3', processingStatus: 'pending'),
        ];
        final state = DocumentsState(documents: documents);

        expect(state.processingDocuments.length, equals(2));
        expect(state.processingDocuments.every((d) => d.isProcessing), isTrue);
      });

      test('readyDocuments returns only ready documents', () {
        final documents = [
          createTestDocument(id: '1', processingStatus: 'completed'),
          createTestDocument(id: '2', processingStatus: 'processing'),
          createTestDocument(id: '3', processingStatus: 'ready'),
        ];
        final state = DocumentsState(documents: documents);

        expect(state.readyDocuments.length, equals(2));
        expect(state.readyDocuments.every((d) => d.isReady), isTrue);
      });

      test('failedDocuments returns only failed documents', () {
        final documents = [
          createTestDocument(id: '1', processingStatus: 'failed'),
          createTestDocument(id: '2', processingStatus: 'completed'),
          createTestDocument(id: '3', processingStatus: 'failed'),
        ];
        final state = DocumentsState(documents: documents);

        expect(state.failedDocuments.length, equals(2));
        expect(state.failedDocuments.every((d) => d.isFailed), isTrue);
      });

      test('pdfDocuments returns only PDF documents', () {
        final documents = [
          createTestDocument(id: '1', contentType: 'application/pdf'),
          createTestDocument(id: '2', contentType: 'image/png'),
          createTestDocument(id: '3', contentType: 'application/pdf'),
        ];
        final state = DocumentsState(documents: documents);

        expect(state.pdfDocuments.length, equals(2));
        expect(state.pdfDocuments.every((d) => d.contentType.contains('pdf')), isTrue);
      });

      test('imageDocuments returns only image documents', () {
        final documents = [
          createTestDocument(id: '1', contentType: 'image/png'),
          createTestDocument(id: '2', contentType: 'application/pdf'),
          createTestDocument(id: '3', contentType: 'image/jpeg'),
        ];
        final state = DocumentsState(documents: documents);

        expect(state.imageDocuments.length, equals(2));
      });

      test('getByContentType returns documents matching content type', () {
        final documents = [
          createTestDocument(id: '1', contentType: 'application/pdf'),
          createTestDocument(id: '2', contentType: 'image/png'),
          createTestDocument(id: '3', contentType: 'application/pdf'),
        ];
        final state = DocumentsState(documents: documents);

        final pdfs = state.getByContentType('pdf');

        expect(pdfs.length, equals(2));
      });
    });

    group('searchLocally', () {
      test('returns all documents when query is empty', () {
        final documents = [
          createTestDocument(id: '1', title: 'Report'),
          createTestDocument(id: '2', title: 'Invoice'),
        ];
        final state = DocumentsState(documents: documents);

        final results = state.searchLocally('');

        expect(results.length, equals(2));
      });

      test('filters documents by title match', () {
        final documents = [
          createTestDocument(id: '1', title: 'Annual Report 2024'),
          createTestDocument(id: '2', title: 'Invoice'),
          createTestDocument(id: '3', title: 'Monthly Report'),
        ];
        final state = DocumentsState(documents: documents);

        final results = state.searchLocally('Report');

        expect(results.length, equals(2));
        expect(results.any((d) => d.title.contains('Report')), isTrue);
      });

      test('filters documents by filename match', () {
        final documents = [
          createTestDocument(id: '1', title: 'Doc 1', filename: 'report_2024.pdf'),
          createTestDocument(id: '2', title: 'Doc 2', filename: 'invoice.pdf'),
          createTestDocument(id: '3', title: 'Doc 3', filename: 'report_2023.pdf'),
        ];
        final state = DocumentsState(documents: documents);

        final results = state.searchLocally('report');

        expect(results.length, equals(2));
      });

      test('search is case insensitive', () {
        final documents = [
          createTestDocument(id: '1', title: 'Report'),
          createTestDocument(id: '2', title: 'REPORT'),
        ];
        final state = DocumentsState(documents: documents);

        final results = state.searchLocally('report');

        expect(results.length, equals(2));
      });

      test('returns empty list when no matches', () {
        final documents = [
          createTestDocument(id: '1', title: 'Report'),
          createTestDocument(id: '2', title: 'Invoice'),
        ];
        final state = DocumentsState(documents: documents);

        final results = state.searchLocally('Contract');

        expect(results, isEmpty);
      });
    });
  });

  group('DocumentsNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty DocumentsState', () {
      final state = container.read(documentsStateProvider);

      expect(state.documents, isEmpty);
      expect(state.collections, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('setDocuments updates documents list', () {
      final documents = [
        createTestDocument(id: '1'),
        createTestDocument(id: '2'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      final state = container.read(documentsStateProvider);
      expect(state.documents.length, equals(2));
    });

    test('setCollections updates collections list', () {
      final collections = [
        createTestCollection(id: '1'),
        createTestCollection(id: '2'),
      ];

      container.read(documentsStateProvider.notifier).setCollections(collections);

      final state = container.read(documentsStateProvider);
      expect(state.collections.length, equals(2));
    });

    test('addDocument prepends document to list', () {
      final document1 = createTestDocument(id: '1', title: 'First');
      final document2 = createTestDocument(id: '2', title: 'Second');

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setDocuments([document1]);
      notifier.addDocument(document2);

      final state = container.read(documentsStateProvider);
      expect(state.documents.length, equals(2));
      expect(state.documents.first.id, equals('2'));
    });

    test('updateDocument updates existing document by id', () {
      final document = createTestDocument(id: '1', title: 'Original');
      final updated = createTestDocument(id: '1', title: 'Updated');

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setDocuments([document]);
      notifier.updateDocument(updated);

      final state = container.read(documentsStateProvider);
      expect(state.documents.first.title, equals('Updated'));
    });

    test('updateDocument does nothing when id not found', () {
      final document = createTestDocument(id: '1', title: 'Original');
      final nonExistent = createTestDocument(id: '999', title: 'Nonexistent');

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setDocuments([document]);
      notifier.updateDocument(nonExistent);

      final state = container.read(documentsStateProvider);
      expect(state.documents.length, equals(1));
      expect(state.documents.first.title, equals('Original'));
    });

    test('removeDocument removes document by id', () {
      final documents = [
        createTestDocument(id: '1'),
        createTestDocument(id: '2'),
      ];

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setDocuments(documents);
      notifier.removeDocument('1');

      final state = container.read(documentsStateProvider);
      expect(state.documents.length, equals(1));
      expect(state.documents.first.id, equals('2'));
    });

    test('removeDocument does nothing when id not found', () {
      final document = createTestDocument(id: '1');

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setDocuments([document]);
      notifier.removeDocument('999');

      final state = container.read(documentsStateProvider);
      expect(state.documents.length, equals(1));
    });

    test('clearSelectedDocument clears the selected document', () {
      container.read(documentsStateProvider.notifier).clearSelectedDocument();

      final state = container.read(documentsStateProvider);
      expect(state.selectedDocument, isNull);
    });

    test('selectCollection sets the selected collection', () {
      final collection = createTestCollection();

      container.read(documentsStateProvider.notifier).selectCollection(collection);

      final state = container.read(documentsStateProvider);
      expect(state.selectedCollection, equals(collection));
    });

    test('clearSelectedCollection clears the selected collection', () {
      final collection = createTestCollection();

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.selectCollection(collection);
      notifier.clearSelectedCollection();

      final state = container.read(documentsStateProvider);
      expect(state.selectedCollection, isNull);
    });

    test('setUploading updates uploading state', () {
      container.read(documentsStateProvider.notifier).setUploading(true);

      final state = container.read(documentsStateProvider);
      expect(state.isUploading, isTrue);
    });

    test('setUploadProgress updates upload progress', () {
      container.read(documentsStateProvider.notifier).setUploadProgress(0.75);

      final state = container.read(documentsStateProvider);
      expect(state.uploadProgress, equals(0.75));
    });

    test('clearFilters clears all filter parameters', () {
      final notifier = container.read(documentsStateProvider.notifier);
      notifier.clearFilters();

      final state = container.read(documentsStateProvider);
      expect(state.searchQuery, isNull);
      expect(state.filterContentType, isNull);
      expect(state.filterStatus, isNull);
    });

    test('clear resets state to initial values', () {
      final document = createTestDocument();
      final collection = createTestCollection();

      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setDocuments([document]);
      notifier.setCollections([collection]);
      notifier.clear();

      final state = container.read(documentsStateProvider);
      expect(state.documents, isEmpty);
      expect(state.collections, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, equals(1));
    });

    test('clearError clears the error state', () {
      final notifier = container.read(documentsStateProvider.notifier);
      notifier.setError('Test error');
      notifier.clearError();

      final state = container.read(documentsStateProvider);
      expect(state.error, isNull);
    });

    test('setLoading updates loading state', () {
      container.read(documentsStateProvider.notifier).setLoading(true);

      final state = container.read(documentsStateProvider);
      expect(state.isLoading, isTrue);
    });

    test('setError updates error state', () {
      container.read(documentsStateProvider.notifier).setError('Test error');

      final state = container.read(documentsStateProvider);
      expect(state.error, equals('Test error'));
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

    test('documentsLoadingProvider reflects loading state', () {
      expect(container.read(documentsLoadingProvider), isFalse);

      container.read(documentsStateProvider.notifier).setLoading(true);

      expect(container.read(documentsLoadingProvider), isTrue);
    });

    test('documentsErrorProvider reflects error state', () {
      expect(container.read(documentsErrorProvider), isNull);

      container.read(documentsStateProvider.notifier).setError('Error');

      expect(container.read(documentsErrorProvider), equals('Error'));
    });

    test('selectedDocumentProvider reflects selected document', () {
      expect(container.read(selectedDocumentProvider), isNull);
    });

    test('documentCollectionsProvider reflects collections', () {
      final collections = [createTestCollection()];

      container.read(documentsStateProvider.notifier).setCollections(collections);

      expect(container.read(documentCollectionsProvider).length, equals(1));
    });

    test('selectedCollectionProvider reflects selected collection', () {
      expect(container.read(selectedCollectionProvider), isNull);

      final collection = createTestCollection();
      container.read(documentsStateProvider.notifier).selectCollection(collection);

      expect(container.read(selectedCollectionProvider), equals(collection));
    });

    test('processingDocumentsProvider returns only processing documents', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'processing'),
        createTestDocument(id: '2', processingStatus: 'completed'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(processingDocumentsProvider).length, equals(1));
      expect(container.read(processingDocumentsProvider).first.id, equals('1'));
    });

    test('readyDocumentsProvider returns only ready documents', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'completed'),
        createTestDocument(id: '2', processingStatus: 'processing'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(readyDocumentsProvider).length, equals(1));
      expect(container.read(readyDocumentsProvider).first.id, equals('1'));
    });

    test('failedDocumentsProvider returns only failed documents', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'failed'),
        createTestDocument(id: '2', processingStatus: 'completed'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(failedDocumentsProvider).length, equals(1));
      expect(container.read(failedDocumentsProvider).first.id, equals('1'));
    });

    test('pdfDocumentsProvider returns only PDF documents', () {
      final documents = [
        createTestDocument(id: '1', contentType: 'application/pdf'),
        createTestDocument(id: '2', contentType: 'image/png'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(pdfDocumentsProvider).length, equals(1));
      expect(container.read(pdfDocumentsProvider).first.id, equals('1'));
    });

    test('imageDocumentsProvider returns only image documents', () {
      final documents = [
        createTestDocument(id: '1', contentType: 'image/png'),
        createTestDocument(id: '2', contentType: 'application/pdf'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(imageDocumentsProvider).length, equals(1));
      expect(container.read(imageDocumentsProvider).first.id, equals('1'));
    });

    test('documentsCountProvider returns total count', () {
      final documents = [
        createTestDocument(id: '1'),
        createTestDocument(id: '2'),
        createTestDocument(id: '3'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(documentsCountProvider), equals(3));
    });

    test('readyDocumentsCountProvider returns ready count', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'completed'),
        createTestDocument(id: '2', processingStatus: 'processing'),
        createTestDocument(id: '3', processingStatus: 'ready'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(readyDocumentsCountProvider), equals(2));
    });

    test('processingDocumentsCountProvider returns processing count', () {
      final documents = [
        createTestDocument(id: '1', processingStatus: 'processing'),
        createTestDocument(id: '2', processingStatus: 'completed'),
        createTestDocument(id: '3', processingStatus: 'pending'),
      ];

      container.read(documentsStateProvider.notifier).setDocuments(documents);

      expect(container.read(processingDocumentsCountProvider), equals(2));
    });

    test('documentsUploadingProvider reflects uploading state', () {
      expect(container.read(documentsUploadingProvider), isFalse);

      container.read(documentsStateProvider.notifier).setUploading(true);

      expect(container.read(documentsUploadingProvider), isTrue);
    });

    test('documentsUploadProgressProvider reflects upload progress', () {
      expect(container.read(documentsUploadProgressProvider), equals(0.0));

      container.read(documentsStateProvider.notifier).setUploadProgress(0.5);

      expect(container.read(documentsUploadProgressProvider), equals(0.5));
    });
  });
}
