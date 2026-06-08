import '../api/api_client.dart';

class PaymentMode {
  const PaymentMode({required this.id, required this.name});

  final String id;
  final String name;

  bool get isCash => name.toLowerCase() == 'cash';

  static PaymentMode? fromJson(Map<String, dynamic> json) {
    if (json['active']?.toString() != '1') return null;
    final name = json['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    return PaymentMode(
      id: json['id']?.toString() ?? '',
      name: name,
    );
  }
}

class PaymentModeService {
  PaymentModeService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<PaymentMode>> fetchPaymentModes(String token) async {
    final response = await _client.getJson(
      '/pos/api/v1/payment_modes',
      authToken: token,
    );
    final raw = response.data['data'];
    final modes = <PaymentMode>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          final m = PaymentMode.fromJson(e);
          if (m != null) modes.add(m);
        }
      }
    }
    return modes;
  }
}
