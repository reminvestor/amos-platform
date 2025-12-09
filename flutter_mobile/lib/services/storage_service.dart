import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-platform storage service that works on both web and mobile
class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();

  StorageService._();

  // For mobile - secure storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    webOptions: WebOptions(
      dbName: 'amos_auth',
      publicKey: 'amos_public_key',
    ),
  );

  /// Read a value from storage
  Future<String?> read(String key) async {
    if (kIsWeb) {
      // On web, use SharedPreferences as fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key);
      } catch (e) {
        return null;
      }
    } else {
      return await _secureStorage.read(key: key);
    }
  }

  /// Write a value to storage
  Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  /// Delete a value from storage
  Future<void> delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  /// Clear all values
  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secureStorage.deleteAll();
    }
  }
}
