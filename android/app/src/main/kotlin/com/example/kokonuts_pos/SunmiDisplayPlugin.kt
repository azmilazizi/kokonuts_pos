package com.example.kokonuts_pos

import android.app.Presentation
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Typeface
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

class SunmiDisplayPlugin(private val context: Context) {

    companion object {
        const val CHANNEL = "kokonuts/sunmi_display"
    }

    private var presentation: CustomerPresentation? = null
    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    fun registerWith(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSecondaryDisplay" -> {
                    val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
                    result.success(displays.isNotEmpty())
                }
                "setEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: true
                    if (enabled) {
                        ensurePresentation()
                        presentation?.showWelcome()
                    } else {
                        presentation?.dismiss()
                        presentation = null
                    }
                    result.success(null)
                }
                "init" -> {
                    initSecondaryDisplay()
                    result.success(null)
                }
                "showWelcome" -> {
                    ensurePresentation()
                    presentation?.showWelcome()
                    result.success(null)
                }
                "showOrder" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) {
                        ensurePresentation()
                        @Suppress("UNCHECKED_CAST")
                        presentation?.showOrder(
                            args["items"] as List<Map<String, Any>>,
                            (args["total"] as Number).toDouble(),
                            (args["subtotal"] as? Number)?.toDouble() ?: 0.0,
                            (args["totalDiscount"] as? Number)?.toDouble() ?: 0.0,
                            (args["cashbackAmount"] as? Number)?.toDouble() ?: 0.0,
                        )
                    }
                    result.success(null)
                }
                "showPayment" -> {
                    val total = (call.arguments as? Number)?.toDouble() ?: 0.0
                    ensurePresentation()
                    presentation?.showPayment(total)
                    result.success(null)
                }
                "showComplete" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    val totalPaid = (args?.get("totalPaid") as? Number)?.toDouble() ?: 0.0
                    val queueNumber = (args?.get("queueNumber") as? Number)?.toInt() ?: 0
                    ensurePresentation()
                    presentation?.showComplete(totalPaid, queueNumber)
                    result.success(null)
                }
                "updatePromoImage" -> {
                    val url = call.arguments as? String
                    ensurePresentation()
                    presentation?.updatePromoImage(url)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initSecondaryDisplay() {
        val displays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
        if (displays.isNotEmpty() && (presentation == null || !presentation!!.isShowing)) {
            try {
                presentation = CustomerPresentation(context, displays[0])
                presentation?.show()
            } catch (e: Exception) {
                presentation = null
            }
        }
    }

    private fun ensurePresentation() {
        if (presentation == null || !presentation!!.isShowing) {
            initSecondaryDisplay()
        }
    }
}

