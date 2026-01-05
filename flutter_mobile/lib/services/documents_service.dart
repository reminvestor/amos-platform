import 'package:dio/dio.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/models/document.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class DocumentsService {
  final ApiClient _api = ApiClient();

  /// Fetch all documents with optional filtering
  Future<List<Document>> getDocuments({
    String? search,
    String? contentType,
    String? status,
    int page = 1,
  }) async {
    try {
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

      final response = await _api.get('/api/v1/documents', queryParameters: queryParams);
      final documentsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${documentsList.length} documents');
      return documentsList.map((json) => Document.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load documents', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single document details
  Future<Document> getDocument(String id) async {
    try {
      final response = await _api.get('/api/v1/documents/$id');
      return Document.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load document $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch document collections (RAG stores)
  Future<List<DocumentCollection>> getCollections() async {
    try {
      final response = await _api.get('/api/v1/documents/collections');
      final collectionsList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${collectionsList.length} document collections');
      return collectionsList.map((json) => DocumentCollection.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load document collections', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get document processing status
  Future<Map<String, dynamic>> getDocumentStatus(String id) async {
    try {
      final response = await _api.get('/api/v1/documents/$id/status');
      return response as Map<String, dynamic>;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get document status $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a document
  Future<void> deleteDocument(String id) async {
    try {
      await _api.delete('/api/v1/documents/$id');
      AppLogger.info('Deleted document $id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete document $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Upload a document file
  Future<Document> uploadDocument(String filePath, String fileName) async {
    try {
      // Get auth token
      final token = await ApiClient.instance.getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      // Create form data with file
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      // Make request with custom Dio for file upload
      final dio = Dio();
      final response = await dio.post(
        '${Env.apiBaseUrl}/api/v1/documents',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      if (response.data['success'] == true && response.data['document'] != null) {
        AppLogger.info('Uploaded document: $fileName');
        return Document.fromJson(response.data['document']);
      } else {
        throw Exception(response.data['error'] ?? 'Upload failed');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to upload document', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
