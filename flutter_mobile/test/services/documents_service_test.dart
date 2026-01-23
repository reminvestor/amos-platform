import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/document.dart';

// Note: DocumentsService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('Document Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'filename': 'report.pdf',
        'title': 'Q4 Report',
        'content_type': 'application/pdf',
        'file_size': '2.5 MB',
        'file_size_bytes': 2621440,
        'processing_status': 'completed',
        'processing_progress': 100,
        'chunks_count': 45,
        'view_count': 12,
        'download_count': 5,
        'collection_name': 'Business Reports',
        'collection_id': '10',
        'icon': 'file-pdf',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
      };

      final document = Document.fromJson(json);

      expect(document.id, equals('1'));
      expect(document.filename, equals('report.pdf'));
      expect(document.title, equals('Q4 Report'));
      expect(document.contentType, equals('application/pdf'));
      expect(document.fileSize, equals('2.5 MB'));
      expect(document.fileSizeBytes, equals(2621440));
      expect(document.processingStatus, equals('completed'));
      expect(document.processingProgress, equals(100));
      expect(document.chunksCount, equals(45));
      expect(document.viewCount, equals(12));
      expect(document.downloadCount, equals(5));
      expect(document.collectionName, equals('Business Reports'));
      expect(document.collectionId, equals('10'));
      expect(document.icon, equals('file-pdf'));
      expect(document.isReady, isTrue);
      expect(document.isProcessing, isFalse);
      expect(document.isFailed, isFalse);
    });

    test('parses detailed fields', () {
      final json = {
        'id': 2,
        'filename': 'manual.pdf',
        'title': 'User Manual',
        'content_type': 'application/pdf',
        'file_size': '5 MB',
        'file_size_bytes': 5242880,
        'processing_status': 'completed',
        'processing_progress': 100,
        'chunks_count': 100,
        'view_count': 50,
        'download_count': 20,
        'collection_name': 'Manuals',
        'collection_id': '20',
        'icon': 'file-pdf',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
        'processing_stage': 'embedding',
        'processing_stage_description': 'Creating vector embeddings',
        'embedded_chunks_count': 95,
        'tags': [
          {'id': 1, 'name': 'manual'},
          {'id': 2, 'name': 'documentation'},
        ],
        'subjects': [
          {'id': 1, 'name': 'Technical'},
          {'id': 2, 'name': 'User Guide'},
        ],
        'has_tables': true,
        'has_images': true,
        'author': 'John Doe',
        'language': 'en',
        'version': 2,
        'last_accessed_at': '2024-01-20T08:00:00.000Z',
      };

      final document = Document.fromJson(json);

      expect(document.processingStage, equals('embedding'));
      expect(document.processingStageDescription, equals('Creating vector embeddings'));
      expect(document.embeddedChunksCount, equals(95));
      expect(document.tags, hasLength(2));
      expect(document.tags![0].name, equals('manual'));
      expect(document.subjects, hasLength(2));
      expect(document.subjects![0].name, equals('Technical'));
      expect(document.hasTables, isTrue);
      expect(document.hasImages, isTrue);
      expect(document.author, equals('John Doe'));
      expect(document.language, equals('en'));
      expect(document.version, equals(2));
      expect(document.lastAccessedAt, equals(DateTime.parse('2024-01-20T08:00:00.000Z')));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 3,
        'filename': 'notes.txt',
        'content_type': 'text/plain',
        'file_size': '1 KB',
        'file_size_bytes': 1024,
        'processing_status': 'pending',
        'processing_progress': 0,
        'chunks_count': 0,
        'view_count': 0,
        'download_count': 0,
        'collection_name': 'Notes',
        'collection_id': '30',
        'icon': 'file-text',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final document = Document.fromJson(json);

      expect(document.title, equals('notes.txt')); // Falls back to filename
      expect(document.processingStage, isNull);
      expect(document.tags, isNull);
      expect(document.subjects, isNull);
      expect(document.hasTables, isNull);
      expect(document.author, isNull);
      expect(document.lastAccessedAt, isNull);
    });

    test('uses filename as title fallback', () {
      final json = {
        'id': 4,
        'filename': 'document.docx',
        'title': null,
        'content_type': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'file_size': '50 KB',
        'file_size_bytes': 51200,
        'processing_status': 'processing',
        'processing_progress': 50,
        'chunks_count': 10,
        'view_count': 0,
        'download_count': 0,
        'collection_name': 'Documents',
        'collection_id': '40',
        'icon': 'file-text',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final document = Document.fromJson(json);

      expect(document.title, equals('document.docx'));
    });
  });

  group('Document Status Helpers', () {
    test('isProcessing returns true for pending status', () {
      final document = Document(
        id: '1',
        filename: 'test.pdf',
        title: 'Test',
        contentType: 'application/pdf',
        fileSize: '1 MB',
        fileSizeBytes: 1048576,
        processingStatus: 'pending',
        processingProgress: 0,
        chunksCount: 0,
        viewCount: 0,
        downloadCount: 0,
        collectionName: 'Test',
        collectionId: '1',
        icon: 'file',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(document.isProcessing, isTrue);
      expect(document.isReady, isFalse);
      expect(document.isFailed, isFalse);
    });

    test('isProcessing returns true for processing status', () {
      final document = Document(
        id: '1',
        filename: 'test.pdf',
        title: 'Test',
        contentType: 'application/pdf',
        fileSize: '1 MB',
        fileSizeBytes: 1048576,
        processingStatus: 'processing',
        processingProgress: 50,
        chunksCount: 10,
        viewCount: 0,
        downloadCount: 0,
        collectionName: 'Test',
        collectionId: '1',
        icon: 'file',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(document.isProcessing, isTrue);
    });

    test('isReady returns true for completed status', () {
      final document = Document(
        id: '1',
        filename: 'test.pdf',
        title: 'Test',
        contentType: 'application/pdf',
        fileSize: '1 MB',
        fileSizeBytes: 1048576,
        processingStatus: 'completed',
        processingProgress: 100,
        chunksCount: 20,
        viewCount: 5,
        downloadCount: 2,
        collectionName: 'Test',
        collectionId: '1',
        icon: 'file',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(document.isReady, isTrue);
      expect(document.isProcessing, isFalse);
    });

    test('isReady returns true for ready status', () {
      final document = Document(
        id: '1',
        filename: 'test.pdf',
        title: 'Test',
        contentType: 'application/pdf',
        fileSize: '1 MB',
        fileSizeBytes: 1048576,
        processingStatus: 'ready',
        processingProgress: 100,
        chunksCount: 20,
        viewCount: 5,
        downloadCount: 2,
        collectionName: 'Test',
        collectionId: '1',
        icon: 'file',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(document.isReady, isTrue);
    });

    test('isFailed returns true for failed status', () {
      final document = Document(
        id: '1',
        filename: 'test.pdf',
        title: 'Test',
        contentType: 'application/pdf',
        fileSize: '1 MB',
        fileSizeBytes: 1048576,
        processingStatus: 'failed',
        processingProgress: 25,
        chunksCount: 5,
        viewCount: 0,
        downloadCount: 0,
        collectionName: 'Test',
        collectionId: '1',
        icon: 'file',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(document.isFailed, isTrue);
      expect(document.isReady, isFalse);
      expect(document.isProcessing, isFalse);
    });
  });

  group('Document Status Labels', () {
    test('returns correct labels for each status', () {
      final statuses = ['pending', 'processing', 'completed', 'ready', 'failed', 'unknown'];
      final expectedLabels = ['Pending', 'Processing', 'Ready', 'Ready', 'Failed', 'unknown'];

      for (int i = 0; i < statuses.length; i++) {
        final document = Document(
          id: '1',
          filename: 'test.pdf',
          title: 'Test',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: statuses[i],
          processingProgress: 0,
          chunksCount: 0,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(document.statusLabel, equals(expectedLabels[i]));
      }
    });
  });

  group('DocumentTag Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'important',
      };

      final tag = DocumentTag.fromJson(json);

      expect(tag.id, equals('1'));
      expect(tag.name, equals('important'));
    });

    test('handles missing name', () {
      final json = {
        'id': 2,
      };

      final tag = DocumentTag.fromJson(json);

      expect(tag.id, equals('2'));
      expect(tag.name, equals(''));
    });
  });

  group('DocumentSubject Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Technical',
      };

      final subject = DocumentSubject.fromJson(json);

      expect(subject.id, equals('1'));
      expect(subject.name, equals('Technical'));
    });

    test('handles missing name', () {
      final json = {
        'id': 2,
      };

      final subject = DocumentSubject.fromJson(json);

      expect(subject.id, equals('2'));
      expect(subject.name, equals(''));
    });
  });

  group('DocumentCollection Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Business Reports',
        'status': 'active',
        'document_count': 25,
        'chunk_count': 500,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
      };

      final collection = DocumentCollection.fromJson(json);

      expect(collection.id, equals('1'));
      expect(collection.name, equals('Business Reports'));
      expect(collection.status, equals('active'));
      expect(collection.documentCount, equals(25));
      expect(collection.chunkCount, equals(500));
      expect(collection.createdAt, equals(DateTime.parse('2024-01-01T00:00:00.000Z')));
      expect(collection.updatedAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
    });

    test('handles missing optional fields with defaults', () {
      final json = {
        'id': 2,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final collection = DocumentCollection.fromJson(json);

      expect(collection.name, equals('Unknown'));
      expect(collection.status, equals('pending'));
      expect(collection.documentCount, equals(0));
      expect(collection.chunkCount, equals(0));
    });
  });

  group('Query Parameter Building', () {
    test('builds basic pagination parameters', () {
      const page = 1;

      final queryParams = <String, dynamic>{
        'page': page,
      };

      expect(queryParams['page'], equals(1));
    });

    test('adds search parameter when provided', () {
      const page = 1;
      const search = 'report';

      final queryParams = <String, dynamic>{
        'page': page,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams['search'], equals('report'));
    });

    test('adds content_type parameter when provided', () {
      const page = 1;
      const contentType = 'application/pdf';

      final queryParams = <String, dynamic>{
        'page': page,
      };
      if (contentType.isNotEmpty) {
        queryParams['content_type'] = contentType;
      }

      expect(queryParams['content_type'], equals('application/pdf'));
    });

    test('adds status parameter when provided', () {
      const page = 1;
      const status = 'completed';

      final queryParams = <String, dynamic>{
        'page': page,
      };
      if (status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams['status'], equals('completed'));
    });

    test('builds full query parameters with all options', () {
      const page = 2;
      const search = 'quarterly';
      const contentType = 'application/pdf';
      const status = 'completed';

      final queryParams = <String, dynamic>{
        'page': page,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (contentType.isNotEmpty) {
        queryParams['content_type'] = contentType;
      }
      if (status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams.length, equals(4));
      expect(queryParams['page'], equals(2));
      expect(queryParams['search'], equals('quarterly'));
      expect(queryParams['content_type'], equals('application/pdf'));
      expect(queryParams['status'], equals('completed'));
    });

    test('handles null parameters', () {
      const page = 1;
      const String? search = null;
      const String? contentType = null;
      const String? status = null;

      final queryParams = <String, dynamic>{
        'page': page,
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (contentType != null && contentType.isNotEmpty) {
        queryParams['content_type'] = contentType;
      }
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams.length, equals(1));
      expect(queryParams.containsKey('search'), isFalse);
      expect(queryParams.containsKey('content_type'), isFalse);
      expect(queryParams.containsKey('status'), isFalse);
    });
  });

  group('Documents List Response Parsing', () {
    test('parses documents list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'filename': 'report1.pdf',
            'title': 'Report 1',
            'content_type': 'application/pdf',
            'file_size': '1 MB',
            'file_size_bytes': 1048576,
            'processing_status': 'completed',
            'processing_progress': 100,
            'chunks_count': 20,
            'view_count': 10,
            'download_count': 5,
            'collection_name': 'Reports',
            'collection_id': '1',
            'icon': 'file-pdf',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'filename': 'report2.pdf',
            'title': 'Report 2',
            'content_type': 'application/pdf',
            'file_size': '2 MB',
            'file_size_bytes': 2097152,
            'processing_status': 'processing',
            'processing_progress': 50,
            'chunks_count': 10,
            'view_count': 0,
            'download_count': 0,
            'collection_name': 'Reports',
            'collection_id': '1',
            'icon': 'file-pdf',
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final documentsList = responseData['data'] as List? ?? [];
      final documents = documentsList.map((json) => Document.fromJson(json)).toList();

      expect(documents, hasLength(2));
      expect(documents[0].id, equals('1'));
      expect(documents[0].title, equals('Report 1'));
      expect(documents[0].isReady, isTrue);
      expect(documents[1].id, equals('2'));
      expect(documents[1].title, equals('Report 2'));
      expect(documents[1].isProcessing, isTrue);
    });

    test('handles empty documents list', () {
      final responseData = {'data': []};

      final documentsList = responseData['data'] as List? ?? [];
      final documents = documentsList.map((json) => Document.fromJson(json)).toList();

      expect(documents, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final documentsList = responseData['data'] as List? ?? [];
      final documents = documentsList.map((json) => Document.fromJson(json)).toList();

      expect(documents, isEmpty);
    });
  });

  group('Collections Response Parsing', () {
    test('parses collections list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'name': 'Business Reports',
            'status': 'active',
            'document_count': 25,
            'chunk_count': 500,
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'name': 'Marketing Materials',
            'status': 'active',
            'document_count': 15,
            'chunk_count': 300,
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final collectionsList = responseData['data'] as List? ?? [];
      final collections = collectionsList.map((json) => DocumentCollection.fromJson(json)).toList();

      expect(collections, hasLength(2));
      expect(collections[0].name, equals('Business Reports'));
      expect(collections[0].documentCount, equals(25));
      expect(collections[1].name, equals('Marketing Materials'));
      expect(collections[1].documentCount, equals(15));
    });
  });

  group('Document Status Response Parsing', () {
    test('parses status response', () {
      final response = {
        'status': 'processing',
        'progress': 75,
        'stage': 'embedding',
        'stage_description': 'Creating vector embeddings',
        'chunks_processed': 30,
        'chunks_total': 40,
      };

      expect(response['status'], equals('processing'));
      expect(response['progress'], equals(75));
      expect(response['stage'], equals('embedding'));
    });
  });

  group('Upload Response Parsing', () {
    test('parses successful upload response', () {
      final response = <String, dynamic>{
        'success': true,
        'document': <String, dynamic>{
          'id': 1,
          'filename': 'uploaded.pdf',
          'title': 'Uploaded Document',
          'content_type': 'application/pdf',
          'file_size': '1 MB',
          'file_size_bytes': 1048576,
          'processing_status': 'pending',
          'processing_progress': 0,
          'chunks_count': 0,
          'view_count': 0,
          'download_count': 0,
          'collection_name': 'Uploads',
          'collection_id': '1',
          'icon': 'file-pdf',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        },
      };

      expect(response['success'], isTrue);
      final document = Document.fromJson(response['document'] as Map<String, dynamic>);
      expect(document.filename, equals('uploaded.pdf'));
      expect(document.processingStatus, equals('pending'));
    });

    test('handles upload failure response', () {
      final response = {
        'success': false,
        'error': 'File type not supported',
      };

      expect(response['success'], isFalse);
      expect(response['error'], equals('File type not supported'));
    });
  });

  group('Dio HTTP Client Tests', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /api/v1/documents returns documents list', () async {
      dioAdapter.onGet(
        '/api/v1/documents',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'filename': 'test.pdf',
              'title': 'Test Document',
              'content_type': 'application/pdf',
              'file_size': '1 MB',
              'file_size_bytes': 1048576,
              'processing_status': 'completed',
              'processing_progress': 100,
              'chunks_count': 20,
              'view_count': 5,
              'download_count': 2,
              'collection_name': 'Test',
              'collection_id': '1',
              'icon': 'file-pdf',
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/documents');

      expect(response.statusCode, equals(200));
      expect(response.data['data'], hasLength(1));

      final documents = (response.data['data'] as List)
          .map((json) => Document.fromJson(json))
          .toList();
      expect(documents[0].title, equals('Test Document'));
    });

    test('GET /api/v1/documents with query parameters', () async {
      dioAdapter.onGet(
        '/api/v1/documents',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'filename': 'report.pdf',
              'title': 'Q4 Report',
              'content_type': 'application/pdf',
              'file_size': '1 MB',
              'file_size_bytes': 1048576,
              'processing_status': 'completed',
              'processing_progress': 100,
              'chunks_count': 20,
              'view_count': 5,
              'download_count': 2,
              'collection_name': 'Reports',
              'collection_id': '1',
              'icon': 'file-pdf',
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
        queryParameters: {
          'page': 1,
          'search': 'report',
          'status': 'completed',
        },
      );

      final response = await dio.get('/api/v1/documents', queryParameters: {
        'page': 1,
        'search': 'report',
        'status': 'completed',
      });

      expect(response.statusCode, equals(200));
    });

    test('GET /api/v1/documents/:id returns single document', () async {
      dioAdapter.onGet(
        '/api/v1/documents/1',
        (server) => server.reply(200, {
          'id': 1,
          'filename': 'detailed.pdf',
          'title': 'Detailed Document',
          'content_type': 'application/pdf',
          'file_size': '5 MB',
          'file_size_bytes': 5242880,
          'processing_status': 'completed',
          'processing_progress': 100,
          'chunks_count': 100,
          'view_count': 50,
          'download_count': 20,
          'collection_name': 'Reports',
          'collection_id': '1',
          'icon': 'file-pdf',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
          'tags': [
            {'id': 1, 'name': 'important'},
          ],
        }),
      );

      final response = await dio.get('/api/v1/documents/1');

      expect(response.statusCode, equals(200));
      final document = Document.fromJson(response.data);
      expect(document.title, equals('Detailed Document'));
      expect(document.tags, hasLength(1));
    });

    test('GET /api/v1/documents/collections returns collections', () async {
      dioAdapter.onGet(
        '/api/v1/documents/collections',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'name': 'Reports',
              'status': 'active',
              'document_count': 25,
              'chunk_count': 500,
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/documents/collections');

      expect(response.statusCode, equals(200));
      final collections = (response.data['data'] as List)
          .map((json) => DocumentCollection.fromJson(json))
          .toList();
      expect(collections[0].name, equals('Reports'));
    });

    test('DELETE /api/v1/documents/:id deletes document', () async {
      dioAdapter.onDelete(
        '/api/v1/documents/1',
        (server) => server.reply(204, null),
      );

      final response = await dio.delete('/api/v1/documents/1');

      expect(response.statusCode, equals(204));
    });

    test('handles 404 not found error', () async {
      dioAdapter.onGet(
        '/api/v1/documents/999',
        (server) => server.reply(404, {'error': 'Document not found'}),
      );

      expect(
        () => dio.get('/api/v1/documents/999'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