class CustomerPresentation(context: Context, display: Display) :
    Presentation(context, display) {

    private lateinit var twoColumnLayout: LinearLayout
    private lateinit var screenWelcome: LinearLayout
    private lateinit var screenOrder: LinearLayout
    private lateinit var screenPayment: LinearLayout
    private lateinit var screenComplete: LinearLayout
    private lateinit var itemsContainer: LinearLayout
    private lateinit var summaryContainer: LinearLayout
    private lateinit var summaryRows: LinearLayout
    private lateinit var tvOrderTotal: TextView
    private lateinit var tvPaymentAmount: TextView
    private lateinit var tvTotalPaid: TextView
    private lateinit var tvQueueNumber: TextView
    private lateinit var tvTime: TextView
    private lateinit var ivPromo: ImageView
    private lateinit var llPlaceholder: LinearLayout

    private val clockHandler = Handler(Looper.getMainLooper())
    private val clockRunnable = object : Runnable {
        override fun run() {
            updateClock()
            clockHandler.postDelayed(this, 30_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.customer_display)

        twoColumnLayout = findViewById(R.id.twoColumnLayout)
        screenWelcome = findViewById(R.id.screenWelcome)
        screenOrder = findViewById(R.id.screenOrder)
        screenPayment = findViewById(R.id.screenPayment)
        screenComplete = findViewById(R.id.screenComplete)
        itemsContainer = findViewById(R.id.itemsContainer)
        summaryContainer = findViewById(R.id.summaryContainer)
        summaryRows = findViewById(R.id.summaryRows)
        tvOrderTotal = findViewById(R.id.tvOrderTotal)
        tvPaymentAmount = findViewById(R.id.tvPaymentAmount)
        tvTotalPaid = findViewById(R.id.tvTotalPaid)
        tvQueueNumber = findViewById(R.id.tvQueueNumber)
        tvTime = findViewById(R.id.tvTime)
        ivPromo = findViewById(R.id.ivPromo)
        llPlaceholder = findViewById(R.id.llPlaceholder)

        // Start live clock immediately
        clockHandler.post(clockRunnable)
    }

    override fun onStop() {
        super.onStop()
        clockHandler.removeCallbacks(clockRunnable)
    }

    // ── Screen transitions ────────────────────────────────────────────────────

    fun showWelcome() = switchTo(screenWelcome)
    fun showPayment(total: Double) {
        switchTo(screenPayment)
        tvPaymentAmount.text = "RM ${String.format("%.2f", total)}"
    }

    fun showComplete(totalPaid: Double, queueNumber: Int = 0) {
        switchTo(screenComplete)
        tvTotalPaid.text = "RM ${String.format("%.2f", totalPaid)}"
        tvQueueNumber.text = if (queueNumber > 0) "$queueNumber" else "-"
    }

    fun showOrder(
        items: List<Map<String, Any>>,
        total: Double,
        subtotal: Double = 0.0,
        totalDiscount: Double = 0.0,
        cashbackAmount: Double = 0.0,
    ) {
        switchTo(screenOrder)

        itemsContainer.removeAllViews()
        for (item in items) {
            val hasDiscount = (item["hasDiscount"] as? Boolean) ?: false
            val lineTotal = (item["lineTotal"] as? Number)?.toDouble() ?: 0.0
            val lineTotalAfterDiscount = (item["lineTotalAfterDiscount"] as? Number)?.toDouble() ?: lineTotal
            itemsContainer.addView(buildItemRow(
                name = item["name"] as? String ?: "",
                qty = (item["qty"] as? Number)?.toInt() ?: 1,
                lineTotal = lineTotal,
                lineTotalAfterDiscount = lineTotalAfterDiscount,
                hasDiscount = hasDiscount,
            ))
            itemsContainer.addView(buildDivider())
        }

        // Summary section pinned above the footer
        summaryRows.removeAllViews()
        if (subtotal > 0) {
            summaryRows.addView(buildSummaryRow("Subtotal", "RM ${String.format("%.2f", subtotal)}", false))
            if (totalDiscount > 0) {
                summaryRows.addView(buildSummaryRow("Discount", "- RM ${String.format("%.2f", totalDiscount)}", true))
            }
            if (cashbackAmount > 0) {
                summaryRows.addView(buildSummaryRow("Cashback Redeem", "- RM ${String.format("%.2f", cashbackAmount)}", true))
            }
            summaryContainer.visibility = View.VISIBLE
        } else {
            summaryContainer.visibility = View.GONE
        }

        tvOrderTotal.text = "RM ${String.format("%.2f", total)}"
    }

    // ── Promo image ───────────────────────────────────────────────────────────

    fun updatePromoImage(url: String?) {
        if (url.isNullOrBlank()) {
            showPlaceholder()
            return
        }
        Thread {
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.doInput = true
                conn.connectTimeout = 8_000
                conn.readTimeout = 8_000
                conn.connect()
                val bitmap = BitmapFactory.decodeStream(conn.inputStream)
                conn.disconnect()
                clockHandler.post {
                    if (bitmap != null) {
                        ivPromo.setImageBitmap(bitmap)
                        ivPromo.visibility = View.VISIBLE
                        llPlaceholder.visibility = View.GONE
                    } else {
                        showPlaceholder()
                    }
                }
            } catch (e: Exception) {
                clockHandler.post { showPlaceholder() }
            }
        }.start()
    }

    private fun showPlaceholder() {
        ivPromo.visibility = View.GONE
        llPlaceholder.visibility = View.VISIBLE
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun switchTo(screen: LinearLayout) {
        screenWelcome.visibility = View.GONE
        screenOrder.visibility = View.GONE
        screenPayment.visibility = View.GONE
        screenComplete.visibility = View.GONE
        // complete screen is a full-screen overlay; hide/show the two-column layout accordingly
        twoColumnLayout.visibility = if (screen === screenComplete) View.GONE else View.VISIBLE
        screen.visibility = View.VISIBLE
    }

    private fun updateClock() {
        val cal = Calendar.getInstance()
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)
        val amPm = if (hour >= 12) "PM" else "AM"
        val hour12 = when {
            hour == 0 -> 12
            hour > 12 -> hour - 12
            else -> hour
        }
        tvTime.text = String.format("%d:%02d %s", hour12, minute, amPm)
    }

    private fun buildItemRow(
        name: String,
        qty: Int,
        lineTotal: Double,
        lineTotalAfterDiscount: Double = lineTotal,
        hasDiscount: Boolean = false,
    ): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.setMargins(0, 8, 0, 8) }

            addView(TextView(context).apply {
                text = "$name  ×$qty"
                textSize = 16f
                setTextColor(0xFF212121.toInt())
                layoutParams = LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })

            if (hasDiscount) {
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = android.view.Gravity.END
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    )
                    addView(TextView(context).apply {
                        text = "RM ${String.format("%.2f", lineTotal)}"
                        textSize = 13f
                        setTextColor(0xFF9E9E9E.toInt())
                        paintFlags = paintFlags or android.graphics.Paint.STRIKE_THRU_TEXT_FLAG
                        gravity = android.view.Gravity.END
                    })
                    addView(TextView(context).apply {
                        text = "RM ${String.format("%.2f", lineTotalAfterDiscount)}"
                        textSize = 16f
                        setTextColor(0xFFE67E22.toInt())
                        setTypeface(typeface, Typeface.BOLD)
                        gravity = android.view.Gravity.END
                    })
                })
            } else {
                addView(TextView(context).apply {
                    text = "RM ${String.format("%.2f", lineTotal)}"
                    textSize = 16f
                    setTextColor(0xFF212121.toInt())
                    setTypeface(typeface, Typeface.BOLD)
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    )
                })
            }
        }
    }

    private fun buildSummaryRow(label: String, value: String, isDeduction: Boolean): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.setMargins(0, 4, 0, 4) }
            addView(TextView(context).apply {
                text = label
                textSize = 13f
                setTextColor(0xFF9E9E9E.toInt())
                layoutParams = LinearLayout.LayoutParams(0,
                    LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
            addView(TextView(context).apply {
                text = value
                textSize = 13f
                setTextColor(if (isDeduction) 0xFFE67E22.toInt() else 0xFF9E9E9E.toInt())
            })
        }
    }

    private fun buildDivider(): View = View(context).apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 1
        ).also { it.setMargins(0, 2, 0, 2) }
        setBackgroundColor(0xFFEEEEEE.toInt())
    }
}
