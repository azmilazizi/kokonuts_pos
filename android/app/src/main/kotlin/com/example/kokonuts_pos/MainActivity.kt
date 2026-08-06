package com.example.kokonuts_pos

import android.Manifest
import android.content.pm.PackageManager
import android.net.Proxy
import android.net.ProxyInfo
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var printerDiscovery: PrinterDiscoveryPlugin

    companion object {
        private const val REQUEST_BT_PERMISSIONS = 1001
        private const val CHANNEL_SYSTEM_NET = "kokonuts_pos/system_network"
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
    }

    private fun readSystemProxy(): Map<String, Any?> {
        val fallbackHost = Proxy.getHost(context).takeIf { !it.isNullOrEmpty() }
        val fallbackPort = Proxy.getPort(context).takeIf { it > 0 }

        val info: ProxyInfo? = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val cm = context.getSystemService(android.net.ConnectivityManager::class.java)
                cm?.defaultProxy
            } else null
        }.getOrNull()

        val httpHost = (info?.host?.takeIf { it.isNotEmpty() } ?: fallbackHost)
        val httpPort = (info?.port?.takeIf { it > 0 } ?: fallbackPort) ?: 0
        val exclusionList: List<String> = (info?.exclusionList ?: emptyList<String>()).filterNotNull()

        return mapOf(
            "httpHost" to httpHost,
            "httpPort" to if (httpPort > 0) httpPort else null,
            "httpsHost" to httpHost,
            "httpsPort" to if (httpPort > 0) httpPort else null,
            "exclusionList" to exclusionList,
        )
    }
}
