package com.example.kokonuts_pos

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class BluetoothPrinterPlugin(private val context: Context) {

    companion object {
        const val CHANNEL = "kokonuts/bt_printer"
        // Serial Port Profile UUID — understood by all Classic BT receipt printers.
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    fun registerWith(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "print" -> {
                    val address = call.argument<String>("address")
                    val data = call.argument<ByteArray>("data")
                    if (address == null || data == null) {
                        result.error("INVALID_ARGS", "address and data are required", null)
                        return@setMethodCallHandler
                    }
                    // RFCOMM is blocking — run on a background thread.
                    Thread {
                        try {
                            sendToPrinter(address, data)
                            result.success(null)
                        } catch (e: SecurityException) {
                            result.error("PERMISSION", e.message, null)
                        } catch (e: IOException) {
                            result.error("IO_ERROR", e.message, null)
                        } catch (e: Exception) {
                            result.error("PRINT_ERROR", e.message, null)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sendToPrinter(address: String, data: ByteArray) {
        val adapter: BluetoothAdapter =
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

        val device = adapter.getRemoteDevice(address)
        adapter.cancelDiscovery() // discovery interferes with RFCOMM throughput

        var socket: BluetoothSocket? = null
        try {
            socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            socket.connect()
            socket.outputStream.write(data)
            socket.outputStream.flush()
            // Small delay so the printer finishes processing before we close.
            Thread.sleep(600)
        } finally {
            try { socket?.close() } catch (_: IOException) {}
        }
    }
}
