import 'dart:typed_data';

class PrintItem {
  const PrintItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    this.discount = 0.0,
    this.modifiers = const [],
  });

  final String name;
  final int qty;
  final double unitPrice;
  final double lineTotal;
  final double discount;
  final List<String> modifiers;
}

class PrintReceiptData {
  const PrintReceiptData({
    required this.receiptId,
    required this.date,
    required this.time,
    required this.paymentMethod,
    required this.items,
    required this.total,
    this.queueNumber,
    this.collectionLabel,
    this.cashbackQrUrl,
    this.cashbackQrToken,
    this.cashReceived = 0.0,
    this.change = 0.0,
    this.subtotal = 0.0,
    this.discount = 0.0,
    this.deliveryFee = 0.0,
  });

  final String receiptId;
  final String? queueNumber;
  /// Overrides the printed collection number display (e.g. an alphanumeric
  /// delivery collection code) in place of [queueNumber].
  final String? collectionLabel;
  final String? cashbackQrUrl;
  final String? cashbackQrToken;
  final String date;
  final String time;
  final String paymentMethod;
  final List<PrintItem> items;
  final double total;
  final double cashReceived;
  final double change;
  final double subtotal;
  final double discount;
  final double deliveryFee;
}

class StoreConfig {
  const StoreConfig({
    required this.storeName,
    this.companyRegId = '',
    this.address = '',
    this.phone = '',
    this.header = '',
    this.footer = 'Thank you!',
    this.logoBytes,
    this.cashbackPercent = 10,
  });

  final String storeName;
  final String companyRegId;
  final String address;
  final String phone;
  // Printed above the item list (e.g. "Thank you for shopping with us!")
  final String header;
  // Printed at the very bottom of the receipt
  final String footer;
  final Uint8List? logoBytes;
  final int cashbackPercent;
}
