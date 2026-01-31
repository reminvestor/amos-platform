import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:amos_mobile/services/api_client.dart';

/// Service for scanning business cards and extracting contact information
class BusinessCardScannerService {
  final ApiClient _api = ApiClient();
  final ImagePicker _picker = ImagePicker();

  /// Pick an image from camera
  Future<File?> pickFromCamera() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    return image != null ? File(image.path) : null;
  }

  /// Pick an image from gallery
  Future<File?> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    return image != null ? File(image.path) : null;
  }

  /// Scan a business card image and extract contact information
  /// Returns the extracted contact data without saving
  Future<BusinessCardResult> scanBusinessCard(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Determine mime type from file extension
      final extension = imageFile.path.split('.').last.toLowerCase();
      final mimeType = _getMimeType(extension);

      // ApiClient.post returns response.data directly, not the Response object
      final data = await _api.post(
        '/api/v1/vision/scan_business_card',
        data: {
          'image': base64Image,
          'mime_type': mimeType,
        },
      );

      if (data is Map && data['success'] == true) {
        return BusinessCardResult.success(
          ExtractedContact.fromJson(data['contact']),
        );
      } else if (data is Map) {
        return BusinessCardResult.error(
          data['error'] ?? 'Failed to extract contact information',
        );
      } else {
        return BusinessCardResult.error('Unexpected response format');
      }
    } catch (e) {
      return BusinessCardResult.error('Failed to scan business card: $e');
    }
  }

  /// Scan a business card and save the contact in one step
  Future<BusinessCardResult> scanAndSaveContact(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final extension = imageFile.path.split('.').last.toLowerCase();
      final mimeType = _getMimeType(extension);

      // ApiClient.post returns response.data directly, not the Response object
      final data = await _api.post(
        '/api/v1/vision/scan_business_card_and_save',
        data: {
          'image': base64Image,
          'mime_type': mimeType,
        },
      );

      if (data is Map && data['success'] == true) {
        return BusinessCardResult.success(
          ExtractedContact.fromJson(data['extracted_data']),
          savedContactId: data['contact']?['id'],
          message: data['message'],
        );
      } else if (data is Map) {
        return BusinessCardResult.error(
          data['error'] ?? 'Failed to save contact',
          extractedData: data['extracted_data'] != null
              ? ExtractedContact.fromJson(data['extracted_data'])
              : null,
        );
      } else {
        return BusinessCardResult.error('Unexpected response format');
      }
    } catch (e) {
      return BusinessCardResult.error('Failed to scan and save: $e');
    }
  }

  String _getMimeType(String extension) {
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

/// Result of a business card scan operation
class BusinessCardResult {
  final bool isSuccess;
  final ExtractedContact? contact;
  final String? error;
  final int? savedContactId;
  final String? message;

  BusinessCardResult._({
    required this.isSuccess,
    this.contact,
    this.error,
    this.savedContactId,
    this.message,
  });

  factory BusinessCardResult.success(
    ExtractedContact contact, {
    int? savedContactId,
    String? message,
  }) {
    return BusinessCardResult._(
      isSuccess: true,
      contact: contact,
      savedContactId: savedContactId,
      message: message,
    );
  }

  factory BusinessCardResult.error(String error, {ExtractedContact? extractedData}) {
    return BusinessCardResult._(
      isSuccess: false,
      error: error,
      contact: extractedData,
    );
  }
}

/// Contact information extracted from a business card
class ExtractedContact {
  final String? name;
  final String? firstName;
  final String? lastName;
  final String? title;
  final String? company;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? website;
  final String? address;
  final String? linkedin;
  final String? twitter;
  final String? notes;

  ExtractedContact({
    this.name,
    this.firstName,
    this.lastName,
    this.title,
    this.company,
    this.email,
    this.phone,
    this.mobile,
    this.website,
    this.address,
    this.linkedin,
    this.twitter,
    this.notes,
  });

  factory ExtractedContact.fromJson(Map<String, dynamic> json) {
    return ExtractedContact(
      name: json['name'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      title: json['title'] as String?,
      company: json['company'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      mobile: json['mobile'] as String?,
      website: json['website'] as String?,
      address: json['address'] as String?,
      linkedin: json['linkedin'] as String?,
      twitter: json['twitter'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Get the best available name
  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    if (name != null) return name!;
    if (firstName != null) return firstName!;
    if (lastName != null) return lastName!;
    return 'Unknown';
  }

  /// Get the best available phone number
  String? get bestPhone => phone ?? mobile;

  /// Check if we have enough data to create a contact
  bool get hasMinimumData => email != null || bestPhone != null;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'first_name': firstName,
      'last_name': lastName,
      'title': title,
      'company': company,
      'email': email,
      'phone': phone,
      'mobile': mobile,
      'website': website,
      'address': address,
      'linkedin': linkedin,
      'twitter': twitter,
      'notes': notes,
    };
  }
}
