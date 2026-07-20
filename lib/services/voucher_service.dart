import 'dart:convert';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/voucher.dart';

class VoucherValidationError implements Exception {
  const VoucherValidationError(this.message);
  final String message;

  @override
  String toString() => 'VoucherValidationError: $message';
}

class VoucherService {
  VoucherService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<VoucherDetails> validate({
    required String token,
    required String code,
    int? customerId,
    String? customerPhone,
    double transactionAmount = 0.0,
  }) async {
    try {
      final response = await _client.postJson(
        '/loyalty/api/pos/voucher/validate',
        authToken: token,
        body: {
          'code': code.trim().toUpperCase(),
          if (customerId != null) 'customer_id': customerId,
          if (customerPhone != null) 'customer_phone': customerPhone,
          'transaction_amount': transactionAmount,
        },
      );
      final data = <String, dynamic>{
        'code': code.trim().toUpperCase(),
        ...((response.data['data'] as Map<String, dynamic>?) ?? response.data),
      };
      final voucher = VoucherDetails.fromJson(data);
      if (voucher == null) {
        throw const VoucherValidationError('Unexpected response from server.');
      }
      return voucher;
    } on ApiException catch (e) {
      throw VoucherValidationError(_extractMessage(e.message));
    }
  }

  Future<void> redeem({
    required String token,
    required String code,
    required int receiptId,
    int? customerId,
    String? customerPhone,
  }) async {
    await _client.postJson(
      '/loyalty/api/pos/voucher/redeem',
      authToken: token,
      body: {
        'code': code,
        'transaction_id': receiptId,
        if (customerId != null) 'customer_id': customerId,
        if (customerPhone != null) 'customer_phone': customerPhone,
      },
    );
  }

  static String _extractMessage(String raw) {
    try {
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final msg = body['message'] ?? body['error'] ?? body['detail'];
      if (msg != null) return _humanize(msg.toString());
    } catch (_) {}
    return raw.isNotEmpty ? _humanize(raw) : 'Voucher validation failed.';
  }

  // Converts snake_case field names in API messages to readable words.
  // e.g. "customer_id is required" → "Customer is required"
  static String _humanize(String msg) {
    return msg.replaceAllMapped(
      RegExp(r'\b[a-z]+(?:_[a-z]+)+\b'),
      (m) {
        var words = m.group(0)!.split('_');
        if (words.last == 'id' && words.length > 1) {
          words = words.sublist(0, words.length - 1);
        }
        final phrase = words.join(' ');
        return phrase[0].toUpperCase() + phrase.substring(1);
      },
    );
  }
}
