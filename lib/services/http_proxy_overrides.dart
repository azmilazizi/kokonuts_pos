import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Global [HttpOverrides] that forces every [HttpClient] to honor the
/// **Android system Wi-Fi proxy** set via:
///   Settings → Wi-Fi → (network) → Advanced → Proxy → Manual
///
/// Why this is needed:
/// - Dart's `Platform.environment` does NOT see Android Wi-Fi proxy vars.
/// - Default `HttpClient` has `findProxy == null` (always DIRECT).
///
/// This class fixes both:
///   1. On startup, reads proxy from Android via a MethodChannel.
///   2. Wires `client.findProxy = HttpClient.findProxyFromEnvironment` on
///      EVERY client so resolver below runs for every request.
///   3. Falls back to POSIX env vars for iOS/desktop/debug.
class ProxyAwareHttpOverrides extends HttpOverrides {
  ProxyAwareHttpOverrides._(this._config);

  _SystemProxyConfig _config;

  static const _channel = MethodChannel('kokonuts_pos/system_network');
  static const _eventChannel = EventChannel(
    'kokonuts_pos/system_network/proxy_updates',
  );
  static bool _channelRead = false;
  static _SystemProxyConfig? _lastFetched;

  /// Install the override globally.
  /// Call from `main()` AFTER `WidgetsFlutterBinding.ensureInitialized()`
  /// and BEFORE `runApp(...)`.
  static Future<ProxyAwareHttpOverrides> apply() async {
    final cfg = await _SystemProxyConfig.resolve();
    final overrides = ProxyAwareHttpOverrides._(cfg);
    HttpOverrides.global = overrides;
    _logConfig(cfg);
    overrides._listenForSystemChanges();
    return overrides;
  }

  static void _logConfig(_SystemProxyConfig cfg) {
    if (cfg.httpHost != null || cfg.httpsHost != null) {
      debugPrint(
        '[PROXY] HTTP=${cfg.httpHost ?? '?'}:${cfg.httpPort ?? '?'}  '
        'HTTPS=${cfg.httpsHost ?? '?'}:${cfg.httpsPort ?? '?'}  '
        'EXCLUDE=${cfg.exclusionList.isEmpty ? '-' : cfg.exclusionList.join(',')}',
      );
    } else {
      debugPrint('[PROXY] No system proxy configured — using DIRECT.');
    }
  }

  /// Android's Wi-Fi/system proxy can change after startup (network
  /// reconnects, proxy toggled, hotspot cycles — as with TetherFi's Wi-Fi
  /// Direct group). The native side pushes updates over this stream so the
  /// app self-heals instead of being locked onto whatever was read at
  /// startup for its entire lifetime.
  void _listenForSystemChanges() {
    if (kIsWeb || !Platform.isAndroid) return;
    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        _config = _SystemProxyConfig._fromChannelMap(
          Map<String, Object?>.from(event),
        );
        _logConfig(_config);
      },
      onError: (Object e) => debugPrint('[PROXY] update stream error: $e'),
    );
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // THIS is the critical wiring — without this line, findProxyFromEnvironment
    // is NEVER called and every request goes DIRECT.
    client.findProxy = HttpClient.findProxyFromEnvironment;
    return client;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    // 1. Respect Android ProxyInfo exclusion list
    if (_config.exclusionList.isNotEmpty &&
        _matchesBypass(url.host, _config.exclusionList)) {
      return 'DIRECT';
    }
    // 2. Per-scheme proxy from Android system layer
    final isHttps = url.scheme == 'https';
    final host = isHttps ? _config.httpsHost : _config.httpHost;
    final port = isHttps ? _config.httpsPort : _config.httpPort;
    if (host != null && port != null) {
      return 'PROXY $host:$port; DIRECT';
    }
    // 3. Fallback: POSIX env vars (HTTP_PROXY, HTTPS_PROXY, NO_PROXY)
    return super.findProxyFromEnvironment(url, environment);
  }

  static bool _matchesBypass(String host, List<String> patterns) {
    for (final pat in patterns) {
      final p = pat.trim().toLowerCase();
      if (p.isEmpty) continue;
      final h = host.toLowerCase();
      if (p.startsWith('.')) {
        if (h.endsWith(p) || h == p.substring(1)) return true;
      } else if (p.startsWith('*')) {
        final suffix = p.substring(1);
        if (h.endsWith(suffix)) return true;
      } else {
        if (h == p || h.endsWith('.$p')) return true;
      }
    }
    return false;
  }
}

