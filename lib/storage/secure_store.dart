import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  const SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'auth_token';
  static const String _staffIdKey = 'staff_id';
  static const String _activationEmailKey = 'activation_email';
  static const String _warehouseCodeKey = 'warehouse_code';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<String?> readStaffId() {
    return _storage.read(key: _staffIdKey);
  }

  Future<String?> readActivationEmail() {
    return _storage.read(key: _activationEmailKey);
  }

  Future<String?> readWarehouseCode() {
    return _storage.read(key: _warehouseCodeKey);
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

  Future<void> writeActivationDetails({
    required String email,
    required String warehouseCode,
  }) {
    return Future.wait([
      _storage.write(key: _activationEmailKey, value: email),
      _storage.write(key: _warehouseCodeKey, value: warehouseCode),
    ]);
  }

  Future<void> clearAuth() {
    return Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _staffIdKey),
    ]);
  }

  Future<void> clearActivation() {
    return Future.wait([
      _storage.delete(key: _activationEmailKey),
      _storage.delete(key: _warehouseCodeKey),
    ]);
  }
}
