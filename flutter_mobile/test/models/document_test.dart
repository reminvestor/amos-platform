import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/document.dart';

void main() {
  group('Document', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'filename': 'report.pdf',
        'title': 'Annual Report 2024',
        'content_type': 'application/pdf',
        'file_size': '2.5 MB',
        'file_size_bytes': 2621440,
        'processing_status': 'completed',
        'processing_progress': 100,
        'chunks_count': 25,
        'view_count': 10,
        'download_count': 5,
        'collection_name': 'Reports',
        'collection_id': '123',
        'icon': 'file-text',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'processing_stage': 'complete',
        'processing_stage_description': 'Document fully processed',
        'embedded_chunks_count': 25,
        'tags': [
          {'id': '1', 'name': 'finance'},
          {'id': '2', 'name': 'annual'},
        ],
        'subjects': [
          {'id': '1', 'name': 'Financial Reports'},
        ],
        'has_tables': true,
        'has_images': false,
        'author': 'John Doe',
        'language': 'en',
        'version': 1,
        'last_accessed_at': '2024-01-17T08:00:00.000Z',
      };

      final doc = Document.fromJson(json);

      expect(doc.id, equals('1'));
      expect(doc.filename, equals('report.pdf'));
      expect(doc.title, equals('Annual Report 2024'));
      expect(doc.contentType, equals('application/pdf'));
      expect(doc.fileSize, equals('2.5 MB'));
      expect(doc.fileSizeBytes, equals(2621440));
      expect(doc.processingStatus, equals('completed'));
      expect(doc.processingProgress, equals(100));
      expect(doc.chunksCount, equals(25));
      expect(doc.viewCount, equals(10));
      expect(doc.downloadCount, equals(5));
      expect(doc.collectionName, equals('Reports'));
      expect(doc.collectionId, equals('123'));
      expect(doc.icon, equals('file-text'));
      expect(doc.processingStage, equals('complete'));
      expect(doc.processingStageDescription, equals('Document fully processed'));
      expect(doc.embeddedChunksCount, equals(25));
      expect(doc.tags, isNotNull);
      expect(doc.tags!.length, equals(2));
      expect(doc.tags![0].name, equals('finance'));
      expect(doc.subjects, isNotNull);
      expect(doc.subjects!.length, equals(1));
      expect(doc.hasTables, isTrue);
      expect(doc.hasImages, isFalse);
      expect(doc.author, equals('John Doe'));
      expect(doc.language, equals('en'));
      expect(doc.version, equals(1));
      expect(doc.lastAccessedAt, equals(DateTime.parse('2024-01-17T08:00:00.000Z')));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final doc = Document.fromJson(json);

      expect(doc.id, equals('123'));
      expect(doc.filename, equals(''));
      expect(doc.title, equals(''));
      expect(doc.contentType, equals(''));
      expect(doc.fileSize, equals('0 B'));
      expect(doc.fileSizeBytes, equals(0));
      expect(doc.processingStatus, equals('pending'));
      expect(doc.processingProgress, equals(0));
      expect(doc.chunksCount, equals(0));
      expect(doc.viewCount, equals(0));
      expect(doc.downloadCount, equals(0));
      expect(doc.collectionName, equals('Unknown'));
      expect(doc.icon, equals('file'));
    });

    test('fromJson uses filename as title when title is missing', () {
      final json = {
        'id': '123',
        'filename': 'document.pdf',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final doc = Document.fromJson(json);

      expect(doc.title, equals('document.pdf'));
    });

    test('isProcessing returns true for pending status', () {
      final doc = Document(
        id: '123',
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

      expect(doc.isProcessing, isTrue);
      expect(doc.isReady, isFalse);
      expect(doc.isFailed, isFalse);
    });

    test('isProcessing returns true for processing status', () {
      final doc = Document(
        id: '123',
        filename: 'test.pdf',
        title: 'Test',
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(doc.isProcessing, isTrue);
      expect(doc.isReady, isFalse);
      expect(doc.isFailed, isFalse);
    });

    test('isReady returns true for completed status', () {
      final doc = Document(
        id: '123',
        filename: 'test.pdf',
        title: 'Test',
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(doc.isProcessing, isFalse);
      expect(doc.isReady, isTrue);
      expect(doc.isFailed, isFalse);
    });

    test('isReady returns true for ready status', () {
      final doc = Document(
        id: '123',
        filename: 'test.pdf',
        title: 'Test',
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(doc.isProcessing, isFalse);
      expect(doc.isReady, isTrue);
      expect(doc.isFailed, isFalse);
    });

    test('isFailed returns true for failed status', () {
      final doc = Document(
        id: '123',
        filename: 'test.pdf',
        title: 'Test',
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(doc.isProcessing, isFalse);
      expect(doc.isReady, isFalse);
      expect(doc.isFailed, isTrue);
    });

    test('statusLabel returns correct labels', () {
      final testCases = {
        'pending': 'Pending',
        'processing': 'Processing',
        'completed': 'Ready',
        'ready': 'Ready',
        'failed': 'Failed',
        'unknown': 'unknown',
      };

      for (final entry in testCases.entries) {
        final doc = Document(
          id: '123',
          filename: 'test.pdf',
          title: 'Test',
          contentType: 'application/pdf',
          fileSize: '1 MB',
          fileSizeBytes: 1048576,
          processingStatus: entry.key,
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

        expect(doc.statusLabel, equals(entry.value),
            reason: 'Expected ${entry.key} to have label ${entry.value}');
      }
    });
  });

  group('DocumentTag', () {
    test('fromJson parses correctly', () {
      final json = {'id': 1, 'name': 'finance'};
      final tag = DocumentTag.fromJson(json);

      expect(tag.id, equals('1'));
      expect(tag.name, equals('finance'));
    });

    test('fromJson handles missing name', () {
      final json = {'id': '123'};
      final tag = DocumentTag.fromJson(json);

      expect(tag.id, equals('123'));
      expect(tag.name, equals(''));
    });
  });

  group('DocumentSubject', () {
    test('fromJson parses correctly', () {
      final json = {'id': 1, 'name': 'Financial Reports'};
      final subject = DocumentSubject.fromJson(json);

      expect(subject.id, equals('1'));
      expect(subject.name, equals('Financial Reports'));
    });

    test('fromJson handles missing name', () {
      final json = {'id': '123'};
      final subject = DocumentSubject.fromJson(json);

      expect(subject.id, equals('123'));
      expect(subject.name, equals(''));
    });
  });

  group('DocumentCollection', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Financial Reports',
        'status': 'active',
        'document_count': 25,
        'chunk_count': 500,
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final collection = DocumentCollection.fromJson(json);

      expect(collection.id, equals('1'));
      expect(collection.name, equals('Financial Reports'));
      expect(collection.status, equals('active'));
      expect(collection.documentCount, equals(25));
      expect(collection.chunkCount, equals(500));
    });

    test('fromJson handles missing fields with defaults', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final collection = DocumentCollection.fromJson(json);

      expect(collection.id, equals('123'));
      expect(collection.name, equals('Unknown'));
      expect(collection.status, equals('pending'));
      expect(collection.documentCount, equals(0));
      expect(collection.chunkCount, equals(0));
    });
  });
}
