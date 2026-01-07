class Document {
  final String id;
  final String filename;
  final String title;
  final String contentType;
  final String fileSize;
  final int fileSizeBytes;
  final String processingStatus;
  final int processingProgress;
  final int chunksCount;
  final int viewCount;
  final int downloadCount;
  final String collectionName;
  final String collectionId;
  final String icon;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Detailed fields
  final String? processingStage;
  final String? processingStageDescription;
  final int? embeddedChunksCount;
  final List<DocumentTag>? tags;
  final List<DocumentSubject>? subjects;
  final bool? hasTables;
  final bool? hasImages;
  final String? author;
  final String? language;
  final int? version;
  final DateTime? lastAccessedAt;

  Document({
    required this.id,
    required this.filename,
    required this.title,
    required this.contentType,
    required this.fileSize,
    required this.fileSizeBytes,
    required this.processingStatus,
    required this.processingProgress,
    required this.chunksCount,
    required this.viewCount,
    required this.downloadCount,
    required this.collectionName,
    required this.collectionId,
    required this.icon,
    required this.createdAt,
    required this.updatedAt,
    this.processingStage,
    this.processingStageDescription,
    this.embeddedChunksCount,
    this.tags,
    this.subjects,
    this.hasTables,
    this.hasImages,
    this.author,
    this.language,
    this.version,
    this.lastAccessedAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'].toString(),
      filename: json['filename'] ?? '',
      title: json['title'] ?? json['filename'] ?? '',
      contentType: json['content_type'] ?? '',
      fileSize: json['file_size'] ?? '0 B',
      fileSizeBytes: json['file_size_bytes'] ?? 0,
      processingStatus: json['processing_status'] ?? 'pending',
      processingProgress: json['processing_progress'] ?? 0,
      chunksCount: json['chunks_count'] ?? 0,
      viewCount: json['view_count'] ?? 0,
      downloadCount: json['download_count'] ?? 0,
      collectionName: json['collection_name'] ?? 'Unknown',
      collectionId: json['collection_id']?.toString() ?? '',
      icon: json['icon'] ?? 'file',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      processingStage: json['processing_stage'],
      processingStageDescription: json['processing_stage_description'],
      embeddedChunksCount: json['embedded_chunks_count'],
      tags: json['tags'] != null
          ? (json['tags'] as List).map((t) => DocumentTag.fromJson(t)).toList()
          : null,
      subjects: json['subjects'] != null
          ? (json['subjects'] as List).map((s) => DocumentSubject.fromJson(s)).toList()
          : null,
      hasTables: json['has_tables'],
      hasImages: json['has_images'],
      author: json['author'],
      language: json['language'],
      version: json['version'],
      lastAccessedAt: json['last_accessed_at'] != null
          ? DateTime.parse(json['last_accessed_at'])
          : null,
    );
  }

  bool get isProcessing => processingStatus == 'pending' || processingStatus == 'processing';
  bool get isReady => processingStatus == 'completed' || processingStatus == 'ready';
  bool get isFailed => processingStatus == 'failed';

  String get statusLabel {
    switch (processingStatus) {
      case 'pending':
        return 'Pending';
      case 'processing':
        return 'Processing';
      case 'completed':
      case 'ready':
        return 'Ready';
      case 'failed':
        return 'Failed';
      default:
        return processingStatus;
    }
  }
}

class DocumentTag {
  final String id;
  final String name;

  DocumentTag({required this.id, required this.name});

  factory DocumentTag.fromJson(Map<String, dynamic> json) {
    return DocumentTag(
      id: json['id'].toString(),
      name: json['name'] ?? '',
    );
  }
}

class DocumentSubject {
  final String id;
  final String name;

  DocumentSubject({required this.id, required this.name});

  factory DocumentSubject.fromJson(Map<String, dynamic> json) {
    return DocumentSubject(
      id: json['id'].toString(),
      name: json['name'] ?? '',
    );
  }
}

class DocumentCollection {
  final String id;
  final String name;
  final String status;
  final int documentCount;
  final int chunkCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentCollection({
    required this.id,
    required this.name,
    required this.status,
    required this.documentCount,
    required this.chunkCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentCollection.fromJson(Map<String, dynamic> json) {
    return DocumentCollection(
      id: json['id'].toString(),
      name: json['name'] ?? 'Unknown',
      status: json['status'] ?? 'pending',
      documentCount: json['document_count'] ?? 0,
      chunkCount: json['chunk_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
