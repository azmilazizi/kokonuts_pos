import 'package:flutter/foundation.dart';

import 'label_printer_service.dart';

/// Simulated label printer for development on Mac (or any non-Android host)
/// and for debug builds on device.
///
/// All operations succeed after a short artificial delay and print a summary
/// to the debug console so you can verify the call flow without hardware.
class MockBixolonLabelService implements LabelPrinterService {
  bool _connected = false;

  @override
  Future<void> connect() async {
    await Future.delayed(const Duration(milliseconds: 250));
    _connected = true;
    debugPrint('[MockBixolon] connect() → OK');
  }

  @override
  Future<void> printLabel(LabelPrintJob job) async {
    if (!_connected) {
      throw const LabelPrinterException(
        'Not connected. Call connect() first.',
        'NOT_CONNECTED',
      );
    }
    await Future.delayed(const Duration(milliseconds: 400));
    debugPrint('[MockBixolon] printLabel()');
    debugPrint('[MockBixolon]   queue    : ${job.queueNumber}');
    debugPrint('[MockBixolon]   name     : ${job.itemName}');
    debugPrint('[MockBixolon]   category : ${job.category}');
    debugPrint('[MockBixolon]   modifier : ${job.modifier}');
    debugPrint('[MockBixolon]   dateTime : ${job.dateTime}');
    debugPrint('[MockBixolon]   item     : ${job.itemIndex}/${job.totalItems}');
  }

  @override
  Future<void> disconnect() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _connected = false;
    debugPrint('[MockBixolon] disconnect() → OK');
  }

  @override
  Future<bool> get isConnected async => _connected;
}
