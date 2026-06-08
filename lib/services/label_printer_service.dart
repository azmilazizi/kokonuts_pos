import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'bixolon_label_service.dart';
import 'mock_bixolon_label_service.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class LabelPrintJob {
  const LabelPrintJob({
    required this.queueNumber,
    required this.itemName,
    required this.category,
    required this.modifier,
    required this.dateTime,
    required this.itemIndex,
    required this.totalItems,
  });

  final int queueNumber;
  final String itemName;
  final String category;

  /// Space-joined selected modifier names, e.g. "Normal Sweet".
  final String modifier;

  /// Formatted date+time string, e.g. "2024.11.02 13:39".
  final String dateTime;

  /// 1-based position of this item type in the order.
  final int itemIndex;

  /// Total number of distinct item types in the order.
  final int totalItems;
}

// ─── Exception ────────────────────────────────────────────────────────────────

class LabelPrinterException implements Exception {
  const LabelPrinterException(this.message, [this.code]);

  final String message;
  final String? code;

  @override
  String toString() =>
      code != null ? 'LabelPrinterException[$code]: $message' : 'LabelPrinterException: $message';
}

// ─── Abstract interface ───────────────────────────────────────────────────────

abstract class LabelPrinterService {
  /// Find and connect to the Bixolon printer over USB.
  /// Throws [LabelPrinterException] on failure.
  Future<void> connect();

  /// Print a drink label for [job].
  /// Throws [LabelPrinterException] on failure.
  Future<void> printLabel(LabelPrintJob job);

  /// Release the USB connection cleanly.
  Future<void> disconnect();

  /// Returns true if a connection is currently open.
  Future<bool> get isConnected;
}

// ─── Dependency injection ─────────────────────────────────────────────────────

/// Returns the correct [LabelPrinterService] implementation:
///
/// | Environment                   | Implementation              |
/// |-------------------------------|-----------------------------|
/// | Web                           | [MockBixolonLabelService]   |
/// | Non-Android (macOS, iOS, …)   | [MockBixolonLabelService]   |
/// | Android                       | [BixolonLabelService]       |
LabelPrinterService createLabelPrinterService() {
  if (kIsWeb) return MockBixolonLabelService();
  if (!Platform.isAndroid) return MockBixolonLabelService();
  return BixolonLabelService();
}
