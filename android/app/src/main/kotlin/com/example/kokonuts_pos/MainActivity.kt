package com.example.kokonuts_pos

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Proxy
import android.net.ProxyInfo
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var printerDiscovery: PrinterDiscoveryPlugin

    private var proxyEventSink: EventChannel.EventSink? = null
    private var proxyReceiver: BroadcastReceiver? = null

    companion object {
        private const val REQUEST_BT_PERMISSIONS = 1001
        private const val CHANNEL_SYSTEM_NET = "kokonuts_pos/system_network"
        private const val CHANNEL_SYSTEM_NET_EVENTS = "kokonuts_pos/system_network/proxy_updates"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        SunmiDisplayPlugin(this).registerWith(messenger)
        printerDiscovery = PrinterDiscoveryPlugin(this).also { it.registerWith(messenger) }
        BixolonLabelPlugin(this).registerWith(messenger)
        BluetoothPrinterPlugin(this).registerWith(messenger)

        MethodChannel(messenger, CHANNEL_SYSTEM_NET).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemProxy" -> result.success(readSystemProxy())
                else -> result.notImplemented()
            }
        }

        // Android reports the Wi-Fi/system proxy asynchronously via a broadcast
        // (visible in logcat as "sending Proxy Broadcast for ...") whenever the
        // network reconnects or the proxy setting changes — e.g. while TetherFi's
        // Wi-Fi Direct hotspot cycles. A one-shot read at app startup can race
        // that and lock onto a stale "no proxy" result for the app's lifetime,
        // so we push live updates to Dart instead of relying on a single read.
        EventChannel(messenger, CHANNEL_SYSTEM_NET_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    proxyEventSink = events
                    registerProxyReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    proxyEventSink = null
                    unregisterProxyReceiver()
                }
            },
        )
    }

    private fun registerProxyReceiver() {
        if (proxyReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                proxyEventSink?.success(readSystemProxy())
            }
        }
        proxyReceiver = receiver
        // PROXY_CHANGE_ACTION is a protected system broadcast (only the OS can
        // send it) delivered as a sticky broadcast. Sticky delivery doesn't
        // carry the auto-generated NOT_EXPORTED permission grant, so the
        // system's own broadcast gets rejected with a PermissionDenial if we
        // register NOT_EXPORTED here. EXPORTED is safe since no other app can
        // spoof a protected broadcast action.
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(Proxy.PROXY_CHANGE_ACTION),
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    private fun unregisterProxyReceiver() {
        proxyReceiver?.let {
            runCatching { unregisterReceiver(it) }
            proxyReceiver = null
        }
    }

    override fun onStart() {
        super.onStart()
        requestBluetoothPermissionsIfNeeded()
    }

    private fun requestBluetoothPermissionsIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val needed = arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
        ).filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), REQUEST_BT_PERMISSIONS)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) currentFocus?.clearFocus()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::printerDiscovery.isInitialized) printerDiscovery.dispose()
        unregisterProxyReceiver()
    }

    private fun readSystemProxy(): Map<String, Any?> {
        val fallbackHost = Proxy.getHost(context).takeIf { !it.isNullOrEmpty() }
        val fallbackPort = Proxy.getPort(context).takeIf { it > 0 }

        val info: ProxyInfo? = runCatching {
            val cm = context.getSystemService(android.net.ConnectivityManager::class.java)
                ?: return@runCatching null

            val defaultProxy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cm.defaultProxy
            } else {
                null
            }
            if (!defaultProxy?.host.isNullOrEmpty()) return@runCatching defaultProxy

            // getDefaultProxy() only returns a network's proxy if that network
            // is the OS's "default network". A hotspot like TetherFi's Wi-Fi
            // Direct group can only reach the internet THROUGH its own proxy,
            // so Android's connectivity validator can never confirm it has
            // working internet (everValidated stays false) — which can keep it
            // from being selected as default even while connected, so the
            // manually-configured proxy never surfaces via getDefaultProxy().
            // Fall back to scanning every connected network directly for a
            // Wi-Fi transport carrying a proxy, bypassing "default" entirely.
            cm.allNetworks.asSequence()
                .filter { network ->
                    cm.getNetworkCapabilities(network)
                        ?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true
                }
                .mapNotNull { network -> cm.getLinkProperties(network)?.httpProxy }
                .firstOrNull { proxy -> !proxy.host.isNullOrEmpty() }
        }.getOrNull()

        val httpHost = (info?.host?.takeIf { it.isNotEmpty() } ?: fallbackHost)
        val httpPort = (info?.port?.takeIf { it > 0 } ?: fallbackPort) ?: 0
        val rawArray: Array<String?>? = info?.exclusionList
        val exclusionList = if (rawArray.isNullOrEmpty()) {
            emptyList<String>()
        } else {
            val out = ArrayList<String>(rawArray.size)
            for (item in rawArray) if (item != null) out.add(item)
            out
        }

        return mapOf(
            "httpHost" to httpHost,
            "httpPort" to if (httpPort > 0) httpPort else null,
            "httpsHost" to httpHost,
            "httpsPort" to if (httpPort > 0) httpPort else null,
            "exclusionList" to exclusionList,
        )
    }
}
