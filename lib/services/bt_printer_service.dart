import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'esc_pos_encoder.dart';
import 'printer_config_service.dart';
import 'receipt_builder.dart';
import 'receipt_commands.dart';
import 'store_config_service.dart';

class BtPrinterService {
  static const _ch = MethodChannel('kokonuts/bt_printer');
  static Future<void> _queue = Future.value();

  // A stalled RFCOMM connect()/write() on the native side can otherwise hang
  // this call forever, wedging the payment screen and every print job queued
  // behind it. Bound the wait so a dead/out-of-range printer fails fast.
  static const _sendTimeout = Duration(seconds: 12);

  Future<void> printCommands(
    String macAddress,
    List<ReceiptCmd> commands,
  ) async {
    final lineWidth = (await _encoderFor(macAddress)).lineWidth;
    final bytes = await Isolate.run(
      () => EscPosEncoder(lineWidth: lineWidth).encode(commands),
    );
    await _send(macAddress, bytes);
  }

  Future<void> printTest(String macAddress, {PaperWidth? paperWidth}) async {
    final store = await StoreConfigService().getConfig();
    final lineWidth = paperWidth != null
        ? paperWidth.lineWidth
        : (await _encoderFor(macAddress)).lineWidth;
    final commands = buildTestReceipt(store);
    final bytes = await Isolate.run(
      () => EscPosEncoder(lineWidth: lineWidth).encode(commands),
    );
    await _send(macAddress, bytes);
  }

  Future<EscPosEncoder> _encoderFor(String macAddress) async {
    final width = await PrinterConfigService().getBtPaperWidth(macAddress);
    return EscPosEncoder(lineWidth: width.lineWidth);
  }

  // ESC p 0 t1 t2 — pulse pin 2 to open cash drawer.
  Future<void> openDrawer(String macAddress) async {
    const drawerKick = [0x1B, 0x70, 0x00, 0x19, 0xFA];
    // Some Bluetooth receipt printers need a brief pause after the receipt
    // payload before accepting the drawer pulse on a fresh RFCOMM session.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _send(macAddress, Uint8List.fromList(drawerKick));
  }

  Future<void> _send(String macAddress, dynamic bytes) async {
    final queued = _queue.then((_) async {
      try {
        final length = bytes is Uint8List ? bytes.length : null;
        debugPrint(
          'BtPrinterService: sending ${length ?? 'unknown'} bytes to $macAddress',
        );
        await _ch.invokeMethod<void>('print', {
          'address': macAddress,
          'data': bytes,
        }).timeout(_sendTimeout);
        debugPrint('BtPrinterService: send complete for $macAddress');
      } on TimeoutException {
        debugPrint('BtPrinterService: send timed out for $macAddress');
        return;
      } on PlatformException {
        debugPrint('BtPrinterService: send failed for $macAddress');
        return;
      }
    });

    _queue = queued.catchError((_) {});
    await queued;
  }
}
