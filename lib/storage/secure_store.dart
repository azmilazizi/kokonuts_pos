import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  const SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'auth_token';
  static const String _staffIdKey = 'staff_id';
  static const String _staffNameKey = 'staff_name';
  static const String _activationEmailKey = 'activation_email';
  static const String _warehouseCodeKey = 'warehouse_code';
  static const String _warehouseIdKey = 'warehouse_id';
  static const String _warehouseNameKey = 'warehouse_name';
  static const String _queueNumberKey = 'queue_number';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<String?> readStaffId() {
    return _storage.read(key: _staffIdKey);
  }

  Future<String?> readStaffName() {
    return _storage.read(key: _staffNameKey);
  }

  Future<String?> readActivationEmail() {
    return _storage.read(key: _activationEmailKey);
  }

  Future<String?> readWarehouseCode() {
    return _storage.read(key: _warehouseCodeKey);
  }

  Future<String?> readWarehouseId() {
    return _storage.read(key: _warehouseIdKey);
  }

  Future<String?> readWarehouseName() {
    return _storage.read(key: _warehouseNameKey);
  }

  Future<int?> readQueueNumber() async {
    final v = await _storage.read(key: _queueNumberKey);
    return v != null ? int.tryParse(v) : null;
  }

  Future<void> writeQueueNumber(int number) {
    return _storage.write(key: _queueNumberKey, value: number.toString());
  }

  Future<int> nextQueueNumber() async {
    final stored = await readQueueNumber();
    final next = (stored == null || stored >= 399) ? 300 : stored + 1;
    await writeQueueNumber(next);
    return next;
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
    String? warehouseId,
    String? staffName,
    String? warehouseName,
  }) {
    return Future.wait([
      _storage.write(key: _activationEmailKey, value: email),
      _storage.write(key: _warehouseCodeKey, value: warehouseCode),
      if (warehouseId != null)
        _storage.write(key: _warehouseIdKey, value: warehouseId),
      if (staffName != null)
        _storage.write(key: _staffNameKey, value: staffName),
      if (warehouseName != null)
        _storage.write(key: _warehouseNameKey, value: warehouseName),
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
      _storage.delete(key: _warehouseIdKey),
      _storage.delete(key: _staffNameKey),
      _storage.delete(key: _warehouseNameKey),
    ]);
  }
}
