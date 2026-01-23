import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/widgets/file_attachment_chip.dart';
import 'package:amos_mobile/models/uploaded_file.dart';
import 'package:amos_mobile/config/theme.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );
  }

  group('FileAttachmentChip', () {
    testWidgets('displays filename', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file),
      ));

      expect(find.text('document.pdf'), findsOneWidget);
    });

    testWidgets('displays file size when available', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
        size: 5120, // 5 KB
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file),
      ));

      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('(5.0 KB)'), findsOneWidget);
    });

    testWidgets('does not display size when null', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'document.pdf',
        contentType: 'application/pdf',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file),
      ));

      // Size string should not be displayed
      expect(find.textContaining('KB'), findsNothing);
      expect(find.textContaining('MB'), findsNothing);
      expect(find.textContaining('B'), findsNothing);
    });

    testWidgets('shows remove button when showRemove is true and onRemove provided', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'file.txt',
        contentType: 'text/plain',
      );

      await tester.pumpWidget(createTestWidget(
        FileAttachmentChip(
          file: file,
          showRemove: true,
          onRemove: () {},
        ),
      ));

      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('hides remove button when showRemove is false', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'file.txt',
        contentType: 'text/plain',
      );

      await tester.pumpWidget(createTestWidget(
        FileAttachmentChip(
          file: file,
          showRemove: false,
          onRemove: () {},
        ),
      ));

      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('hides remove button when onRemove is null', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'file.txt',
        contentType: 'text/plain',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file, showRemove: true),
      ));

      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('calls onRemove when remove button tapped', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'file.txt',
        contentType: 'text/plain',
      );

      bool removed = false;

      await tester.pumpWidget(createTestWidget(
        FileAttachmentChip(
          file: file,
          showRemove: true,
          onRemove: () => removed = true,
        ),
      ));

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();

      expect(removed, isTrue);
    });

    testWidgets('shows image icon for image files', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'photo.jpg',
        contentType: 'image/jpeg',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file, showRemove: false),
      ));

      expect(find.byIcon(LucideIcons.image), findsOneWidget);
    });

    testWidgets('shows document icon for PDF files', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'report.pdf',
        contentType: 'application/pdf',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file, showRemove: false),
      ));

      expect(find.byIcon(LucideIcons.fileText), findsOneWidget);
    });

    testWidgets('shows spreadsheet icon for CSV files', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'data.csv',
        contentType: 'text/csv',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file, showRemove: false),
      ));

      expect(find.byIcon(LucideIcons.sheet), findsOneWidget);
    });

    testWidgets('shows generic file icon for unknown types', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'archive.zip',
        contentType: 'application/zip',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file, showRemove: false),
      ));

      expect(find.byIcon(LucideIcons.file), findsOneWidget);
    });

    testWidgets('truncates long filenames', (tester) async {
      const file = UploadedFile(
        assetId: '123',
        filename: 'this_is_a_very_long_filename_that_should_be_truncated.pdf',
        contentType: 'application/pdf',
      );

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentChip(file: file, showRemove: false),
      ));

      // The text should be present (even if truncated)
      expect(find.textContaining('this_is'), findsOneWidget);
    });
  });

  group('FileAttachmentList', () {
    testWidgets('renders empty when no files', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const FileAttachmentList(files: []),
      ));

      expect(find.byType(FileAttachmentChip), findsNothing);
    });

    testWidgets('renders chips for each file', (tester) async {
      const files = [
        UploadedFile(assetId: '1', filename: 'file1.pdf', contentType: 'application/pdf'),
        UploadedFile(assetId: '2', filename: 'file2.jpg', contentType: 'image/jpeg'),
        UploadedFile(assetId: '3', filename: 'file3.csv', contentType: 'text/csv'),
      ];

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentList(files: files),
      ));

      expect(find.byType(FileAttachmentChip), findsNWidgets(3));
      expect(find.text('file1.pdf'), findsOneWidget);
      expect(find.text('file2.jpg'), findsOneWidget);
      expect(find.text('file3.csv'), findsOneWidget);
    });

    testWidgets('calls onRemove with correct assetId', (tester) async {
      const files = [
        UploadedFile(assetId: 'asset-123', filename: 'file1.pdf', contentType: 'application/pdf'),
      ];

      String? removedId;

      await tester.pumpWidget(createTestWidget(
        FileAttachmentList(
          files: files,
          onRemove: (id) => removedId = id,
        ),
      ));

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();

      expect(removedId, equals('asset-123'));
    });

    testWidgets('hides remove buttons when onRemove is null', (tester) async {
      const files = [
        UploadedFile(assetId: '1', filename: 'file1.pdf', contentType: 'application/pdf'),
        UploadedFile(assetId: '2', filename: 'file2.jpg', contentType: 'image/jpeg'),
      ];

      await tester.pumpWidget(createTestWidget(
        const FileAttachmentList(files: files),
      ));

      expect(find.byIcon(LucideIcons.x), findsNothing);
    });
  });
}
