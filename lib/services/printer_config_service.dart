import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum PaperWidth {
  w58mm(lineWidth: 32),
  w80mm(lineWidth: 48);

  const PaperWidth({required this.lineWidth});
  final int lineWidth;

  String get label => this == w58mm ? '58 mm' : '80 mm';
}

class PrinterConfigService {
  // Sentinel stored in receiptMac / kitchenMac when the Sunmi built-in printer
  // is explicitly assigned to that role.
  static const kSunmiKey = '__sunmi__';

  static const _kReceiptMac = 'printer_receipt_mac';
  static const _kKitchenMac = 'printer_kitchen_mac';
  static const _kSunmiPaperWidth = 'printer_sunmi_paper_width';
  static const _kBtPaperWidthPrefix = 'printer_bt_width_';

  // ── Receipt / kitchen printer assignment ──────────────────────────────────

  Future<String?> getReceiptPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kReceiptMac);
  }

  Future<String?> getKitchenPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKitchenMac);
  }

  Future<void> setReceiptPrinterMac(String? mac) async {
    final prefs = await SharedPreferences.getInstance();
    if (mac == null) {
      await prefs.remove(_kReceiptMac);
    } else {
      await prefs.setString(_kReceiptMac, mac);
    }
  }

  Future<void> setKitchenPrinterMac(String? mac) async {
    final prefs = await SharedPreferences.getInstance();
    if (mac == null) {
      await prefs.remove(_kKitchenMac);
    } else {
      await prefs.setString(_kKitchenMac, mac);
    }
  }

  // ── Paper width ───────────────────────────────────────────────────────────

  Future<PaperWidth> getSunmiPaperWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSunmiPaperWidth) == PaperWidth.w58mm.name
        ? PaperWidth.w58mm
        : PaperWidth.w80mm;
  }

  Future<void> setSunmiPaperWidth(PaperWidth width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSunmiPaperWidth, width.name);
  }

  Future<PaperWidth> getBtPaperWidth(String macAddress) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_kBtPaperWidthPrefix$macAddress');
    if (saved == PaperWidth.w80mm.name) return PaperWidth.w80mm;
    if (saved == PaperWidth.w58mm.name) return PaperWidth.w58mm;
    // No BT-specific width saved — fall back to the Sunmi paper width so
    // changing the "Built-in Sunmi" setting also affects BT receipts.
    return getSunmiPaperWidth();
  }

  Future<void> setBtPaperWidth(String macAddress, PaperWidth width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kBtPaperWidthPrefix$macAddress', width.name);
  }

  // ── Saved device lists (BT + USB) ─────────────────────────────────────────

  static const _kBtDevices = 'printer_bt_devices';
  static const _kUsbDevices = 'printer_usb_devices';

  Future<List<Map<String, String>>> getSavedDevices({
    required bool bluetooth,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(bluetooth ? _kBtDevices : _kUsbDevices);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k, v.toString())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDevices({
    required bool bluetooth,
    required List<Map<String, String>> devices,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      bluetooth ? _kBtDevices : _kUsbDevices,
      jsonEncode(devices),
    );
  }
}
