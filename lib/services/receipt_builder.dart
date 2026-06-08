import 'cashback_image_builder.dart';
import 'print_models.dart';
import 'receipt_commands.dart';

List<ReceiptCmd> buildReceipt(
  PrintReceiptData data,
  StoreConfig store,
) {
  final cashbackUrl = data.cashbackQrUrl;
  return [
    // ── Store header ──────────────────────────────────────────────────────────
    if (store.logoBytes != null)
      RcImage(store.logoBytes!, align: ReceiptAlign.center)
    else
      RcText(store.storeName, align: ReceiptAlign.center, bold: true, large: true),

    if (store.address.isNotEmpty)
      RcText(store.address, align: ReceiptAlign.center, bold: true, small: true),

    if (store.phone.isNotEmpty)
      RcText('Tel: ${store.phone}', align: ReceiptAlign.center, small: true),

    RcText(store.storeName, align: ReceiptAlign.center, small: true),

    if (store.companyRegId.isNotEmpty)
      RcText(store.companyRegId, align: ReceiptAlign.center, small: true),

    if (store.header.isNotEmpty) ...[
      const RcFeed(),
      RcText(store.header, align: ReceiptAlign.center),
    ],

    const RcFeed(),

    // ── Collection number ─────────────────────────────────────────────────────
    RcText('Your collection #:', align: ReceiptAlign.center),
    RcText(
      data.queueNumber != null ? '${data.queueNumber}' : data.receiptId,
      align: ReceiptAlign.center,
      bold: true,
      large: true,
    ),

    const RcDivider(),

    // ── Receipt details ───────────────────────────────────────────────────────
    RcText('Date: ${data.date}  ${data.time}'),
    RcText('Payment: ${data.paymentMethod}'),
    const RcDivider(),
    const RcItemRow(
      name: 'Item',
      price: 'Price',
      qty: 'Qty',
      discount: 'Disc',
      amount: 'Amount',
      isHeader: true,
    ),
    const RcDivider(),
    for (final item in data.items) ...[
      RcItemRow(
        name: item.name,
        price: item.unitPrice.toStringAsFixed(2),
        qty: '${item.qty}',
        discount: item.discount > 0 ? item.discount.toStringAsFixed(2) : '-',
        amount: 'RM${item.lineTotal.toStringAsFixed(2)}',
      ),
      for (final mod in item.modifiers) RcText('  $mod', small: true),
    ],
    const RcDivider(),
    RcRow('TOTAL', 'RM ${data.total.toStringAsFixed(2)}',
        bold: true, rightAlignLabel: true),
    const RcDivider(),
    if (data.cashReceived > 0) ...[
      RcRow('Cash', 'RM ${data.cashReceived.toStringAsFixed(2)}',
          rightAlignLabel: true),
      RcRow('Change', 'RM ${data.change.toStringAsFixed(2)}',
          bold: true, rightAlignLabel: true),
    ],

    // ── QR cashback ───────────────────────────────────────────────────────────
    if (cashbackUrl != null) ...[
      const RcFeed(),
      RcImage(buildCashbackImage(cashbackUrl, store.cashbackPercent)),
      RcText(
        'Redeem rewards on your next visit',
        align: ReceiptAlign.center,
        small: true,
      ),
    ],

    // ── Footer ────────────────────────────────────────────────────────────────
    const RcFeed(),
    RcText(store.footer, align: ReceiptAlign.center, bold: true),
    const RcFeed(2),
    const RcCut(),
  ];
}

List<ReceiptCmd> buildKitchenTicket({
  required int queueNumber,
  required String dateTime,
  required List<({String name, int qty, String modifiers})> items,
}) {
  return [
    RcText('KITCHEN ORDER', align: ReceiptAlign.center, bold: true, large: true),
    RcText(dateTime, align: ReceiptAlign.center, small: true),
    RcDivider(),
    RcText('Queue #$queueNumber', align: ReceiptAlign.center, bold: true, large: true),
    RcDivider(),
    for (final item in items) ...[
      RcRow('${item.qty}x  ${item.name}', '', bold: true),
      if (item.modifiers.isNotEmpty) RcText('    ${item.modifiers}', small: true),
    ],
    RcFeed(3),
    RcCut(),
  ];
}

List<ReceiptCmd> buildTestReceipt(StoreConfig store) {
  return [
    RcText(store.storeName, align: ReceiptAlign.center, bold: true, large: true),
    RcText('PRINTER TEST', align: ReceiptAlign.center),
    const RcDivider(),
    RcText('Connection: Bluetooth'),
    RcText('Status:     OK'),
    const RcDivider(),
    RcText('Printer is working correctly.', align: ReceiptAlign.center, bold: true),
    const RcFeed(2),
    const RcCut(),
  ];
}
