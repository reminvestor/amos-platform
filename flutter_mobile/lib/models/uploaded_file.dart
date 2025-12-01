/// Represents a file uploaded to the server
class UploadedFile {
  final String assetId;
  final String filename;
  final String contentType;
  final String? url;
  final String? assetType;
  final int? size;

  const UploadedFile({
    required this.assetId,
    required this.filename,
    required this.contentType,
    this.url,
    this.assetType,
    this.size,
  });

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      assetId: json['asset_id']?.toString() ?? json['document_id']?.toString() ?? '',
      filename: json['filename'] ?? json['name'] ?? 'Unknown',
      contentType: json['content_type'] ?? json['mime_type'] ?? 'application/octet-stream',
      url: json['url'],
      assetType: json['asset_type'],
      size: json['size'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'asset_id': assetId,
      'filename': filename,
      'content_type': contentType,
      if (url != null) 'url': url,
      if (assetType != null) 'asset_type': assetType,
    };
  }

  /// Get file extension from filename
  String get extension {
    final parts = filename.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Check if file is an image
  bool get isImage {
    return contentType.startsWith('image/') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(extension);
  }

  /// Check if file is a document
  bool get isDocument {
    return ['pdf', 'doc', 'docx', 'txt', 'md', 'rtf'].contains(extension) ||
        contentType.contains('pdf') ||
        contentType.contains('document');
  }

  /// Check if file is a spreadsheet
  bool get isSpreadsheet {
    return ['csv', 'xlsx', 'xls'].contains(extension) ||
        contentType.contains('spreadsheet') ||
        contentType.contains('csv');
  }

  /// Get a human-readable size string
  String get sizeString {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
