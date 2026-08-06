import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global HTTP proxy override that forces the Dart `HttpClient` (used by the
/// `http` package, Dio, and every other `dart:io`-based client) to honor the
/// hotspot / carrier's HTTP proxy.
///
/// # Why this works
///
/// Simply overriding [findProxyFromEnvironment] is **not** enough.
/// The default `HttpClient` has `findProxy == null` (i.e. always DIRECT)
/// unless you explicitly assign it to `HttpClient.findProxyFromEnvironment`.
/// This class does that for **every** client returned by [createHttpClient] —
/// so every `new HttpClient()` (including the one wrapped by `package:http`'s
/// default `IOClient`) will route through our resolver.
///
/// # Proxy resolution order (first non-empty wins per scheme):
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
/// # Captive-portal / HTTPS-over-HTTP-proxy helper
///
/// Exhausted-data hotspots / corporate proxies often inject a transparent
/// HTTPS MITM with a self-signed certificate to serve the quota page.
/// The setting `trust_bad_certs = true` will install a permissive
/// [badCertificateCallback] so connectivity is not broken by the cert error.
/// Only flip this on when you *know* you're on a hotspot that does this —
/// don't leave it on permanently for untrusted networks.
class ProxyAwareHttpOverrides extends HttpOverrides {
  ProxyAwareHttpOverrides._(this._config);

  final _ProxyConfig _config;

  static const _kPrefHttpProxy = 'http_proxy_url';
  static const _kPrefHttpsProxy = 'https_proxy_url';
  static const _kPrefNoProxy = 'no_proxy_hosts';
  static const _kPrefTrustBad = 'trust_bad_certs';
  static const _kPrefVerbose = 'proxy_verbose_log';

  // ---------------------------------------------------------------------------
  // Application entry-point helpers
  // ---------------------------------------------------------------------------

  /// Sets [HttpOverrides.global] to a [ProxyAwareHttpOverrides] instance with
  /// proxy values resolved from SharedPreferences + `Platform.environment`.
  ///
  /// Safe to call multiple times (re-applies with latest preferences).
  static Future<ProxyAwareHttpOverrides> apply() async {
    final cfg = await _ProxyConfig.resolve();
    final overrides = ProxyAwareHttpOverrides._(cfg);
    HttpOverrides.global = overrides;
    if (cfg.httpProxy != null || cfg.httpsProxy != null || cfg.trustBadCerts) {
      debugPrint(
        '[PROXY] HTTP=${cfg.httpProxy ?? 'DIRECT'}  '
        'HTTPS=${cfg.httpsProxy ?? 'DIRECT'}  '
        'NO_PROXY=${cfg.noProxy.isEmpty ? '-' : cfg.noProxy.join(',')}  '
        'TRUST_BAD_CERTS=${cfg.trustBadCerts}  '
        'VERBOSE=${cfg.verboseLog}',
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
    bool trustBadCerts = false,
  }) {
    final cfg = _ProxyConfig(
      httpProxy: _normalizeProxy(httpProxy),
      httpsProxy: _normalizeProxy(httpsProxy),
      noProxy: noProxy,
      trustBadCerts: trustBadCerts,
      verboseLog: false,
    );
    final overrides = ProxyAwareHttpOverrides._(cfg);
    HttpOverrides.global = overrides;
    return overrides;
  }

  /// Returns the currently-active proxy in a human-readable summary, used by
  /// the "Test Connection" dialog in settings so the user can visually
  /// confirm which proxy is in effect when debugging failures.
  static Future<String> summary() async {
    final c = await _ProxyConfig.resolve();
    final lines = <String>[
      'HTTP proxy     : ${c.httpProxy ?? '(direct)'}',
      'HTTPS proxy    : ${c.httpsProxy ?? '(direct)'}',
      'Bypass list    : ${c.noProxy.isEmpty ? '—' : c.noProxy.join(', ')}',
      'Trust bad certs: ${c.trustBadCerts ? 'ON (captive portal friendly)' : 'off'}',
      'Verbose log    : ${c.verboseLog ? 'on' : 'off'}',
    ];
    return lines.join('\n');
  }

  // ---------------------------------------------------------------------------
  // HttpOverrides hooks — the actual plumbing
  // ---------------------------------------------------------------------------

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // THIS is the line that makes proxying work.
    // `HttpClient.findProxyFromEnvironment` is a static helper that
    // delegates to `HttpOverrides.current.findProxyFromEnvironment(url, env)`
    // — which is the method we override below. Without this assignment,
    // `findProxyFromEnvironment` is NEVER called and all traffic goes DIRECT.
    client.findProxy = HttpClient.findProxyFromEnvironment;

    // Captive-portal / transparent-HTTPS-interop workaround: install a
    // permissive callback when the user has explicitly opted in.
    if (_config.trustBadCerts) {
      client.badCertificateCallback = (cert, host, port) => true;
    }

    if (_config.verboseLog) {
      client.connectionFactory =
          null; // keep default factory, we just want trace
    }

    return client;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    // User-supplied bypass list.
    if (_config.noProxy.isNotEmpty &&
        _matchesBypass(url.host, _config.noProxy)) {
      if (_config.verboseLog) {
        debugPrint('[PROXY] $url → DIRECT (bypass match)');
      }
      return 'DIRECT';
    }
    final isHttps = url.scheme == 'https';
    final proxy = isHttps ? _config.httpsProxy : _config.httpProxy;
    if (proxy != null && proxy.isNotEmpty) {
      final authority = _proxyAuthority(proxy);
      final result = 'PROXY $authority; DIRECT';
      if (_config.verboseLog) {
        debugPrint('[PROXY] $url → $result');
      }
      return result;
    }

    if (_config.verboseLog) {
      debugPrint('[PROXY] $url → DIRECT');
    }
    return 'DIRECT';
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

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
      if (uri.host.isEmpty) {
        return value; // give raw value a chance
      }
      return '${uri.host}:${uri.hasPort ? uri.port : 80}';
    } catch (_) {
      return value;
    }
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

  // ---------------------------------------------------------------------------
  // Settings-screen persistence helpers (read/write user-set proxy config).
  // ---------------------------------------------------------------------------

  /// Returns currently saved proxy values for display in the Settings UI.
  /// Uses a record to avoid exposing the internal _ProxyConfig type.
  static Future<
    ({
      String? http,
      String? https,
      List<String> noProxy,
      bool trustBadCerts,
      bool verboseLog,
    })
  >
  readSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      http: _normalizeProxy(prefs.getString(_kPrefHttpProxy)),
      https: _normalizeProxy(prefs.getString(_kPrefHttpsProxy)),
      noProxy: _splitHosts(prefs.getString(_kPrefNoProxy)),
      trustBadCerts: prefs.getBool(_kPrefTrustBad) ?? false,
      verboseLog: prefs.getBool(_kPrefVerbose) ?? false,
    );
  }

  static Future<void> saveConfig({
    String? httpProxy,
    String? httpsProxy,
    String? noProxyCsv,
    bool? trustBadCerts,
    bool? verboseLog,
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
    if (trustBadCerts != null) {
      await prefs.setBool(_kPrefTrustBad, trustBadCerts);
    }
    if (verboseLog != null) {
      await prefs.setBool(_kPrefVerbose, verboseLog);
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
    required this.trustBadCerts,
    required this.verboseLog,
  });

  final String? httpProxy;
  final String? httpsProxy;
  final List<String> noProxy;
  final bool trustBadCerts;
  final bool verboseLog;

  static Future<_ProxyConfig> resolve() async {
    final saved = await ProxyAwareHttpOverrides.readSavedConfig();
    if (saved.http != null ||
        saved.https != null ||
        saved.trustBadCerts ||
        saved.verboseLog) {
      return _ProxyConfig(
        httpProxy: saved.http,
        httpsProxy: saved.https,
        noProxy: saved.noProxy,
        trustBadCerts: saved.trustBadCerts,
        verboseLog: saved.verboseLog,
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
    final trustEnv = _firstBoolEnv(env, const [
      'TRUST_BAD_CERTS',
      'trust_bad_certs',
    ]);
    final verboseEnv = _firstBoolEnv(env, const [
      'PROXY_VERBOSE_LOG',
      'proxy_verbose_log',
    ]);
    return _ProxyConfig(
      httpProxy: ProxyAwareHttpOverrides._normalizeProxy(envHttp),
      httpsProxy: ProxyAwareHttpOverrides._normalizeProxy(envHttps),
      noProxy: ProxyAwareHttpOverrides._splitHosts(envNo),
      trustBadCerts: trustEnv ?? false,
      verboseLog: verboseEnv ?? false,
    );
  }

  static String? _firstEnv(Map<String, String> env, List<String> keys) {
    for (final k in keys) {
      final v = env[k];
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  static bool? _firstBoolEnv(Map<String, String> env, List<String> keys) {
    for (final k in keys) {
      final v = env[k]?.trim().toLowerCase();
      if (v == null) continue;
      if (const {'1', 'true', 'yes', 'on'}.contains(v)) return true;
      if (const {'0', 'false', 'no', 'off'}.contains(v)) return false;
    }
    return null;
  }
}
