import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'bt_printer_service.dart';
import 'esc_pos_encoder.dart';
import 'print_models.dart';
import 'printer_config_service.dart';
import 'receipt_builder.dart';
import 'receipt_commands.dart';
import 'store_config_service.dart';

export 'print_models.dart';


class SunmiPrinterService {
  static final SunmiPrinterService _instance = SunmiPrinterService._();
  factory SunmiPrinterService() => _instance;
  SunmiPrinterService._();

  Future<void> printReceipt(PrintReceiptData data) async {
    try {
      await printReceiptOrThrow(data);
    } on PlatformException {
      // No-op on non-Sunmi hardware.
    } catch (_) {}
  }

  /// Same as [printReceipt] but propagates failures instead of swallowing
  /// them, so callers that need to know whether the print actually
  /// succeeded (e.g. delivery print jobs) can react accordingly.
  Future<void> printReceiptOrThrow(PrintReceiptData data) async {
    final store = await StoreConfigService().getConfig();
    final commands = buildReceipt(data, store);
    await _routeReceiptCommands(commands);
  }

  Future<void> printTestReceipt() async {
    try {
      final store = await StoreConfigService().getConfig();
      final commands = buildTestReceipt(store);
      await _routeReceiptCommands(commands);
    } on PlatformException {
      // No-op on non-Sunmi hardware.
    } catch (_) {}
  }

  // Routes receipt ESC/POS commands to the correct output based on the saved
  // receipt printer assignment:
  //   null or '__sunmi__'  → Sunmi built-in (backward-compatible fallback)
  //   XX:XX:XX:XX:XX:XX   → Bluetooth thermal printer
  //   anything else        → USB path; receipt printing not yet supported, skip
  Future<void> _routeReceiptCommands(List<ReceiptCmd> commands) async {
    final mac = await PrinterConfigService().getReceiptPrinterMac();
    if (mac == null || mac == PrinterConfigService.kSunmiKey) {
      await _printEscPos(commands);
      return;
    }
    if (_isBtMac(mac)) {
      await BtPrinterService().printCommands(mac, commands);
    }
    // USB receipt printing is not yet supported — skip silently.
  }

  static bool _isBtMac(String mac) =>
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(mac);

  Future<void> openCashDrawer() async {
    try {
      final mac = await PrinterConfigService().getReceiptPrinterMac();
      if (_isBtMac(mac ?? '')) {
        await BtPrinterService().openDrawer(mac!);
      }
    } on PlatformException {
      // No-op on non-Sunmi hardware.
    } catch (_) {}
  }

  Future<void> printKitchenTicket({
    required String queueNumber,
    required String dateTime,
    required List<({String name, int qty, String modifiers})> items,
  }) async {
    try {
      final commands = buildKitchenTicket(
        queueLabel: queueNumber,
        dateTime: dateTime,
        items: items,
      );
      await _printEscPos(commands);
    } on PlatformException {
      // No-op on non-Sunmi hardware.
    } catch (_) {}
  }

  // Encodes commands as raw ESC/POS bytes and sends them via the Sunmi
  // commandApi (sendEscCommand). This bypasses the lineApi entirely, so the
  // full paper width is used regardless of lineApi's internal defaults.
  Future<void> _printEscPos(List<ReceiptCmd> commands) async {
    final paperWidth = await PrinterConfigService().getSunmiPaperWidth();
    final lineWidth = paperWidth.lineWidth;
    // Encoding runs in a background isolate so that image pixel conversion
    // (decodeImage + copyResize + bitmap loop) never blocks the UI thread.
    final bytes = await Isolate.run(
      () => EscPosEncoder(lineWidth: lineWidth).encode(commands),
    );
    await SunmiPrinter.printEscPos(bytes.toList());
  }
}
