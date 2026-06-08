import 'package:flutter/services.dart';

import 'label_printer_service.dart';

/// Real implementation — delegates every call to [BixolonLabelPlugin] via the
/// [MethodChannel] registered in MainActivity.
///
/// Only used in **release** mode on Android.
/// In debug mode or on non-Android platforms [MockBixolonLabelService] is used.
class BixolonLabelService implements LabelPrinterService {
  static const _ch = MethodChannel('kokonuts/bixolon_label');

  // ── LabelPrinterService ───────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    try {
      final ok = await _ch.invokeMethod<bool>('connect') ?? false;
      if (!ok) throw const LabelPrinterException('connect() returned false.', 'CONNECT_FAILED');
    } on PlatformException catch (e) {
      throw LabelPrinterException(e.message ?? 'Connection failed.', e.code);
    }
  }

  @override
  Future<void> printLabel(LabelPrintJob job) async {
    try {
      await _ch.invokeMethod<bool>('printLabel', {
        'queueNumber': job.queueNumber,
        'name': job.itemName,
        'category': job.category,
        'modifier': job.modifier,
        'dateTime': job.dateTime,
        'itemIndex': job.itemIndex,
        'totalItems': job.totalItems,
      });
    } on PlatformException catch (e) {
      throw LabelPrinterException(e.message ?? 'Print failed.', e.code);
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _ch.invokeMethod<bool>('disconnect');
    } on PlatformException catch (e) {
      throw LabelPrinterException(e.message ?? 'Disconnect failed.', e.code);
    }
  }

  @override
  Future<bool> get isConnected async {
    try {
      return await _ch.invokeMethod<bool>('isConnected') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
