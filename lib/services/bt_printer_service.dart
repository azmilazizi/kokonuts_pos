import 'dart:isolate';

import 'package:flutter/services.dart';

import 'esc_pos_encoder.dart';
import 'printer_config_service.dart';
import 'receipt_builder.dart';
import 'receipt_commands.dart';
import 'store_config_service.dart';

class BtPrinterService {
  static const _ch = MethodChannel('kokonuts/bt_printer');

  Future<void> printCommands(String macAddress, List<ReceiptCmd> commands) async {
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
    await _send(macAddress, Uint8List.fromList(drawerKick));
  }

  Future<void> _send(String macAddress, dynamic bytes) async {
    try {
      await _ch.invokeMethod<void>(
        'print',
        {'address': macAddress, 'data': bytes},
      );
    } on PlatformException {
      // Silently swallowed — mirrors no-op pattern of SunmiPrinterService.
    }
  }
}
