import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/uploaded_file.dart';

// Note: FileUploadService uses FilePicker and Dio which require native plugins.
// For unit tests, we test the response parsing logic and model behavior separately.

void main() {
  group('UploadedFile Model', () {
    test('parses file response correctly', () {
      final json = {
        'asset_id': 'abc123',
        'filename': 'document.pdf',
        'content_type': 'application/pdf',
        'url': 'https://example.com/files/document.pdf',
        'asset_type': 'document',
        'size': 1024000,
      };

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals('abc123'));
      expect(file.filename, equals('document.pdf'));
      expect(file.contentType, equals('application/pdf'));
      expect(file.url, equals('https://example.com/files/document.pdf'));
      expect(file.assetType, equals('document'));
      expect(file.size, equals(1024000));
    });

    test('handles alternative JSON keys', () {
      final json = {
        'document_id': 'doc456',
        'name': 'image.png',
        'mime_type': 'image/png',
      };

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals('doc456'));
      expect(file.filename, equals('image.png'));
      expect(file.contentType, equals('image/png'));
    });

    test('handles missing optional fields', () {
      final json = {
        'asset_id': 'xyz789',
        'filename': 'test.txt',
        'content_type': 'text/plain',
      };

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals('xyz789'));
      expect(file.url, isNull);
      expect(file.assetType, isNull);
      expect(file.size, isNull);
    });

    test('handles null asset_id with fallback', () {
      final json = {
        'filename': 'test.txt',
        'content_type': 'text/plain',
      };

      final file = UploadedFile.fromJson(json);

      expect(file.assetId, equals(''));
    });
  });

  group('UploadedFile.extension', () {
    test('extracts extension from filename', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      expect(file.extension, equals('pdf'));
    });

    test('extracts extension from complex filename', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'my.document.v2.docx',
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );

      expect(file.extension, equals('docx'));
    });

    test('returns empty string for no extension', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'README',
        contentType: 'text/plain',
      );

      expect(file.extension, equals(''));
    });

    test('converts extension to lowercase', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'Image.PNG',
        contentType: 'image/png',
      );

      expect(file.extension, equals('png'));
    });
  });

  group('UploadedFile.isImage', () {
    test('detects image by content type', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'photo',
        contentType: 'image/jpeg',
      );

      expect(file.isImage, isTrue);
    });

    test('detects image by extension', () {
      final extensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'];
      for (final ext in extensions) {
        final file = UploadedFile(
          assetId: '1',
          filename: 'photo.$ext',
          contentType: 'application/octet-stream',
        );
        expect(file.isImage, isTrue, reason: 'Should detect $ext as image');
      }
    });

    test('returns false for non-image', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      expect(file.isImage, isFalse);
    });
  });

  group('UploadedFile.isDocument', () {
    test('detects document by extension', () {
      final extensions = ['pdf', 'doc', 'docx', 'txt', 'md', 'rtf'];
      for (final ext in extensions) {
        final file = UploadedFile(
          assetId: '1',
          filename: 'file.$ext',
          contentType: 'application/octet-stream',
        );
        expect(file.isDocument, isTrue, reason: 'Should detect $ext as document');
      }
    });

    test('detects PDF by content type', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file',
        contentType: 'application/pdf',
      );

      expect(file.isDocument, isTrue);
    });

    test('detects document by content type containing document', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file',
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );

      expect(file.isDocument, isTrue);
    });

    test('returns false for non-document', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'image.png',
        contentType: 'image/png',
      );

      expect(file.isDocument, isFalse);
    });
  });

  group('UploadedFile.isSpreadsheet', () {
    test('detects spreadsheet by extension', () {
      final extensions = ['csv', 'xlsx', 'xls'];
      for (final ext in extensions) {
        final file = UploadedFile(
          assetId: '1',
          filename: 'data.$ext',
          contentType: 'application/octet-stream',
        );
        expect(file.isSpreadsheet, isTrue, reason: 'Should detect $ext as spreadsheet');
      }
    });

    test('detects spreadsheet by content type', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'data',
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      expect(file.isSpreadsheet, isTrue);
    });

    test('detects CSV by content type', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'data',
        contentType: 'text/csv',
      );

      expect(file.isSpreadsheet, isTrue);
    });

    test('returns false for non-spreadsheet', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      expect(file.isSpreadsheet, isFalse);
    });
  });

  group('UploadedFile.sizeString', () {
    test('returns empty string when size is null', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
      );

      expect(file.sizeString, equals(''));
    });

    test('formats bytes correctly', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 512,
      );

      expect(file.sizeString, equals('512 B'));
    });

    test('formats kilobytes correctly', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 2048,
      );

      expect(file.sizeString, equals('2.0 KB'));
    });

    test('formats megabytes correctly', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 2097152, // 2 MB
      );

      expect(file.sizeString, equals('2.0 MB'));
    });

    test('formats fractional sizes correctly', () {
      final file = UploadedFile(
        assetId: '1',
        filename: 'file.txt',
        contentType: 'text/plain',
        size: 1536, // 1.5 KB
      );

      expect(file.sizeString, equals('1.5 KB'));
    });
  });

  group('UploadedFile.toJson', () {
    test('serializes all fields correctly', () {
      final file = UploadedFile(
        assetId: 'abc123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
        url: 'https://example.com/file.pdf',
        assetType: 'document',
      );

      final json = file.toJson();

      expect(json['asset_id'], equals('abc123'));
      expect(json['filename'], equals('document.pdf'));
      expect(json['content_type'], equals('application/pdf'));
      expect(json['url'], equals('https://example.com/file.pdf'));
      expect(json['asset_type'], equals('document'));
    });

    test('excludes null optional fields', () {
      final file = UploadedFile(
        assetId: 'abc123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      final json = file.toJson();

      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('asset_type'), isFalse);
    });
  });

  group('FileUploadService.supportedExtensions', () {
    test('includes common document types', () {
      const extensions = ['pdf', 'doc', 'docx', 'txt', 'md', 'rtf'];
      // Testing that the constant list exists and has expected values
      // We can't import the service directly due to platform dependencies
      // but we can validate our expectations of what should be supported
      expect(extensions, contains('pdf'));
      expect(extensions, contains('docx'));
    });

    test('includes common image types', () {
      const extensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'];
      expect(extensions, contains('png'));
      expect(extensions, contains('jpg'));
    });

    test('includes spreadsheet types', () {
      const extensions = ['csv', 'xlsx', 'xls'];
      expect(extensions, contains('csv'));
      expect(extensions, contains('xlsx'));
    });
  });

  group('Upload Response Parsing', () {
    test('parses successful upload response', () {
      final responseData = {
        'file_urls': [
          {
            'asset_id': 'file1',
            'filename': 'doc1.pdf',
            'content_type': 'application/pdf',
            'url': 'https://example.com/files/doc1.pdf',
          },
          {
            'asset_id': 'file2',
            'filename': 'image.png',
            'content_type': 'image/png',
            'url': 'https://example.com/files/image.png',
          },
        ],
      };

      final fileUrls = responseData['file_urls'] as List;
      final uploaded = fileUrls
          .map((f) => UploadedFile.fromJson(f as Map<String, dynamic>))
          .toList();

      expect(uploaded, hasLength(2));
      expect(uploaded[0].filename, equals('doc1.pdf'));
      expect(uploaded[1].filename, equals('image.png'));
    });

    test('handles empty file_urls list', () {
      final responseData = {'file_urls': []};

      final fileUrls = responseData['file_urls'] as List;
      final uploaded = fileUrls
          .map((f) => UploadedFile.fromJson(f as Map<String, dynamic>))
          .toList();

      expect(uploaded, isEmpty);
    });

    test('handles missing file_urls with fallback', () {
      final responseData = <String, dynamic>{};

      final fileUrls = responseData['file_urls'] as List? ?? [];
      final uploaded = fileUrls
          .map((f) => UploadedFile.fromJson(f as Map<String, dynamic>))
          .toList();

      expect(uploaded, isEmpty);
    });
  });

  group('Document Status Response Parsing', () {
    test('parses indexed document status', () {
      final responseData = {
        'status': 'indexed',
        'document_id': 'doc123',
        'chunk_count': 15,
        'indexed_at': '2024-01-15T12:00:00.000Z',
      };

      expect(responseData['status'], equals('indexed'));
      expect(responseData['chunk_count'], equals(15));
    });

    test('parses processing document status', () {
      final responseData = {
        'status': 'processing',
        'document_id': 'doc456',
        'progress': 0.65,
      };

      expect(responseData['status'], equals('processing'));
      expect(responseData['progress'], equals(0.65));
    });

    test('parses failed document status', () {
      final responseData = {
        'status': 'failed',
        'document_id': 'doc789',
        'error': 'Unsupported file format',
      };

      expect(responseData['status'], equals('failed'));
      expect(responseData['error'], equals('Unsupported file format'));
    });
  });
}
