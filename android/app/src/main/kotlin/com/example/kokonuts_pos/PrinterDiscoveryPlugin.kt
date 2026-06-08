package com.example.kokonuts_pos

import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PrinterDiscoveryPlugin(private val context: Context) {

    companion object {
        const val CHANNEL = "kokonuts/printer_discovery"
        private const val ACTION_USB_PERMISSION =
            "com.example.kokonuts_pos.USB_PERMISSION"

        // Common receipt-printer vendor IDs for friendly display names.
        private val KNOWN_VENDORS = mapOf(
            0x0416 to "Winbond",
            0x04B8 to "Epson",
            0x0519 to "Star Micronics",
            0x067B to "Prolific",
            0x0721 to "Bixolon",
            0x0A5F to "Zebra",
            0x0FE6 to "Sunmi",
            0x1504 to "Bixolon",
            0x154F to "SNBC",
            0x1659 to "Rongta",
            0x20D1 to "Citizen",
            0x28E9 to "Gprinter",
            0x6868 to "Sewoo",
            0x0483 to "STMicroelectronics",
        )
    }

    // Devices captured via USB_DEVICE_ATTACHED broadcast while the app is running.
    private val usbEventCache = mutableMapOf<String, UsbDevice>()

    // Receives the result of UsbManager.requestPermission().
    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != ACTION_USB_PERMISSION) return
            // Permission was either granted or denied — no further action needed
            // here; the next scanUsb() call will reflect hasPermission() correctly.
        }
    }

    // Receives USB attach/detach events at runtime and immediately asks for
    // permission on any newly attached device.
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            device ?: return
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    usbEventCache[device.deviceName] = device
                    requestPermissionIfNeeded(device)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED ->
                    usbEventCache.remove(device.deviceName)
            }
        }
    }

    fun registerWith(messenger: BinaryMessenger) {
        // Register USB attach/detach receiver.
        val usbFilter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        // Register permission-result receiver.
        val permFilter = IntentFilter(ACTION_USB_PERMISSION)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(usbReceiver, usbFilter, Context.RECEIVER_NOT_EXPORTED)
                context.registerReceiver(usbPermissionReceiver, permFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(usbReceiver, usbFilter)
                context.registerReceiver(usbPermissionReceiver, permFilter)
            }
        } catch (_: Exception) {}

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanBluetooth" -> result.success(scanBluetooth())
                "scanUsb" -> result.success(scanUsb())
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        try { context.unregisterReceiver(usbReceiver) } catch (_: Exception) {}
        try { context.unregisterReceiver(usbPermissionReceiver) } catch (_: Exception) {}
    }

    // ── Bluetooth ─────────────────────────────────────────────────────────────

    private fun scanBluetooth(): List<Map<String, String>> {
        return try {
            val adapter: BluetoothAdapter =
                (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
                    ?.adapter ?: return emptyList()
            if (!adapter.isEnabled) return emptyList()

            adapter.bondedDevices.map { device: BluetoothDevice ->
                val name = try { device.name } catch (_: Exception) { null }
                mapOf(
                    "name" to (name ?: "Unknown"),
                    "address" to device.address,
                    "type" to when (device.type) {
                        BluetoothDevice.DEVICE_TYPE_CLASSIC -> "Classic"
                        BluetoothDevice.DEVICE_TYPE_LE -> "BLE"
                        BluetoothDevice.DEVICE_TYPE_DUAL -> "Dual"
                        else -> "Unknown"
                    },
                )
            }
        } catch (_: SecurityException) { emptyList() }
        catch (_: Exception) { emptyList() }
    }

    // ── USB ───────────────────────────────────────────────────────────────────

    private fun scanUsb(): List<Map<String, String>> {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            ?: return emptyList()

        // Merge currently enumerated devices with runtime-cached ones.
        val merged = mutableMapOf<String, UsbDevice>()
        usbManager.deviceList.forEach { (_, d) -> merged[d.deviceName] = d }
        usbEventCache.forEach { (k, d) -> merged[k] = d }

        // Request permission for any device that doesn't have it yet.
        // The dialog is shown once per device; subsequent calls are no-ops if
        // the user already approved or denied.
        merged.values.forEach { requestPermissionIfNeeded(it) }

        return merged.values.mapNotNull { device ->
            try {
                val vid = device.vendorId
                val pid = device.productId
                val vidHex = vid.toString(16).uppercase().padStart(4, '0')
                val pidHex = pid.toString(16).uppercase().padStart(4, '0')

                // productName / manufacturerName require USB permission on API 26+.
                val productName = try { device.productName } catch (_: Exception) { null }
                val mfrName = try { device.manufacturerName } catch (_: Exception) { null }

                val displayName = productName
                    ?: KNOWN_VENDORS[vid]?.let { "$it Printer" }
                    ?: "USB Device $vidHex:$pidHex"
                val detail = mfrName
                    ?: KNOWN_VENDORS[vid]
                    ?: "VID:$vidHex  PID:$pidHex"

                mapOf(
                    "name" to displayName,
                    "manufacturer" to detail,
                    "vendorId" to vid.toString(),
                    "productId" to pid.toString(),
                    "deviceName" to device.deviceName,
                    "deviceClass" to device.deviceClass.toString(),
                    "hasPermission" to usbManager.hasPermission(device).toString(),
                )
            } catch (_: Exception) { null }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun requestPermissionIfNeeded(device: UsbDevice) {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            ?: return
        if (usbManager.hasPermission(device)) return

        val intent = Intent(ACTION_USB_PERMISSION).apply {
            setPackage(context.packageName) // required on Android 12+
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            device.deviceId,
            intent,
            flags,
        )
        try {
            usbManager.requestPermission(device, pendingIntent)
        } catch (_: Exception) {}
    }
}
