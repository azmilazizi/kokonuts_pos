import '../api/api_client.dart';

/// Human-readable delivery platform name for a raw `source` value (e.g.
/// "GRABFOOD" → "GrabFood"), or '' if [source] is empty (walk-in order).
String deliverySourceLabel(String source) {
  switch (source.toUpperCase()) {
    case 'GRABFOOD':
      return 'GrabFood';
    case 'FOODPANDA':
      return 'foodpanda';
    case 'SHOPEEFOOD':
      return 'ShopeeFood';
    default:
      if (source.isEmpty) return '';
      return source[0].toUpperCase() + source.substring(1).toLowerCase();
  }
}

// ─── List model ──────────────────────────────────────────────────────────────

class ReceiptSummary {
  const ReceiptSummary({
    required this.id,
    required this.receiptNumber,
    required this.status,
    required this.receiptDate,
    required this.employeeName,
    required this.diningOption,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.totalMoney,
    required this.paymentMethod,
    required this.paymentType,
    this.source = '',
    this.queueNumber,
    this.shortOrderNumber,
  });

  final int id;
  final String receiptNumber;
  final String status;
  final DateTime receiptDate;
  final String employeeName;
  final String diningOption;
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double totalMoney;
  final String paymentMethod;
  final String paymentType;
  final String? queueNumber;
  final String? shortOrderNumber;
  /// Delivery platform origin (e.g. "GRABFOOD"), empty for walk-in orders.
  final String source;

  /// Human-readable delivery platform name for badges, or '' if not a
  /// delivery order.
  String get sourceLabel => deliverySourceLabel(source);

  String get formattedTotal => 'RM${totalMoney.toStringAsFixed(2)}';

  /// "Thursday, June 5, 2026" — used for date group headers
  String get dateGroup {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[receiptDate.weekday - 1]}, '
        '${months[receiptDate.month - 1]} ${receiptDate.day}, ${receiptDate.year}';
  }

  /// "10:30 AM"
  String get formattedTime {
    final h = receiptDate.hour % 12 == 0 ? 12 : receiptDate.hour % 12;
    final m = receiptDate.minute.toString().padLeft(2, '0');
    final ampm = receiptDate.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  /// "6/5/26 10:30 AM"
  String get shortDatetime =>
      '${receiptDate.month}/${receiptDate.day}/${receiptDate.year % 100} $formattedTime';

  static ReceiptSummary? fromJson(Map<String, dynamic> json) {
    final dateStr = json['receipt_date']?.toString() ?? '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return null;
    return ReceiptSummary(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      receiptNumber: json['receipt_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      receiptDate: date,
      employeeName: json['employee_name']?.toString() ?? '',
      diningOption: json['dining_option']?.toString() ?? '',
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '') ?? 0.0,
      totalDiscount:
          double.tryParse(json['total_discount']?.toString() ?? '') ?? 0.0,
      totalTax: double.tryParse(json['total_tax']?.toString() ?? '') ?? 0.0,
      totalMoney: double.tryParse(json['total_money']?.toString() ?? '') ?? 0.0,
      paymentMethod: json['payment_method']?.toString() ?? '',
      paymentType: json['payment_type']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      queueNumber: json['queue_number']?.toString(),
      shortOrderNumber: json['short_order_number']?.toString(),
    );
  }
}

// ─── Detail models ────────────────────────────────────────────────────────────

class ReceiptLineItem {
  const ReceiptLineItem({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.modifierNames,
    required this.modifiersPrice,
    required this.totalMoney,
  });

  final int id;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final List<String> modifierNames;
  final double modifiersPrice;
  final double totalMoney;

  static ReceiptLineItem fromJson(Map<String, dynamic> json) {
    final rawMods = json['modifier_names'];
    final mods = <String>[];
    if (rawMods is List) {
      for (final m in rawMods) {
        if (m != null) mods.add(m.toString());
      }
    }
    return ReceiptLineItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      itemName: json['item_name']?.toString() ?? '',
      quantity:
          double.tryParse(json['quantity']?.toString() ?? '') ?? 1.0,
      unitPrice:
          double.tryParse(json['unit_price']?.toString() ?? '') ?? 0.0,
      modifierNames: mods,
      modifiersPrice:
          double.tryParse(json['modifiers_price']?.toString() ?? '') ?? 0.0,
      totalMoney:
          double.tryParse(json['total_money']?.toString() ?? '') ?? 0.0,
    );
  }
}

class ReceiptPayment {
  const ReceiptPayment({
    required this.paymentName,
    required this.type,
    required this.moneyAmount,
    required this.cashBack,
  });

  final String paymentName;
  final String type;
  final double moneyAmount;
  final double cashBack;

