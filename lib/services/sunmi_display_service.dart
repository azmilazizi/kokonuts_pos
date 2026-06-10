import 'package:flutter/services.dart';

/// Controls the Sunmi T2 secondary customer-facing display via a MethodChannel.
///
/// Gracefully no-ops when no secondary display is detected (non-T2 hardware,
/// dev machines, or if the presentation fails to show).
class SunmiDisplayService {
  static final SunmiDisplayService _instance = SunmiDisplayService._();
  factory SunmiDisplayService() => _instance;
  SunmiDisplayService._();

  static const _channel = MethodChannel('kokonuts/sunmi_display');

  /// Returns true if a secondary DISPLAY_CATEGORY_PRESENTATION screen is connected.
  Future<bool> hasSecondaryDisplay() async {
    try {
      return await _channel.invokeMethod<bool>('hasSecondaryDisplay') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enable or disable the customer-facing Presentation.
  /// Enabling restores the welcome screen; disabling dismisses the Presentation
  /// so Android shows the secondary display's default state.
  Future<void> setEnabled(bool enabled) => _invoke('setEnabled', enabled);

  Future<void> init() => _invoke('init');

  Future<void> showWelcome() => _invoke('showWelcome');

  Future<void> showOrder({
    required List<Map<String, dynamic>> items,
    required double total,
    double subtotal = 0.0,
    double totalDiscount = 0.0,
    double cashbackAmount = 0.0,
  }) => _invoke('showOrder', {
    'items': items,
    'total': total,
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'cashbackAmount': cashbackAmount,
  });

  Future<void> showPayment(double total) => _invoke('showPayment', total);

  Future<void> showComplete({double totalPaid = 0.0, int queueNumber = 0}) =>
      _invoke('showComplete', {'totalPaid': totalPaid, 'queueNumber': queueNumber});

  /// Show the DuitNow QR hosted page on the customer display using a WebView.
  Future<void> showDuitNowQr(String url) => _invoke('showDuitNowQr', url);

  /// Load a promotional image on the left panel from [imageUrl].
  /// Pass null or an empty string to revert to the orange placeholder.
  Future<void> updatePromoImage(String? imageUrl) =>
      _invoke('updatePromoImage', imageUrl);

  Future<void> _invoke(String method, [dynamic arguments]) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } on PlatformException {
      // No-op — secondary display not available on this device.
    } catch (_) {
      // No-op.
    }
  }
}
