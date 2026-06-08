package com.example.kokonuts_pos

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private lateinit var printerDiscovery: PrinterDiscoveryPlugin

    companion object {
        private const val REQUEST_BT_PERMISSIONS = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        SunmiDisplayPlugin(this).registerWith(messenger)
        printerDiscovery = PrinterDiscoveryPlugin(this).also { it.registerWith(messenger) }
        BixolonLabelPlugin(this).registerWith(messenger)
        BluetoothPrinterPlugin(this).registerWith(messenger)
    }

    override fun onStart() {
        super.onStart()
        requestBluetoothPermissionsIfNeeded()
    }

    // BLUETOOTH_CONNECT is a runtime permission on Android 12+ (API 31+).
    // Without it, bondedDevices throws SecurityException and returns empty.
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

    // Samsung devices sometimes leave the IME in a "hasWindowFocus=false,
    // mHasImeFocus=true" state when a Flutter route/dialog takes focus.
    // Clearing the focused view on focus loss resets that state and prevents
    // the subsequent ANR / touch-event blackhole.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) currentFocus?.clearFocus()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::printerDiscovery.isInitialized) printerDiscovery.dispose()
    }
}
