import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/models/uploaded_file.dart';
import 'package:amos_mobile/utils/logger.dart';

class FileUploadService {
  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  FileUploadService() : _dio = Dio();

  /// Supported file extensions
  static const List<String> supportedExtensions = [
    // Documents
    'pdf', 'doc', 'docx', 'txt', 'md', 'rtf',
    // Images
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg',
    // Spreadsheets
    'csv', 'xlsx', 'xls',
  ];

  /// Pick files from device
  Future<List<PlatformFile>?> pickFiles({
    bool allowMultiple = true,
    List<String>? allowedExtensions,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        type: FileType.custom,
        allowedExtensions: allowedExtensions ?? supportedExtensions,
        withData: true, // For web support
      );

      return result?.files;
    } catch (e, stackTrace) {
      AppLogger.error('File picker error', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Upload files to server
  Future<List<UploadedFile>> uploadFiles(
    List<PlatformFile> files, {
    String storageType = 'long-term',
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final formData = FormData();

      for (var i = 0; i < files.length; i++) {
        final file = files[i];

        MultipartFile multipartFile;
        if (file.bytes != null) {
          // Web or bytes available
          multipartFile = MultipartFile.fromBytes(
            file.bytes!,
            filename: file.name,
          );
        } else if (file.path != null) {
          // Mobile with file path
          multipartFile = await MultipartFile.fromFile(
            file.path!,
            filename: file.name,
          );
        } else {
          AppLogger.warning('Skipping file without data: ${file.name}');
          continue;
        }

        formData.files.add(MapEntry('files[$i]', multipartFile));
      }

      formData.fields.add(MapEntry('storage_type', storageType));

      AppLogger.info('Uploading ${files.length} files...');

      final response = await _dio.post(
        '${Env.apiBaseUrl}/scout/upload_files',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
          contentType: 'multipart/form-data',
        ),
        onSendProgress: onProgress,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final fileUrls = response.data['file_urls'] as List? ?? [];
        final uploaded = fileUrls
            .map((f) => UploadedFile.fromJson(f as Map<String, dynamic>))
            .toList();

        AppLogger.info('Successfully uploaded ${uploaded.length} files');
        return uploaded;
      } else {
        throw Exception('Upload failed: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      AppLogger.error('File upload DioException', error: e);
      throw Exception('Upload failed: ${e.message}');
    } catch (e, stackTrace) {
      AppLogger.error('File upload error', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Check document indexing status (for RAG)
  Future<Map<String, dynamic>> checkDocumentStatus(String assetId) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await _dio.get(
        '${Env.apiBaseUrl}/scout/document-status/$assetId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error('Document status check error', error: e);
      return {'status': 'unknown', 'error': e.toString()};
    }
  }
}
