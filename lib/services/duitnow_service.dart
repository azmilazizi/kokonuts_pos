import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';

class DuitNowResult {
  const DuitNowResult({
    required this.purchaseId,
    required this.checkoutUrl,
    required this.qrUrl,
    required this.amount,
    required this.status,
  });

  final String purchaseId;
  final String checkoutUrl;
  final String qrUrl;
  final double amount;
  final String status;
}

class DuitNowStatusResult {
  const DuitNowStatusResult({
    required this.purchaseId,
    required this.status,
    this.paidAt,
  });

  final String purchaseId;
  final String status;
  final String? paidAt;

  bool get isPaid => status == 'paid';
}

class DuitNowService {
  DuitNowService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<DuitNowResult> createPayment({
    required String token,
    required double amount,
    required String reference,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/duitnow/create',
      authToken: token,
      body: {
        'amount': amount,
        'reference': reference,
      },
    );
    final data =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    return DuitNowResult(
      purchaseId: data['purchase_id'] as String,
      checkoutUrl: data['checkout_url'] as String,
      qrUrl: data['qr_url'] as String,
      amount: (data['amount'] as num).toDouble(),
      status: data['status'] as String,
    );
  }

  Future<DuitNowStatusResult> pollStatus({
    required String token,
    required String purchaseId,
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/duitnow/$purchaseId/status',
      authToken: token,
    );
    final data =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    return DuitNowStatusResult(
      purchaseId: data['purchase_id'] as String,
      status: data['status'] as String,
      paidAt: data['paid_at'] as String?,
    );
  }

  Future<Uint8List> fetchQrImage({
    required String token,
    required String purchaseId,
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/duitnow/$purchaseId/qr_image',
      authToken: token,
    );
    final data =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    final qrImage = data['qr_image'] as String;
    return base64Decode(qrImage.split(',').last);
  }

  Future<void> cancelPayment({
    required String token,
    required String purchaseId,
  }) async {
    await _client.postJson(
      '/pos/api/v1/duitnow/$purchaseId/cancel',
      authToken: token,
      body: {},
    );
  }
}
