import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  const SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'auth_token';
  static const String _staffIdKey = 'staff_id';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<String?> readStaffId() {
    return _storage.read(key: _staffIdKey);
  }

  Future<void> writeAuth({
    required String token,
    required String staffId,
  }) {
    return Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _staffIdKey, value: staffId),
    ]);
  }

  Future<void> clearAuth() {
    return Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _staffIdKey),
    ]);
  }
}
