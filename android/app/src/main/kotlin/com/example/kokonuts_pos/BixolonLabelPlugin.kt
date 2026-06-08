package com.example.kokonuts_pos

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import com.bixolon.labelprinter.BixolonLabelPrinter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter ↔ Bixolon SLP-DX220 Label Printer bridge (SDK v2.1.1, USB).
 *
 * Channel : kokonuts/bixolon_label
 * Methods : connect | printLabel | disconnect | isConnected
 *
 * Label : 40 mm wide × 30 mm tall, 203 DPI
 *   setWidth  : 40 × 8 = 320 dots  (across printhead)
 *   setLength : 30 × 8 = 240 dots  (feed direction), gap = 3 × 8 = 24 dots
 *
 * SDK constants (verified from bytecode):
 *   FONT_SIZE_12          = 51
 *   TEXT_ALIGNMENT_LEFT   = 70
 *   MEDIA_TYPE_GAP        = 71
 */
class BixolonLabelPlugin(private val context: Context) {

    companion object {
        const val CHANNEL = "kokonuts/bixolon_label"
        private val BIXOLON_VENDOR_IDS = setOf(5380, 1825) // 0x1504, 0x0721
        private const val CONNECT_TIMEOUT_MS = 6_000L
        private const val TAG = "BixolonLabel"
        // FONT_SIZE_8 at 1× on a 270-dot wide area (320 − 50): ~12 dots/char → 22 chars/line
        private const val MAX_LINE_CHARS = 22
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var printer: BixolonLabelPrinter? = null
    private var pendingConnectResult: MethodChannel.Result? = null

    // Background thread for USB print operations — keeps the main looper free
    // for the SDK's state-change callbacks.
    private val printThread = HandlerThread("BixolonPrint").also { it.start() }
    private val printHandler = Handler(printThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val sdkHandler = Handler(Looper.getMainLooper()) { msg ->
        if (msg.what == BixolonLabelPrinter.MESSAGE_STATE_CHANGE) {
            Log.d(TAG, "STATE_CHANGE arg1=${msg.arg1}")
            when (msg.arg1) {
                BixolonLabelPrinter.STATE_CONNECTED -> {
                    Log.d(TAG, "STATE_CONNECTED")
                    pendingConnectResult?.success(true)
                    pendingConnectResult = null
                }
                BixolonLabelPrinter.STATE_NONE -> {
                    // Fires after print() — normal USB SDK behaviour (bulk-transfer
                    // closes once the job is queued). Only treat as failure if
                    // a connect() call is still pending.
                    Log.d(TAG, "STATE_NONE")
                    pendingConnectResult?.error("CONNECT_FAILED", "Printer disconnected.", null)
                    pendingConnectResult = null
                    printer = null
                }
            }
        }
        true
    }

    fun registerWith(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> connect(result)
                "printLabel" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Expected label job args", null)
                        return@setMethodCallHandler
                    }
                    printHandler.post {
                        printLabel(
                            queueNumber = (args["queueNumber"] as? Int) ?: 0,
                            name        = args["name"]     as? String ?: "",
                            category    = args["category"] as? String ?: "",
                            modifier    = args["modifier"] as? String ?: "",
                            dateTime    = args["dateTime"] as? String ?: "",
                            itemIndex   = (args["itemIndex"]  as? Int) ?: 1,
                            totalItems  = (args["totalItems"] as? Int) ?: 1,
                            result      = result,
                        )
                    }
                }
                "disconnect" -> disconnect(result)
                "isConnected" -> result.success(printer?.isConnected() == true)
                else -> result.notImplemented()
            }
        }
    }

    private fun connect(result: MethodChannel.Result) {
        try {
            if (printer?.isConnected() == true) {
                result.success(true)
                return
            }

            val device = findBixolonDevice() ?: return result.error(
                "NO_DEVICE",
                "No Bixolon printer found. Check USB connection and try again.",
                null,
            )

            Log.d(TAG, "connect() device=${device.deviceName} vid=${device.vendorId} pid=${device.productId}")

            if (!usbManager.hasPermission(device)) return result.error(
                "NO_PERMISSION",
                "USB permission not granted. Go to Settings → USB Printers → Scan and accept the dialog.",
                null,
            )

            pendingConnectResult?.error("CANCELLED", "Replaced by new connect().", null)
            pendingConnectResult = result

            val p = BixolonLabelPrinter(context, sdkHandler, Looper.getMainLooper())
            printer = p
            p.connect(device)

            sdkHandler.postDelayed({
                if (pendingConnectResult != null) {
                    pendingConnectResult?.error("TIMEOUT", "Connection timed out.", null)
                    pendingConnectResult = null
                    printer?.disconnect()
                    printer = null
                }
            }, CONNECT_TIMEOUT_MS)

        } catch (e: Exception) {
            pendingConnectResult = null
            printer = null
            result.error("ERROR", "connect: ${e.message}", null)
        }
    }

    /**
     * Layout on a 30 mm × 40 mm label (240 × 320 dots at 203 DPI):
     *
     *   ┌────────────────────────────────────┐  (320 dots / 40 mm wide)
     *   │ 307                                │  y=5    queue number
     *   │ Banana Coconut Shake               │  y=28   item name
     *   │ Fruits                             │  y=51   category
     *   │ Normal Sweet                       │  y=74   modifier
     *   │ 2026.06.06 23:23               1/1 │  y=189  datetime (left) + count (right)
     *   └────────────────────────────────────┘  (240 dots / 30 mm tall)
     */
    private fun printLabel(
        queueNumber: Int,
        name: String,
        category: String,
        modifier: String,
        dateTime: String,
        itemIndex: Int,
        totalItems: Int,
        result: MethodChannel.Result,
    ) {
        val p = printer
        if (p == null || !p.isConnected()) {
            printer = null
            mainHandler.post { result.error("NOT_CONNECTED", "Call connect() before printLabel().", null) }
            return
        }

        Log.d(TAG, "printLabel() queue=$queueNumber name='$name'")

        try {
            p.initializePrinter()
            p.setPrintingType(BixolonLabelPrinter.PRINTING_TYPE_DIRECT_THERMAL)
            // 432 = full SLP-DX220 printhead width in dots. Setting the image buffer
            // to the physical maximum ensures x=0 maps to the true left edge of the
            // printhead rather than being offset by the printer centering a narrower
            // buffer. setMargin(0,0) clears any remaining hidden padding.
            p.setWidth(432)   // full SLP-DX220 printhead canvas (432 dots / ~54 mm)
            p.setMargin(0, 0)
            p.setLength(240, 24, BixolonLabelPrinter.MEDIA_TYPE_GAP, 0) // 30 mm feed
            p.clearBuffer()

            // Verified from SDK bytecode — actual signature (no rotation param):
            // drawText(data, x, y, fontSize, hMul, vMul, rightSpace, reverse, bold, italic, alignment)
            // alignment = TEXT_ALIGNMENT_LEFT = 70 is the LAST (11th) param.
            val font  = BixolonLabelPrinter.FONT_SIZE_8         // 49
            val left  = BixolonLabelPrinter.TEXT_ALIGNMENT_LEFT // 70
            val right = BixolonLabelPrinter.TEXT_ALIGNMENT_RIGHT // 76

            val x      = 55   // left offset
            val xEnd   = 350  // right edge of 40 mm label
            val lineH  = 20   // line height in dots for FONT_SIZE_8 at 1×
            val yFloor = 200  // bottom row reserved for date + count (label = 240 dots)

            var y = 5
            fun drawLine(text: String) {
                if (y < yFloor) {
                    p.drawText(text, x, y, font, 1, 1, 0, 0, false, false, left)
                    y += lineH
                }
            }

            drawLine(queueNumber.toString())
            wrapText(name, MAX_LINE_CHARS).forEach { drawLine(it) }
            if (modifier.isNotEmpty()) {
                modifier.split("\n").forEach { mod ->
                    wrapText("- $mod", MAX_LINE_CHARS).forEach { drawLine(it) }
                }
            }

            p.drawText(dateTime,                 x,    yFloor, font, 1, 1, 0, 0, false, false, left)
            p.drawText("$itemIndex/$totalItems", xEnd, yFloor, font, 1, 1, 0, 0, false, false, right)

            p.print(1, 1)
            Log.d(TAG, "print() sent")

            mainHandler.post { result.success(true) }
        } catch (e: Exception) {
            Log.e(TAG, "printLabel exception: ${e.message}", e)
            mainHandler.post { result.error("PRINT_FAILED", e.message, null) }
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        try { printer?.disconnect() } catch (_: Exception) { }
        printer = null
        result.success(true)
    }

    private fun findBixolonDevice(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { it.vendorId in BIXOLON_VENDOR_IDS }

    // Word-wraps text to at most maxChars per line, breaking on spaces where possible.
    private fun wrapText(text: String, maxChars: Int): List<String> {
        if (text.length <= maxChars) return listOf(text)
        val lines = mutableListOf<String>()
        var remaining = text.trim()
        while (remaining.length > maxChars) {
            val breakAt = remaining.lastIndexOf(' ', maxChars)
            val cut = if (breakAt > 0) breakAt else maxChars
            lines.add(remaining.substring(0, cut).trim())
            remaining = remaining.substring(cut).trim()
        }
        if (remaining.isNotEmpty()) lines.add(remaining)
        return lines
    }
}
