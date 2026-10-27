package com.example.my_app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Exposes the SMS inbox to Dart so bank and UPI messages can be turned into
 * expenses:
 * - `my_app/sms` (method channel): permissions, reading the inbox, and
 *   remembering how far the last sync got.
 * - `my_app/sms/incoming` (event channel): SMS received while the app runs.
 * - `my_app/notifications` (method channel): notification access and the
 *   payment notifications [PaymentNotificationListener] has queued.
 * - `my_app/notifications/incoming` (event channel): payment notifications
 *   posted while the app runs.
 */
class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "my_app/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeclared" -> result.success(smsPermissionDeclared())
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> requestSmsPermission(result)
                "readInbox" -> {
                    if (!hasSmsPermission()) {
                        result.error("permission", "SMS permission not granted", null)
                        return@setMethodCallHandler
                    }
                    val since = call.argument<Number>("since")?.toLong() ?: 0L
                    val limit = call.argument<Number>("limit")?.toInt() ?: 200
                    Thread {
                        try {
                            val messages = readInbox(since, limit)
                            runOnUiThread { result.success(messages) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("read_failed", e.message, null) }
                        }
                    }.start()
                }
                "getLastSync" -> {
                    val key = call.argument<String>("key") ?: ""
                    val p = prefs()
                    result.success(if (p.contains(key)) p.getLong(key, 0L) else null)
                }
                "setLastSync" -> {
                    val key = call.argument<String>("key") ?: ""
                    val value = call.argument<Number>("value")?.toLong() ?: 0L
                    prefs().edit().putLong(key, value).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "my_app/sms/incoming").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    registerSmsReceiver(events)
                }

                override fun onCancel(arguments: Any?) {
                    unregisterSmsReceiver()
                }
            },
        )

        MethodChannel(messenger, "my_app/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasNotificationAccess())
                "openSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "pending" -> result.success(PaymentNotifications.pending(this))
                "acknowledge" -> {
                    PaymentNotifications.remove(this, call.argument<List<String>>("refs").orEmpty())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "my_app/notifications/incoming").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    PaymentNotifications.listener = { events.success(it) }
                }

                override fun onCancel(arguments: Any?) {
                    PaymentNotifications.listener = null
                }
            },
        )
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        PaymentNotifications.listener = null
        super.onDestroy()
    }

    private fun listenerComponent() = ComponentName(this, PaymentNotificationListener::class.java)

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        val me = listenerComponent()
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
    }

    /** Opens this app's notification access page, or the full list where that is not available. */
    private fun openNotificationSettings() {
        val list = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                listenerComponent().flattenToString(),
            )
        } else {
            list
        }
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            startActivity(list)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQUEST) {
            pendingPermissionResult?.success(hasSmsPermission())
            pendingPermissionResult = null
        }
    }

    private fun prefs(): SharedPreferences =
        getSharedPreferences("auto_detect", Context.MODE_PRIVATE)

    /** False when the manifest leaves the SMS permissions out (Play builds). */
    @Suppress("DEPRECATION")
    private fun smsPermissionDeclared(): Boolean {
        val requested = packageManager
            .getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions ?: return false
        return Manifest.permission.READ_SMS in requested &&
            Manifest.permission.RECEIVE_SMS in requested
    }

    private fun hasSmsPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
            SMS_PERMISSION_REQUEST,
        )
    }

    private fun readInbox(since: Long, limit: Int): List<Map<String, Any>> {
        val messages = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { cursor ->
            val addressCol = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyCol = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateCol = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (cursor.moveToNext() && messages.size < limit) {
                val address = cursor.getString(addressCol) ?: ""
                val body = cursor.getString(bodyCol) ?: ""
                messages.add(message(address, body, cursor.getLong(dateCol)))
            }
        }
        return messages
    }

    private fun registerSmsReceiver(events: EventChannel.EventSink) {
        unregisterSmsReceiver()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
                // Long messages arrive split into parts.
                parts.groupBy { it.originatingAddress ?: "" }.forEach { (address, group) ->
                    val body = group.joinToString("") { it.messageBody ?: "" }
                    events.success(message(address, body, System.currentTimeMillis()))
                }
            }
        }
        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        smsReceiver = receiver
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
            }
        }
        smsReceiver = null
    }

    /**
     * The ref only depends on sender and text, so the same SMS seen live and
     * later in the inbox maps to the same expense.
     */
    private fun message(address: String, body: String, date: Long): Map<String, Any> {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("${address.trim().uppercase()}|$body".toByteArray())
        val ref = "sms:" + digest.take(16).joinToString("") { "%02x".format(it) }
        return mapOf("ref" to ref, "address" to address, "body" to body, "date" to date)
    }

    companion object {
        private const val SMS_PERMISSION_REQUEST = 4201
    }
}