class _SystemProxyConfig {
  _SystemProxyConfig({
    required this.httpHost,
    required this.httpPort,
    required this.httpsHost,
    required this.httpsPort,
    required this.exclusionList,
  });

  final String? httpHost;
  final int? httpPort;
  final String? httpsHost;
  final int? httpsPort;
  final List<String> exclusionList;

  static _SystemProxyConfig _fromChannelMap(Map<String, Object?> data) {
    final httpHost = data['httpHost'] as String?;
    final hp = data['httpPort'];
    final httpPort = hp is int
        ? hp
        : (hp is num)
        ? hp.toInt()
        : null;
    final httpsHost = data['httpsHost'] as String?;
    final sp = data['httpsPort'];
    final httpsPort = sp is int
        ? sp
        : (sp is num)
        ? sp.toInt()
        : null;
    final ex = data['exclusionList'];
    final exclusionList = ex is List
        ? ex.whereType<String>().toList(growable: false)
        : const <String>[];
    return _SystemProxyConfig(
      httpHost: httpHost,
      httpPort: httpPort,
      httpsHost: httpsHost,
      httpsPort: httpsPort,
      exclusionList: exclusionList,
    );
  }

  static Future<_SystemProxyConfig> resolve() async {
    // Cache to avoid repeated platform calls per app session
    if (ProxyAwareHttpOverrides._channelRead &&
        ProxyAwareHttpOverrides._lastFetched != null) {
      return ProxyAwareHttpOverrides._lastFetched!;
    }

    String? httpHost;
    int? httpPort;
    String? httpsHost;
    int? httpsPort;
    List<String> exclusionList = const [];

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final data = await ProxyAwareHttpOverrides._channel
            .invokeMapMethod<String, Object>('getSystemProxy');
        if (data != null) {
          ProxyAwareHttpOverrides._lastFetched = _fromChannelMap(data);
          ProxyAwareHttpOverrides._channelRead = true;
          return ProxyAwareHttpOverrides._lastFetched!;
        }
      } catch (e) {
        debugPrint('[PROXY] platform read failed: $e');
      }
    }

    // Fallback for non-Android: standard POSIX env vars
    final env = Platform.environment;
    httpHost ??= _hostFromEnv(env, const ['HTTP_PROXY', 'http_proxy']);
    httpPort ??= _portFromEnv(env, const ['HTTP_PROXY', 'http_proxy']);
    httpsHost ??= _hostFromEnv(env, const [
      'HTTPS_PROXY',
      'https_proxy',
      'HTTP_PROXY',
      'http_proxy',
    ]);
    httpsPort ??= _portFromEnv(env, const [
      'HTTPS_PROXY',
      'https_proxy',
      'HTTP_PROXY',
      'http_proxy',
    ]);
    final noProxy = env['NO_PROXY'] ?? env['no_proxy'];
    if (noProxy != null && noProxy.isNotEmpty) {
      exclusionList = noProxy
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    return _SystemProxyConfig(
      httpHost: httpHost,
      httpPort: httpPort,
      httpsHost: httpsHost,
      httpsPort: httpsPort,
      exclusionList: exclusionList,
    );
  }

  static String? _firstEnv(Map<String, String> env, List<String> keys) {
    for (final k in keys) {
      final v = env[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static String? _hostFromEnv(Map<String, String> env, List<String> keys) {
    final v = _firstEnv(env, keys);
    if (v == null) return null;
    try {
      final uri = Uri.parse(v.contains('://') ? v : 'http://$v');
      return uri.host.isEmpty ? null : uri.host;
    } catch (_) {
      return null;
    }
  }

  static int? _portFromEnv(Map<String, String> env, List<String> keys) {
    final v = _firstEnv(env, keys);
    if (v == null) return null;
    try {
      final uri = Uri.parse(v.contains('://') ? v : 'http://$v');
      return uri.hasPort ? uri.port : null;
    } catch (_) {
      return null;
    }
  }
}
