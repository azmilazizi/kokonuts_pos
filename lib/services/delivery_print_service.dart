import 'bt_printer_service.dart';
import 'label_printer_service.dart';
import 'print_job_service.dart';
import 'printer_config_service.dart';
import 'receipt_builder.dart';
import 'receipt_service.dart';
import 'sunmi_printer_service.dart';

class DeliveryPrintResult {
  const DeliveryPrintResult({required this.kitchenOk, this.kitchenError});

  final bool kitchenOk;
  final String? kitchenError;
}

/// Headless print orchestration for delivery-platform print jobs — mirrors
/// the dine-in receipt + kitchen print pipeline (see
/// `pos_register.dart:_printLabels` and `main.dart:_sendToKitchen`) but
/// operates on a [PrintJob]'s embedded receipt instead of the live cart, so
/// it can run from a background poller with no BuildContext.
class DeliveryPrintService {
  Future<DeliveryPrintResult> printJob(PrintJob job) async {
    final detail = job.detail;

    await SunmiPrinterService().printReceiptOrThrow(
      PrintReceiptData(
        receiptId: job.receiptNumber,
        collectionLabel: job.printCollectionNumber,
        date: job.dateLabel,
        time: job.timeLabel,
        paymentMethod: job.paymentMethodLabel,
        items: detail.lineItems
            .map((item) => PrintItem(
                  name: item.itemName,
                  qty: item.quantity.round(),
                  unitPrice: item.unitPrice,
                  lineTotal: item.totalMoney,
                  discount: ((item.unitPrice * item.quantity) -
                          item.totalMoney)
                      .clamp(0.0, double.infinity),
                  modifiers: item.modifierNames,
                ))
            .toList(),
        total: job.totalMoney,
        subtotal: detail.subtotal,
        discount: detail.totalDiscount,
        deliveryFee: detail.deliveryFee + detail.grabfoodDeliveryFee,
        cashReceived: job.totalMoney,
        change: 0.0,
      ),
    );

    return _printKitchenTicket(job, detail.lineItems);
  }

  Future<DeliveryPrintResult> _printKitchenTicket(
    PrintJob job,
    List<ReceiptLineItem> lineItems,
  ) async {
    try {
      final kitchenMac = await PrinterConfigService().getKitchenPrinterMac();
      if (kitchenMac == null || kitchenMac.isEmpty) {
        return const DeliveryPrintResult(kitchenOk: true);
      }

      final now = job.createdAt;
      final dt =
          '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      if (_isBtMac(kitchenMac)) {
        final commands = buildKitchenTicket(
          queueLabel: job.printCollectionNumber,
          dateTime: dt,
          items: lineItems
              .map((item) => (
                    name: item.itemName,
                    qty: item.quantity.round(),
                    modifiers: item.modifierNames.join(', '),
                  ))
              .toList(),
        );
        await BtPrinterService().printCommands(kitchenMac, commands);
        return const DeliveryPrintResult(kitchenOk: true);
      }

      final printer = createLabelPrinterService();
      await printer.connect();
      try {
        final totalItems = lineItems.length;
        for (var i = 0; i < lineItems.length; i++) {
          final item = lineItems[i];
          final labelJob = LabelPrintJob(
            queueNumber: job.printCollectionNumber,
            itemName: item.itemName,
            category: '',
            modifier: item.modifierNames.join('\n'),
            dateTime: dt,
            itemIndex: i + 1,
            totalItems: totalItems,
          );
          final qty = item.quantity.round();
          for (var copy = 0; copy < qty; copy++) {
            await printer.printLabel(labelJob);
          }
        }
      } finally {
        await printer.disconnect();
      }
      return const DeliveryPrintResult(kitchenOk: true);
    } catch (e) {
      return DeliveryPrintResult(kitchenOk: false, kitchenError: e.toString());
    }
  }

  static bool _isBtMac(String mac) =>
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(mac);
}
