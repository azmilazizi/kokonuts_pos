import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../storage/secure_store.dart';
import 'print_models.dart';

class StoreConfigService {
  static final StoreConfigService _instance = StoreConfigService._();
  factory StoreConfigService() => _instance;
  StoreConfigService._();

  final _api = ApiClient();
  final _store = SecureStore();

  StoreConfig? _cached;

  // ── Store config ──────────────────────────────────────────────────────────
  //
  // Fetches receipt settings from GET /pos/api/v1/receipt_settings.
  // The result is cached in memory; call invalidate() to force a re-fetch
  // (e.g. after the user updates settings).
  //
  // Falls back to a minimal default if the network call fails so printing
  // still works offline.

  Future<StoreConfig> getConfig() async {
    if (_cached != null) return _cached!;

    try {
      final token = await _store.readToken();
      final response = await _api.getJson(
        '/pos/api/v1/receipt_settings',
        authToken: token,
      );
      final data =
          (response.data['data'] as Map<String, dynamic>?) ?? response.data;

      Uint8List? logoBytes;
      final logoUrl = data['logo_url'] as String?;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        logoBytes = await _downloadLogo(logoUrl);
      }

      _cached = StoreConfig(
        storeName: data['company_name'] as String? ?? 'KOKONUTS',
        companyRegId: data['company_reg_id'] as String? ?? '',
        address: data['address'] as String? ?? '',
        phone: data['phone'] as String? ?? '',
        header: data['header'] as String? ?? '',
        footer: data['footer'] as String? ?? 'Thank you!',
        logoBytes: logoBytes,
      );
    } catch (_) {
      _cached ??= const StoreConfig(storeName: 'KOKONUTS');
    }

    return _cached!;
  }

  // Call this when receipt settings may have changed (e.g. on settings save).
  void invalidate() => _cached = null;

  // ── Cashback URL ──────────────────────────────────────────────────────────
  //
  // Calls POST /api/pos/cashback to create a server-side cashback record that
  // expires 12 hours after the receipt is issued.  The backend returns a
  // unique URL encoding a signed token.  When the customer scans the QR:
  //   - still valid   → loyalty claim page
  //   - expired       → "This offer has expired" page
  //
  // Backend contract:
  //   POST /api/pos/cashback
  //   { "receipt_id": "...", "expires_at": "<ISO-8601 UTC>" }
  //   → 201 { "url": "https://crm.kokonuts.my/cashback/<TOKEN>" }
  //
  // Returns null on network/auth failure → QR section is silently omitted.

  Future<String?> generateCashbackUrl(String receiptId) async {
    try {
      final token = await _store.readToken();
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 12));
      final response = await _api.postJson(
        '/api/pos/cashback',
        body: {
          'receipt_id': receiptId,
          'expires_at': expiresAt.toIso8601String(),
        },
        authToken: token,
      );
      final url = response.data['url'];
      return url is String ? url : null;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Uint8List?> _downloadLogo(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
