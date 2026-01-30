import 'dart:convert';
import 'dart:io';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/screens/scanner/scanner_screen.dart';
import 'package:amos_mobile/utils/exceptions.dart';

/// Unified scanner service for all scan modes
class ScannerService {
  final ApiClient _api = ApiClient();

  /// Scan an image based on the selected mode
  Future<ScanResult> scan(File imageFile, ScanMode mode) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = _getMimeType(imageFile.path);

      // ApiClient.post returns response.data directly, not the Response object
      final data = await _api.post(
        '/api/v1/vision/scan',
        data: {
          'image': base64Image,
          'mime_type': mimeType,
          'mode': mode.name,
        },
      );

      if (data is Map && data['success'] == true) {
        return ScanResult.success(
          mode: mode,
          extractedFields: Map<String, dynamic>.from(data['data'] ?? {}),
        );
      } else if (data is Map) {
        return ScanResult.error(_extractErrorMessage(data));
      } else {
        return ScanResult.error('Unexpected response format');
      }
    } on AppException catch (e) {
      // ApiClient throws AppException (not DioException) for errors
      return ScanResult.error(e.message);
    } catch (e) {
      return ScanResult.error('Failed to scan: $e');
    }
  }

  /// Extract user-friendly error message from API response
  String _extractErrorMessage(dynamic data) {
    if (data is Map) {
      // Prefer 'message' over 'error' for user-friendly messages
      final message = data['message'] as String?;
      final error = data['error'] as String?;

      if (message != null && message.isNotEmpty) {
        return message;
      }
      if (error != null && error.isNotEmpty && error != 'no_entity') {
        return error;
      }
    }
    return 'An error occurred';
  }

  /// Save the scan result based on mode
  Future<ScanResult> saveResult(
    File imageFile,
    ScanMode mode,
    ScanResult scanResult,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = _getMimeType(imageFile.path);

      // ApiClient.post returns response.data directly, not the Response object
      final data = await _api.post(
        '/api/v1/vision/scan_and_save',
        data: {
          'image': base64Image,
          'mime_type': mimeType,
          'mode': mode.name,
          'extracted_data': scanResult.extractedFields,
        },
      );

      if (data is Map && data['success'] == true) {
        return ScanResult.success(
          mode: mode,
          extractedFields: scanResult.extractedFields,
          savedId: data['id'],
          message: data['message'] ?? 'Saved successfully!',
        );
      } else if (data is Map) {
        return ScanResult.error(_extractErrorMessage(data));
      } else {
        return ScanResult.error('Unexpected response format');
      }
    } on AppException catch (e) {
      // ApiClient throws AppException (not DioException) for errors
      return ScanResult.error(e.message);
    } catch (e) {
      return ScanResult.error('Failed to save: $e');
    }
  }

  String _getMimeType(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

/// Result of a scan operation
class ScanResult {
  final bool isSuccess;
  final ScanMode? mode;
  final Map<String, dynamic> extractedFields;
  final String? error;
  final int? savedId;
  final String? message;

  ScanResult._({
    required this.isSuccess,
    this.mode,
    this.extractedFields = const {},
    this.error,
    this.savedId,
    this.message,
  });

  factory ScanResult.success({
    required ScanMode mode,
    required Map<String, dynamic> extractedFields,
    int? savedId,
    String? message,
  }) {
    return ScanResult._(
      isSuccess: true,
      mode: mode,
      extractedFields: extractedFields,
      savedId: savedId,
      message: message,
    );
  }

  factory ScanResult.error(String error) {
    return ScanResult._(
      isSuccess: false,
      error: error,
    );
  }
}
