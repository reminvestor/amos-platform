import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/document.dart';
import 'package:amos_mobile/services/documents_service.dart';

/// State for documents management
class DocumentsState {
  final List<Document> documents;
  final List<DocumentCollection> collections;
  final Document? selectedDocument;
  final DocumentCollection? selectedCollection;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isUploading;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final String? searchQuery;
  final String? filterContentType;
  final String? filterStatus;
  final double uploadProgress;

  const DocumentsState({
    this.documents = const [],
    this.collections = const [],
    this.selectedDocument,
    this.selectedCollection,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isUploading = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
    this.searchQuery,
    this.filterContentType,
    this.filterStatus,
    this.uploadProgress = 0.0,
  });

  DocumentsState copyWith({
    List<Document>? documents,
    List<DocumentCollection>? collections,
    Document? selectedDocument,
    DocumentCollection? selectedCollection,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isUploading,
    String? error,
    int? currentPage,
    bool? hasMore,
    String? searchQuery,
    String? filterContentType,
    String? filterStatus,
    double? uploadProgress,
    bool clearSelectedDocument = false,
    bool clearSelectedCollection = false,
    bool clearError = false,
    bool clearSearchQuery = false,
    bool clearFilterContentType = false,
    bool clearFilterStatus = false,
  }) {
    return DocumentsState(
      documents: documents ?? this.documents,
      collections: collections ?? this.collections,
      selectedDocument: clearSelectedDocument ? null : (selectedDocument ?? this.selectedDocument),
      selectedCollection: clearSelectedCollection ? null : (selectedCollection ?? this.selectedCollection),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isUploading: isUploading ?? this.isUploading,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      filterContentType: clearFilterContentType ? null : (filterContentType ?? this.filterContentType),
      filterStatus: clearFilterStatus ? null : (filterStatus ?? this.filterStatus),
      uploadProgress: uploadProgress ?? this.uploadProgress,
    );
  }

  /// Get documents filtered by processing status
  List<Document> get processingDocuments =>
      documents.where((d) => d.isProcessing).toList();

  List<Document> get readyDocuments =>
      documents.where((d) => d.isReady).toList();

  List<Document> get failedDocuments =>
      documents.where((d) => d.isFailed).toList();

  /// Get documents by content type
  List<Document> getByContentType(String contentType) {
    return documents.where((d) => d.contentType.contains(contentType)).toList();
  }

  /// Get PDF documents
  List<Document> get pdfDocuments => getByContentType('pdf');

  /// Get image documents
  List<Document> get imageDocuments {
    return documents.where((d) =>
        d.contentType.contains('image') ||
        d.contentType.contains('png') ||
        d.contentType.contains('jpeg') ||
        d.contentType.contains('jpg')
    ).toList();
  }

  /// Search documents locally by title or filename
  List<Document> searchLocally(String query) {
    if (query.isEmpty) return documents;
    final lowerQuery = query.toLowerCase();
    return documents.where((d) {
      final title = d.title.toLowerCase();
      final filename = d.filename.toLowerCase();
      return title.contains(lowerQuery) || filename.contains(lowerQuery);
    }).toList();
  }

  /// Check if there are any documents
  bool get isEmpty => documents.isEmpty;

  /// Get total document count
  int get totalCount => documents.length;

  /// Get ready document count
  int get readyCount => readyDocuments.length;

  /// Get processing document count
  int get processingCount => processingDocuments.length;

  /// Check if currently busy
  bool get isBusy => isLoading || isUploading;
}

/// Notifier for documents state management
class DocumentsNotifier extends Notifier<DocumentsState> {
  late final DocumentsService _documentsService;

  @override
  DocumentsState build() {
    _documentsService = ref.read(documentsServiceProvider);
    return const DocumentsState();
  }

  /// Load documents from API
  Future<void> loadDocuments({
    String? search,
    String? contentType,
    String? status,
    bool refresh = false,
  }) async {
    if (state.isLoading) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      searchQuery: search,
      filterContentType: contentType,
      filterStatus: status,
      currentPage: refresh ? 1 : state.currentPage,
    );