  static ReceiptPayment fromJson(Map<String, dynamic> json) => ReceiptPayment(
        paymentName: json['payment_name']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        moneyAmount:
            double.tryParse(json['money_amount']?.toString() ?? '') ?? 0.0,
        cashBack:
            double.tryParse(json['cash_back']?.toString() ?? '') ?? 0.0,
      );
}

class ReceiptDetail {
  const ReceiptDetail({
    required this.id,
    required this.receiptNumber,
    required this.status,
    required this.lineItems,
    required this.payments,
    this.queueNumber,
    this.cashbackQrUrl,
    this.cashbackQrToken,
    this.subtotal = 0.0,
    this.totalDiscount = 0.0,
    this.deliveryFee = 0.0,
    this.grabfoodDeliveryFee = 0.0,
  });

  final int id;
  final String receiptNumber;
  final String status;
  final List<ReceiptLineItem> lineItems;
  final List<ReceiptPayment> payments;
  final String? queueNumber;
  final String? cashbackQrUrl;
  final String? cashbackQrToken;
  final double subtotal;
  final double totalDiscount;
  final double deliveryFee;
  final double grabfoodDeliveryFee;

  static ReceiptDetail? fromJson(Map<String, dynamic> json) {
    final rawItems = json['line_items'];
    final items = <ReceiptLineItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map<String, dynamic>) items.add(ReceiptLineItem.fromJson(e));
      }
    }
    final rawPayments = json['payments'];
    final payments = <ReceiptPayment>[];
    if (rawPayments is List) {
      for (final e in rawPayments) {
        if (e is Map<String, dynamic>) payments.add(ReceiptPayment.fromJson(e));
      }
    }
    return ReceiptDetail(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      receiptNumber: json['receipt_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      lineItems: items,
      payments: payments,
      queueNumber: json['queue_number']?.toString(),
      cashbackQrUrl: json['cashback_qr_url']?.toString(),
      cashbackQrToken: json['cashback_qr_token']?.toString(),
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '') ?? 0.0,
      totalDiscount: double.tryParse(json['total_discount']?.toString() ?? '') ?? 0.0,
      deliveryFee: double.tryParse(json['delivery_fee']?.toString() ?? '') ?? 0.0,
      grabfoodDeliveryFee: double.tryParse(
            ((json['grabfood_price'] as Map<String, dynamic>?)?['delivery_fee'])
                ?.toString() ??
                '') ??
          0.0,
    );
  }
}

// ─── Paginated response ───────────────────────────────────────────────────────

class ReceiptsPage {
  const ReceiptsPage({
    required this.total,
    required this.page,
    required this.pageCount,
    required this.limit,
    required this.items,
  });

  final int total;
  final int page;
  final int pageCount;
  final int limit;
  final List<ReceiptSummary> items;
}

// ─── Service ─────────────────────────────────────────────────────────────────

class ReceiptService {
  ReceiptService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<ReceiptsPage> fetchReceipts(
    String token, {
    int page = 1,
    int limit = 20,
    String? q,
    String? shiftId,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (q != null && q.isNotEmpty) 'q': q,
      if (shiftId != null && shiftId.isNotEmpty) 'shift_id': shiftId,
    };
    final response = await _client.getJson(
      '/pos/api/v1/receipts',
      queryParameters: params,
      authToken: token,
    );
    final outer = (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    final rawList = outer['data'];
    final summaries = <ReceiptSummary>[];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map<String, dynamic>) {
          final s = ReceiptSummary.fromJson(e);
          if (s != null) summaries.add(s);
        }
      }
    }
    return ReceiptsPage(
      total: _parseInt(outer['total']) ?? summaries.length,
      page: _parseInt(outer['page']) ?? page,
      pageCount: _parseInt(outer['page_count']) ?? 1,
      limit: _parseInt(outer['limit']) ?? limit,
      items: summaries,
    );
  }

  Future<ReceiptDetail?> fetchReceiptDetail(
      String token, String receiptNumber) async {
    final response = await _client.getJson(
      '/pos/api/v1/receipt/$receiptNumber',
      authToken: token,
    );
    final data =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    return ReceiptDetail.fromJson(data);
  }

  Future<void> refundReceipt(
    String token,
    int receiptId,
    double amount,
    List<({int lineItemId, int quantity})> items,
  ) async {
    await _client.postJson(
      '/pos/api/v1/receipts/$receiptId/refund',
      body: {
        'amount': amount,
        'items': items
            .map((e) => {'line_item_id': e.lineItemId, 'quantity': e.quantity})
            .toList(),
      },
      authToken: token,
    );
  }

  Future<void> cancelReceipt(String token, int receiptId) async {
    await _client.patchJson(
      '/pos/api/v1/receipts/$receiptId/cancel',
      authToken: token,
    );
  }

  static int? _parseInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '');
}
