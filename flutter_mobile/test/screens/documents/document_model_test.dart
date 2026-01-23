import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/document.dart';

void main() {
  group('Document', () {
    final createdAt = DateTime(2025, 1, 15, 10, 0);
    final updatedAt = DateTime(2025, 1, 15, 12, 0);

    test('creates with required values', () {
      final doc = Document(
        id: '1',
        filename: 'report.pdf',
        title: 'Annual Report',
        contentType: 'application/pdf',
        fileSize: '2.5 MB',
        fileSizeBytes: 2621440,
        processingStatus: 'completed',
        processingProgress: 100,
        chunksCount: 50,
        viewCount: 10,
        downloadCount: 5,
        collectionName: 'Reports',
        collectionId: 'col-1',
        icon: 'file-text',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(doc.id, '1');
      expect(doc.filename, 'report.pdf');
      expect(doc.title, 'Annual Report');
      expect(doc.contentType, 'application/pdf');
      expect(doc.fileSize, '2.5 MB');
      expect(doc.fileSizeBytes, 2621440);
      expect(doc.processingStatus, 'completed');
      expect(doc.processingProgress, 100);
      expect(doc.chunksCount, 50);
      expect(doc.viewCount, 10);
      expect(doc.downloadCount, 5);
      expect(doc.collectionName, 'Reports');
      expect(doc.icon, 'file-text');
    });

    test('creates with optional values', () {
      final doc = Document(
        id: '2',
        filename: 'data.xlsx',
        title: 'Sales Data',
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        fileSize: '1.2 MB',
        fileSizeBytes: 1258291,
        processingStatus: 'completed',
        processingProgress: 100,
        chunksCount: 30,
        viewCount: 5,
        downloadCount: 2,
        collectionName: 'Data',
        collectionId: 'col-2',
        icon: 'table',
        createdAt: createdAt,
        updatedAt: updatedAt,
        processingStage: 'embedding',
        processingStageDescription: 'Creating embeddings',
        embeddedChunksCount: 28,
        hasTables: true,
        hasImages: false,
        author: 'John Doe',
        language: 'en',
        version: 2,
        lastAccessedAt: updatedAt,
      );

      expect(doc.processingStage, 'embedding');
      expect(doc.processingStageDescription, 'Creating embeddings');
      expect(doc.embeddedChunksCount, 28);
      expect(doc.hasTables, true);
      expect(doc.hasImages, false);
      expect(doc.author, 'John Doe');
      expect(doc.language, 'en');
      expect(doc.version, 2);
      expect(doc.lastAccessedAt, updatedAt);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'filename': 'guide.pdf',
        'title': 'User Guide',
        'content_type': 'application/pdf',
        'file_size': '5.0 MB',
        'file_size_bytes': 5242880,
        'processing_status': 'completed',
        'processing_progress': 100,
        'chunks_count': 100,
        'view_count': 25,
        'download_count': 10,
        'collection_name': 'Guides',
        'collection_id': 'col-123',
        'icon': 'file-text',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T12:00:00Z',
        'processing_stage': 'complete',
        'processing_stage_description': 'Document ready',
        'embedded_chunks_count': 100,
        'has_tables': true,
        'has_images': true,
        'author': 'Jane Smith',
        'language': 'en',
        'version': 3,
        'last_accessed_at': '2025-01-15T14:00:00Z',
      };

      final doc = Document.fromJson(json);

      expect(doc.id, '123');
      expect(doc.filename, 'guide.pdf');
      expect(doc.title, 'User Guide');
      expect(doc.contentType, 'application/pdf');
      expect(doc.fileSize, '5.0 MB');
      expect(doc.fileSizeBytes, 5242880);
      expect(doc.processingStatus, 'completed');
      expect(doc.chunksCount, 100);
      expect(doc.viewCount, 25);
      expect(doc.hasTables, true);
      expect(doc.hasImages, true);
      expect(doc.author, 'Jane Smith');
    });

    test('fromJson handles minimal data', () {
      final json = {
        'id': 1,
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final doc = Document.fromJson(json);

      expect(doc.id, '1');
      expect(doc.filename, '');
      expect(doc.title, '');
      expect(doc.contentType, '');
      expect(doc.fileSize, '0 B');
      expect(doc.fileSizeBytes, 0);
      expect(doc.processingStatus, 'pending');
      expect(doc.processingProgress, 0);
      expect(doc.chunksCount, 0);
      expect(doc.collectionName, 'Unknown');
      expect(doc.icon, 'file');
    });

    test('fromJson uses filename as title if title is missing', () {
      final json = {
        'id': 1,
        'filename': 'important-doc.pdf',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final doc = Document.fromJson(json);

      expect(doc.title, 'important-doc.pdf');
    });

    test('fromJson parses tags', () {
      final json = {
        'id': 1,
        'filename': 'doc.pdf',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
        'tags': [
          {'id': 1, 'name': 'Important'},
          {'id': 2, 'name': 'Review'},
        ],
      };

      final doc = Document.fromJson(json);

      expect(doc.tags, isNotNull);
      expect(doc.tags!.length, 2);
      expect(doc.tags![0].name, 'Important');
      expect(doc.tags![1].name, 'Review');
    });

    test('fromJson parses subjects', () {
      final json = {
        'id': 1,
        'filename': 'doc.pdf',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
        'subjects': [
          {'id': 1, 'name': 'Marketing'},
          {'id': 2, 'name': 'Sales'},
        ],
      };

      final doc = Document.fromJson(json);

      expect(doc.subjects, isNotNull);
      expect(doc.subjects!.length, 2);
      expect(doc.subjects![0].name, 'Marketing');
    });

    group('status helpers', () {
      test('isProcessing returns true for pending status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
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
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.isProcessing, true);
        expect(doc.isReady, false);
        expect(doc.isFailed, false);
      });

      test('isProcessing returns true for processing status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'processing',
          processingProgress: 50,
          chunksCount: 0,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.isProcessing, true);
        expect(doc.isReady, false);
        expect(doc.isFailed, false);
      });

      test('isReady returns true for completed status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'completed',
          processingProgress: 100,
          chunksCount: 10,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.isProcessing, false);
        expect(doc.isReady, true);
        expect(doc.isFailed, false);
      });

      test('isReady returns true for ready status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'ready',
          processingProgress: 100,
          chunksCount: 10,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.isReady, true);
      });

      test('isFailed returns true for failed status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'failed',
          processingProgress: 30,
          chunksCount: 0,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.isProcessing, false);
        expect(doc.isReady, false);
        expect(doc.isFailed, true);
      });
    });

    group('statusLabel', () {
      test('returns Pending for pending status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
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
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.statusLabel, 'Pending');
      });

      test('returns Processing for processing status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'processing',
          processingProgress: 50,
          chunksCount: 0,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.statusLabel, 'Processing');
      });

      test('returns Ready for completed status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'completed',
          processingProgress: 100,
          chunksCount: 10,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.statusLabel, 'Ready');
      });

      test('returns Failed for failed status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'failed',
          processingProgress: 0,
          chunksCount: 0,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.statusLabel, 'Failed');
      });

      test('returns original status for unknown status', () {
        final doc = Document(
          id: '1',
          filename: 'doc.pdf',
          title: 'Doc',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: 'queued',
          processingProgress: 0,
          chunksCount: 0,
          viewCount: 0,
          downloadCount: 0,
          collectionName: 'Test',
          collectionId: '1',
          icon: 'file',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(doc.statusLabel, 'queued');
      });
    });
  });

  group('DocumentTag', () {
    test('creates with required values', () {
      final tag = DocumentTag(id: '1', name: 'Important');

      expect(tag.id, '1');
      expect(tag.name, 'Important');
    });

    test('fromJson parses data', () {
      final json = {'id': 123, 'name': 'Urgent'};
      final tag = DocumentTag.fromJson(json);

      expect(tag.id, '123');
      expect(tag.name, 'Urgent');
    });

    test('fromJson handles missing name', () {
      final json = {'id': 1};
      final tag = DocumentTag.fromJson(json);

      expect(tag.name, '');
    });
  });

  group('DocumentSubject', () {
    test('creates with required values', () {
      final subject = DocumentSubject(id: '1', name: 'Marketing');

      expect(subject.id, '1');
      expect(subject.name, 'Marketing');
    });

    test('fromJson parses data', () {
      final json = {'id': 456, 'name': 'Sales'};
      final subject = DocumentSubject.fromJson(json);

      expect(subject.id, '456');
      expect(subject.name, 'Sales');
    });

    test('fromJson handles missing name', () {
      final json = {'id': 1};
      final subject = DocumentSubject.fromJson(json);

      expect(subject.name, '');
    });
  });

  group('DocumentCollection', () {
    test('creates with required values', () {
      final created = DateTime(2025, 1, 1);
      final updated = DateTime(2025, 1, 15);

      final collection = DocumentCollection(
        id: '1',
        name: 'Marketing Docs',
        status: 'active',
        documentCount: 25,
        chunkCount: 500,
        createdAt: created,
        updatedAt: updated,
      );

      expect(collection.id, '1');
      expect(collection.name, 'Marketing Docs');
      expect(collection.status, 'active');
      expect(collection.documentCount, 25);
      expect(collection.chunkCount, 500);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'name': 'Legal Documents',
        'status': 'active',
        'document_count': 50,
        'chunk_count': 1000,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-15T12:00:00Z',
      };

      final collection = DocumentCollection.fromJson(json);

      expect(collection.id, '123');
      expect(collection.name, 'Legal Documents');
      expect(collection.status, 'active');
      expect(collection.documentCount, 50);
      expect(collection.chunkCount, 1000);
    });

    test('fromJson handles minimal data', () {
      final json = {
        'id': 1,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final collection = DocumentCollection.fromJson(json);

      expect(collection.name, 'Unknown');
      expect(collection.status, 'pending');
      expect(collection.documentCount, 0);
      expect(collection.chunkCount, 0);
    });
  });
}
