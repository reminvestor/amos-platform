import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/uploaded_file.dart';

void main() {
  group('UploadedFile', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'asset_id': 'asset-123',
        'filename': 'document.pdf',
        'content_type': 'application/pdf',
        'url': 'https://example.com/files/document.pdf',
        'asset_type': 'document',
        'size': 1024000,
      };

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals('asset-123'));
      expect(file.filename, equals('document.pdf'));
      expect(file.contentType, equals('application/pdf'));
      expect(file.url, equals('https://example.com/files/document.pdf'));
      expect(file.assetType, equals('document'));
      expect(file.size, equals(1024000));
    });

    test('fromJson handles document_id as fallback for asset_id', () {
      final json = {
        'document_id': 'doc-456',
        'filename': 'file.txt',
        'content_type': 'text/plain',
      };

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals('doc-456'));
    });

    test('fromJson handles name as fallback for filename', () {
      final json = {
        'asset_id': '123',
        'name': 'report.xlsx',
        'content_type': 'application/xlsx',
      };

      final file = UploadedFile.fromJson(json);

      expect(file.filename, equals('report.xlsx'));
    });

    test('fromJson handles mime_type as fallback for content_type', () {
      final json = {
        'asset_id': '123',
        'filename': 'image.png',
        'mime_type': 'image/png',
      };

      final file = UploadedFile.fromJson(json);

      expect(file.contentType, equals('image/png'));
    });

    test('fromJson handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals(''));
      expect(file.filename, equals('Unknown'));
      expect(file.contentType, equals('application/octet-stream'));
      expect(file.url, isNull);
      expect(file.assetType, isNull);
      expect(file.size, isNull);
    });

    test('toJson serializes correctly', () {
      const file = UploadedFile(
        assetId: 'asset-123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
        url: 'https://example.com/file.pdf',
        assetType: 'document',
        size: 5000,
      );

      final json = file.toJson();

      expect(json['asset_id'], equals('asset-123'));
      expect(json['filename'], equals('document.pdf'));
      expect(json['content_type'], equals('application/pdf'));
      expect(json['url'], equals('https://example.com/file.pdf'));
      expect(json['asset_type'], equals('document'));
    });

    test('toJson excludes null optional fields', () {
      const file = UploadedFile(
        assetId: 'asset-123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      final json = file.toJson();

      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('asset_type'), isFalse);
    });

    test('extension returns correct extension', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'document.PDF',
        contentType: 'application/pdf',
      );

      expect(file.extension, equals('pdf'));
    });

    test('extension returns empty string for files without extension', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'README',
        contentType: 'text/plain',
      );

      expect(file.extension, equals(''));
    });

    test('isImage returns true for image content type', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'photo.jpg',
        contentType: 'image/jpeg',
      );

      expect(file.isImage, isTrue);
      expect(file.isDocument, isFalse);
      expect(file.isSpreadsheet, isFalse);
    });

    test('isImage returns true for image extensions', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'photo.png',
        contentType: 'application/octet-stream',
      );

      expect(file.isImage, isTrue);
    });

    test('isDocument returns true for PDF content type', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'report.pdf',
        contentType: 'application/pdf',
      );

      expect(file.isDocument, isTrue);
      expect(file.isImage, isFalse);
      expect(file.isSpreadsheet, isFalse);
    });

    test('isDocument returns true for document extensions', () {
      const extensions = ['pdf', 'doc', 'docx', 'txt', 'md', 'rtf'];
      for (final ext in extensions) {
        final file = UploadedFile(
          assetId: '1',
          filename: 'file.$ext',
          contentType: 'application/octet-stream',
        );
        expect(file.isDocument, isTrue, reason: '$ext should be a document');
      }
    });

    test('isSpreadsheet returns true for CSV content type', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'data.csv',
        contentType: 'text/csv',
      );

      expect(file.isSpreadsheet, isTrue);
    });

    test('isSpreadsheet returns true for spreadsheet extensions', () {
      const extensions = ['csv', 'xlsx', 'xls'];
      for (final ext in extensions) {
        final file = UploadedFile(
          assetId: '1',
          filename: 'file.$ext',
          contentType: 'application/octet-stream',
        );
        expect(file.isSpreadsheet, isTrue, reason: '$ext should be a spreadsheet');
      }
    });

    test('sizeString returns empty for null size', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
      );

      expect(file.sizeString, equals(''));
    });

    test('sizeString returns bytes for small files', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 500,
      );

      expect(file.sizeString, equals('500 B'));
    });

    test('sizeString returns KB for medium files', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 5120, // 5 KB
      );

      expect(file.sizeString, equals('5.0 KB'));
    });

    test('sizeString returns MB for large files', () {
      const file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 5242880, // 5 MB
      );

      expect(file.sizeString, equals('5.0 MB'));
    });
  });
}
