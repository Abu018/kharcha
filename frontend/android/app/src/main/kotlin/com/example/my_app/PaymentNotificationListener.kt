package com.example.my_app

import android.app.Notification
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/**
 * Receives notifications once the user grants notification access in
 * Android settings. Only notifications from [PaymentNotifications.APPS] that
 * mention an amount are kept; everything else is ignored without being stored.
 */
class PaymentNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val app = PaymentNotifications.APPS[sbn.packageName] ?: return
        val notification = sbn.notification
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) {
            return
        }
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        val kept = PaymentNotifications.mentionsAmount("$title $text")
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            Log.d("PaymentNotification", "${if (kept) "kept" else "no amount"}: $app | $title | $text")
        }
        if (!kept) {
            return
        }
        val time = if (notification.`when` > 0) notification.`when` else sbn.postTime
        PaymentNotifications.add(this, PaymentNotifications.entry(sbn.packageName, app, title, text, time))
    }
}

/**
 * Payment notifications waiting to be uploaded. They are kept in shared
 * preferences because the listener runs even when Flutter is not, and are
 * removed once Dart acknowledges them.
 */
object PaymentNotifications {
    /** Package name to the name shown as the expense's bank. */
    val APPS = mapOf(
        "com.google.android.apps.nbu.paisa.user" to "Google Pay",
        "com.phonepe.app" to "PhonePe",
        "net.one97.paytm" to "Paytm",
        "in.org.npci.upiapp" to "BHIM",
        "com.dreamplug.androidapp" to "CRED",
        "com.mobikwik_new" to "MobiKwik",
        "com.sbi.upi" to "SBI",
        "com.sbi.lotusintouch" to "SBI",
        "com.snapwork.hdfc" to "HDFC Bank",
        "com.hdfcbank.android.now" to "HDFC Bank",
        "com.hdfcbank.payzapp" to "PayZapp",
        "com.csam.icici.bank.imobile" to "ICICI Bank",
        "com.axis.mobile" to "Axis Bank",
        "com.msf.kbank.mobile" to "Kotak Bank",
    )

    private const val PREFS = "payment_notifications"
    private const val KEY = "pending"
    private const val MAX_PENDING = 300

    private val amount = Regex("""(₹|\brs\.?|\binr)\s*[0-9]""", RegexOption.IGNORE_CASE)
    private val main = Handler(Looper.getMainLooper())

    /** Set while Flutter listens on `my_app/notifications/incoming`. */
    @Volatile
    var listener: ((Map<String, Any>) -> Unit)? = null

    fun mentionsAmount(text: String) = amount.containsMatchIn(text)

    /**
     * The ref depends on the app, the text and the time the app put on the
     * notification, so an update to the same notification is not saved twice.
     */
    fun entry(pkg: String, app: String, title: String, text: String, time: Long): Map<String, Any> {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$pkg|$title|$text|$time".toByteArray())
        val ref = "notif:" + digest.take(16).joinToString("") { "%02x".format(it) }
        return mapOf("ref" to ref, "app" to app, "title" to title, "text" to text, "date" to time)
    }

    @Synchronized
    fun add(context: Context, item: Map<String, Any>) {
        val items = read(context)
        if (items.any { it["ref"] == item["ref"] }) {
            return
        }
        items.add(item)
        write(context, items.takeLast(MAX_PENDING))
        listener?.let { send -> main.post { send(item) } }
    }

    /** Oldest first. */
    @Synchronized
    fun pending(context: Context): List<Map<String, Any>> =
        read(context).sortedBy { it["date"] as Long }

    @Synchronized
    fun remove(context: Context, refs: Collection<String>) {
        write(context, read(context).filter { it["ref"] !in refs })
    }

    private fun read(context: Context): MutableList<Map<String, Any>> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?: return mutableListOf()
        val array = try {
            JSONArray(raw)
        } catch (_: Exception) {
            return mutableListOf()
        }
        return (0 until array.length()).mapTo(mutableListOf()) { i ->
            val o = array.getJSONObject(i)
            mapOf(
                "ref" to o.getString("ref"),
                "app" to o.getString("app"),
                "title" to o.getString("title"),
                "text" to o.getString("text"),
                "date" to o.getLong("date"),
            )
        }
    }

    private fun write(context: Context, items: List<Map<String, Any>>) {
        val array = JSONArray()
        items.forEach { array.put(JSONObject(it)) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, array.toString()).apply()
    }
}
