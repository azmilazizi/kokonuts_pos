import '../api/api_client.dart';

class OrderResult {
  const OrderResult({
    required this.receiptId,
    required this.receiptNumber,
    required this.queueNumber,
    this.cashbackQrUrl,
    this.cashbackQrToken,
  });

  final int receiptId;
  final String receiptNumber;
  final String queueNumber;
  final String? cashbackQrUrl;
  final String? cashbackQrToken;
}

class OrderItemModifier {
  const OrderItemModifier({
    required this.id,
    required this.name,
    required this.price,
  });

  final String id;
  final String name;
  final double price;
}

class OrderItem {
  const OrderItem({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineDiscount,
    required this.modifiers,
  });

  final String itemId;
  final String name;
  final int qty;
  final double unitPrice;
  final double lineDiscount;
  final List<OrderItemModifier> modifiers;
}

class OrderService {
  OrderService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  static const _paymentTypeMap = <String, (int, String)>{
    'Cash': (1, 'Cash'),
    'Card': (2, 'Card'),
    'DuitNow QR': (3, 'DuitNow QR'),
  };

  static String _methodKey(String method) =>
      method.toLowerCase().replaceAll(' ', '_');

  Future<OrderResult> submitOrder({
    required String token,
    required int shiftId,
    required int employeeId,
    int? customerId,
    required String paymentMethod,
    required double subtotal,
    required double billDiscount,
    required double cashbackRedeemed,
    required double total,
    required double cashReceived,
    required double change,
    required List<OrderItem> items,
    required String queueNumber,
  }) async {
    final (typeId, typeName) =
        _paymentTypeMap[paymentMethod] ?? (1, paymentMethod);

    final response = await _client.postJson(
      '/pos/api/v1/orders',
      authToken: token,
      body: {
        'shift_id': shiftId,
        'employee_id': employeeId,
        'customer_id': customerId,
        'dining_option': 'Dine in',
        'note': null,
        'subtotal': subtotal,
        'bill_discount': billDiscount,
        'total_tax': 0.0,
        'tip': 0.0,
        'surcharge': 0.0,
        'total': total,
        'payment_method': _methodKey(paymentMethod),
        'payment_type_id': typeId,
        'payment_name': typeName,
        'cash_received': cashReceived,
        'change': change,
        'cashback_redeemed': cashbackRedeemed,
        'queue_number': queueNumber,
        'items': items
            .map(
              (item) => {
                'item_id': int.tryParse(item.itemId) ?? 0,
                'name': item.name,
                'variant_id': null,
                'variant_name': null,
                'qty': item.qty,
                'unit_price': item.unitPrice,
                'line_discount': item.lineDiscount,
                'total_tax': 0.0,
                'tax_ids': <int>[],
                'modifiers': item.modifiers
                    .map(
                      (m) => {
                        'id': int.tryParse(m.id) ?? 0,
                        'name': m.name,
                        'price': m.price,
                      },
                    )
                    .toList(),
                'line_note': null,
              },
            )
            .toList(),
      },
    );

    final data =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    final rawId = data['receipt_id'];
    return OrderResult(
      receiptId: rawId is int
          ? rawId
          : int.tryParse(rawId?.toString() ?? '') ?? 0,
      receiptNumber: data['receipt_number']?.toString() ?? '',
      queueNumber: queueNumber,
      cashbackQrUrl: data['cashback_qr_url']?.toString(),
      cashbackQrToken: data['cashback_qr_token']?.toString(),
    );
  }

  Future<double> redeemCashback({
    required String token,
    required int customerId,
    required int receiptId,
    required double amount,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/customers/$customerId/cashback/redeem',
      authToken: token,
      body: {'receipt_id': receiptId, 'amount': amount},
    );
    final data =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    return double.tryParse(data['points_balance']?.toString() ?? '') ?? 0.0;
  }
}
