import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global HTTP proxy override that forces the Dart `HttpClient` (used by the
/// `http` package, Dio, and every other `dart:io`-based client) to honor the
/// hotspot / carrier's HTTP proxy.
///
/// Proxy resolution order (first non-empty wins per scheme):
///   1. `SharedPreferences` (user-set from the app Settings screen — highest
///      priority because it is explicit):
///       - `http_proxy_url`       → e.g. `http://10.10.1.1:8080`
///       - `https_proxy_url`      → same (or separate proxy for HTTPS)
///       - `no_proxy_hosts`       → comma-separated host suffix list,
///                                   e.g. `localhost,127.0.0.1,.intranet`
///   2. Dart's `Platform.environment` — works for debug mode via
///      `--dart-define` or when the process was launched with the standard
///      POSIX variables `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`.
///
/// The `findProxy` callback uses the standard `PROXY host:port; DIRECT`
/// format that `HttpClient` expects — this is the exact value Chrome / curl
/// hand off to the system resolver.
///
/// Usage: call [ProxyAwareHttpOverrides.apply] as early as possible in `main`
/// (after `WidgetsFlutterBinding.ensureInitialized()` so SharedPreferences is
/// reachable) and **before** `runApp(...)`. All HTTP clients created with
/// `new HttpClient()` — including the default `http.Client()` used by the
/// app's `ApiClient` — will then consult this override automatically for
/// *every* request.
class ProxyAwareHttpOverrides extends HttpOverrides {
  ProxyAwareHttpOverrides._(this._config);

  final _ProxyConfig _config;

  static const _kPrefHttpProxy = 'http_proxy_url';
  static const _kPrefHttpsProxy = 'https_proxy_url';
  static const _kPrefNoProxy = 'no_proxy_hosts';

  /// Sets [HttpOverrides.global] to a [ProxyAwareHttpOverrides] instance with
  /// proxy values resolved from SharedPreferences + `Platform.environment`.
  ///
  /// Safe to call multiple times (re-applies with latest preferences).
  static Future<ProxyAwareHttpOverrides> apply() async {
    final cfg = await _ProxyConfig.resolve();
    final overrides = ProxyAwareHttpOverrides._(cfg);
    HttpOverrides.global = overrides;
    if (cfg.httpProxy != null || cfg.httpsProxy != null) {
      debugPrint(
        '[PROXY] HTTP=${cfg.httpProxy ?? 'DIRECT'}  '
        'HTTPS=${cfg.httpsProxy ?? 'DIRECT'}  '
        'NO_PROXY=${cfg.noProxy.join(',')}',
      );
    }
    return overrides;
  }

  /// Shortcut for unit tests / quick overrides — takes plain strings.
  /// Pass `null` to force DIRECT.
  static ProxyAwareHttpOverrides applyManual({
    String? httpProxy,
    String? httpsProxy,
    List<String> noProxy = const [],
  }) {
    final cfg = _ProxyConfig(
      httpProxy: _normalizeProxy(httpProxy),
      httpsProxy: _normalizeProxy(httpsProxy),
      noProxy: noProxy,
    );
    final overrides = ProxyAwareHttpOverrides._(cfg);
    HttpOverrides.global = overrides;
    return overrides;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    return client;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    final bypass = _config.noProxy;
    if (bypass.isNotEmpty && _matchesBypass(url.host, bypass)) {
      return 'DIRECT';
    }
    final isHttps = url.scheme == 'https';
    final proxy = isHttps ? _config.httpsProxy : _config.httpProxy;
    if (proxy != null && proxy.isNotEmpty) {
      // Convert "http://host:port" or "host:port" into "PROXY host:port".
      final authority = _proxyAuthority(proxy);
      return 'PROXY $authority; DIRECT';
    }
    return 'DIRECT';
  }

  static String? _normalizeProxy(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    return v;
  }

  /// Extracts `host:port` from a value that may be written as:
  ///   - `http://proxy.local:8080`
  ///   - `https://proxy.local:8080`
  ///   - `proxy.local:8080`
  ///   - `user:pass@proxy.local:8080`  (authority form)
  static String _proxyAuthority(String value) {
    try {
      final uri = Uri.parse(value.contains('://') ? value : 'http://$value');
      return '${uri.host}:${uri.hasPort ? uri.port : 80}';
    } catch (_) {
      // Fallback: use raw value as-is — HttpClient will still try it.
      return value;
    }
  }

  static bool _matchesBypass(String host, List<String> patterns) {
    for (final pat in patterns) {
      final p = pat.trim().toLowerCase();
      if (p.isEmpty) continue;
      final h = host.toLowerCase();
      // Leading dot — suffix match: `.intranet` matches `foo.intranet`.
      if (p.startsWith('.')) {
        if (h.endsWith(p) || h == p.substring(1)) return true;
      } else if (p.startsWith('*')) {
        final suffix = p.substring(1);
        if (h.endsWith(suffix)) return true;
      } else {
        // Exact match OR suffix match on subdomain boundaries.
        if (h == p || h.endsWith('.$p')) return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Settings-screen persistence helpers (read/write user-set proxy config).
  // ---------------------------------------------------------------------------

  /// Returns currently saved proxy values for display in the Settings UI.
  /// Uses a record to avoid exposing the internal _ProxyConfig type.
  static Future<({String? http, String? https, List<String> noProxy})>
  readSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      http: _normalizeProxy(prefs.getString(_kPrefHttpProxy)),
      https: _normalizeProxy(prefs.getString(_kPrefHttpsProxy)),
      noProxy: _splitHosts(prefs.getString(_kPrefNoProxy)),
    );
  }

  static Future<void> saveConfig({
    String? httpProxy,
    String? httpsProxy,
    String? noProxyCsv,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (httpProxy == null || httpProxy.trim().isEmpty) {
      await prefs.remove(_kPrefHttpProxy);
    } else {
      await prefs.setString(_kPrefHttpProxy, httpProxy.trim());
    }
    if (httpsProxy == null || httpsProxy.trim().isEmpty) {
      await prefs.remove(_kPrefHttpsProxy);
    } else {
      await prefs.setString(_kPrefHttpsProxy, httpsProxy.trim());
    }
    if (noProxyCsv == null || noProxyCsv.trim().isEmpty) {
      await prefs.remove(_kPrefNoProxy);
    } else {
      await prefs.setString(_kPrefNoProxy, noProxyCsv.trim());
    }
    // Re-apply immediately so new values take effect for the next HTTP call
    // without requiring an app restart.
    await apply();
  }

  static List<String> _splitHosts(String? raw) {
    if (raw == null) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}

class _ProxyConfig {
  _ProxyConfig({
    required this.httpProxy,
    required this.httpsProxy,
    required this.noProxy,
  });

  final String? httpProxy;
  final String? httpsProxy;
  final List<String> noProxy;

  static Future<_ProxyConfig> resolve() async {
    final saved = await ProxyAwareHttpOverrides.readSavedConfig();
    if (saved.http != null || saved.https != null) {
      return _ProxyConfig(
        httpProxy: saved.http,
        httpsProxy: saved.https,
        noProxy: saved.noProxy,
      );
    }
    final env = Platform.environment;
    String? envHttp = _firstEnv(env, const ['HTTP_PROXY', 'http_proxy']);
    String? envHttps = _firstEnv(env, const [
      'HTTPS_PROXY',
      'https_proxy',
      'HTTP_PROXY',
      'http_proxy',
    ]);
    final envNo = _firstEnv(env, const ['NO_PROXY', 'no_proxy']);
    return _ProxyConfig(
      httpProxy: ProxyAwareHttpOverrides._normalizeProxy(envHttp),
      httpsProxy: ProxyAwareHttpOverrides._normalizeProxy(envHttps),
      noProxy: ProxyAwareHttpOverrides._splitHosts(envNo),
    );
  }

  static String? _firstEnv(Map<String, String> env, List<String> keys) {
    for (final k in keys) {
      final v = env[k];
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }
}