    try {
      final documents = await _documentsService.getDocuments(
        search: search,
        contentType: contentType,
        status: status,
        page: refresh ? 1 : state.currentPage,
      );

      state = state.copyWith(
        documents: refresh ? documents : [...state.documents, ...documents],
        isLoading: false,
        hasMore: documents.length >= 20,
        currentPage: refresh ? 1 : state.currentPage,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load more documents (pagination)
  Future<void> loadMoreDocuments() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final documents = await _documentsService.getDocuments(
        search: state.searchQuery,
        contentType: state.filterContentType,
        status: state.filterStatus,
        page: state.currentPage + 1,
      );

      state = state.copyWith(
        documents: [...state.documents, ...documents],
        isLoadingMore: false,
        hasMore: documents.length >= 20,
        currentPage: state.currentPage + 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  /// Load document collections
  Future<void> loadCollections() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final collections = await _documentsService.getCollections();
      state = state.copyWith(
        collections: collections,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Select a document for detail view
  Future<void> selectDocument(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final document = await _documentsService.getDocument(id);
      state = state.copyWith(
        selectedDocument: document,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clear selected document
  void clearSelectedDocument() {
    state = state.copyWith(clearSelectedDocument: true);
  }

  /// Select a collection
  void selectCollection(DocumentCollection collection) {
    state = state.copyWith(selectedCollection: collection);
  }

  /// Clear selected collection
  void clearSelectedCollection() {
    state = state.copyWith(clearSelectedCollection: true);
  }

  /// Set documents directly (for testing or external updates)
  void setDocuments(List<Document> documents) {
    state = state.copyWith(documents: documents);
  }

  /// Set collections directly
  void setCollections(List<DocumentCollection> collections) {
    state = state.copyWith(collections: collections);
  }

  /// Add a document to the list
  void addDocument(Document document) {
    state = state.copyWith(documents: [document, ...state.documents]);
  }

  /// Update a document in the list
  void updateDocument(Document document) {
    final index = state.documents.indexWhere((d) => d.id == document.id);
    if (index != -1) {
      final updatedList = [...state.documents];
      updatedList[index] = document;
      state = state.copyWith(
        documents: updatedList,
        selectedDocument: state.selectedDocument?.id == document.id
            ? document
            : state.selectedDocument,
      );
    }
  }

  /// Remove a document from the list
  void removeDocument(String id) {
    state = state.copyWith(
      documents: state.documents.where((d) => d.id != id).toList(),
      clearSelectedDocument: state.selectedDocument?.id == id,
    );
  }

  /// Set uploading state
  void setUploading(bool uploading) {
    state = state.copyWith(isUploading: uploading);
  }

  /// Set upload progress
  void setUploadProgress(double progress) {
    state = state.copyWith(uploadProgress: progress);
  }

  /// Clear all filters
  void clearFilters() {
    state = state.copyWith(
      clearSearchQuery: true,
      clearFilterContentType: true,
      clearFilterStatus: true,
    );
  }

  /// Clear all documents
  void clear() {
    state = const DocumentsState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set loading state
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  /// Set error state
  void setError(String error) {
    state = state.copyWith(error: error);
  }
}

// Service provider
final documentsServiceProvider = Provider<DocumentsService>((ref) => DocumentsService());

// State provider
final documentsStateProvider = NotifierProvider<DocumentsNotifier, DocumentsState>(
  DocumentsNotifier.new,
);

// Convenience providers
final documentsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(documentsStateProvider).isLoading;
});

final documentsErrorProvider = Provider<String?>((ref) {
  return ref.watch(documentsStateProvider).error;
});

final selectedDocumentProvider = Provider<Document?>((ref) {
  return ref.watch(documentsStateProvider).selectedDocument;
});

final documentCollectionsProvider = Provider<List<DocumentCollection>>((ref) {
  return ref.watch(documentsStateProvider).collections;
});

final selectedCollectionProvider = Provider<DocumentCollection?>((ref) {
  return ref.watch(documentsStateProvider).selectedCollection;
});

final processingDocumentsProvider = Provider<List<Document>>((ref) {
  return ref.watch(documentsStateProvider).processingDocuments;
});

final readyDocumentsProvider = Provider<List<Document>>((ref) {
  return ref.watch(documentsStateProvider).readyDocuments;
});

final failedDocumentsProvider = Provider<List<Document>>((ref) {
  return ref.watch(documentsStateProvider).failedDocuments;
});

final pdfDocumentsProvider = Provider<List<Document>>((ref) {
  return ref.watch(documentsStateProvider).pdfDocuments;
});

final imageDocumentsProvider = Provider<List<Document>>((ref) {
  return ref.watch(documentsStateProvider).imageDocuments;
});

final documentsCountProvider = Provider<int>((ref) {
  return ref.watch(documentsStateProvider).totalCount;
});

final readyDocumentsCountProvider = Provider<int>((ref) {
  return ref.watch(documentsStateProvider).readyCount;
});

final processingDocumentsCountProvider = Provider<int>((ref) {
  return ref.watch(documentsStateProvider).processingCount;
});

final documentsUploadingProvider = Provider<bool>((ref) {
  return ref.watch(documentsStateProvider).isUploading;
});

final documentsUploadProgressProvider = Provider<double>((ref) {
  return ref.watch(documentsStateProvider).uploadProgress;
});
