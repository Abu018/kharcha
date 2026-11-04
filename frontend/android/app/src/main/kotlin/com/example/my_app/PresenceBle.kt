package com.example.my_app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
import android.bluetooth.le.AdvertiseSettings.ADVERTISE_TX_POWER_HIGH
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Advertises the backend-issued temporary ID in BLE Service Data and scans
 * for other Kharcha advertisements. Dart owns the UUID and the ID; this
 * class only talks to the radio.
 */
class PresenceBle(private val activity: Activity, messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "my_app/ble")
    private val advertisements = EventChannel(messenger, "my_app/ble/advertisements")

    private var events: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingEnable: MethodChannel.Result? = null
    private var pendingAdvertise: MethodChannel.Result? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var scanner: BluetoothLeScanner? = null
    private var advertising = false
    private var scanning = false
    private var serviceUuid: ParcelUuid? = null

    init {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasPermission())
                "requestPermission" -> requestPermission(result)
                "isBluetoothOn" -> result.success(adapter()?.isEnabled == true)
                "enableBluetooth" -> enableBluetooth(result)
                "canAdvertise" -> result.success(canAdvertise())
                "startAdvertising" -> startAdvertising(
                    call.argument<String>("temporaryId"),
                    call.argument<String>("serviceUuid"),
                    result,
                )
                "stopAdvertising" -> {
                    stopAdvertising()
                    result.success(null)
                }
                "startScan" -> startScan(call.argument<String>("serviceUuid"), result)
                "stopScan" -> {
                    stopScan()
                    result.success(null)
                }
                "stop" -> {
                    stopAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        advertisements.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    this@PresenceBle.events = events
                }

                override fun onCancel(arguments: Any?) {
                    this@PresenceBle.events = null
                }
            },
        )
    }

    fun dispose() {
        stopAll()
        events = null
        methods.setMethodCallHandler(null)
        advertisements.setStreamHandler(null)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) {
            return false
        }
        pendingPermission?.success(hasPermission())
        pendingPermission = null
        return true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != ENABLE_REQUEST) {
            return false
        }
        pendingEnable?.success(resultCode == Activity.RESULT_OK && adapter()?.isEnabled == true)
        pendingEnable = null
        return true
    }

    private fun adapter(): BluetoothAdapter? {
        val manager = activity.getSystemService(BluetoothManager::class.java) ?: return null
        return manager.adapter
    }

    private fun granted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun hasPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_SCAN) &&
                granted(Manifest.permission.BLUETOOTH_ADVERTISE) &&
                granted(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            granted(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        activity.requestPermissions(permissions, PERMISSION_REQUEST)
    }

    @Suppress("DEPRECATION")
    private fun enableBluetooth(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            result.success(false)
            return
        }
        if (adapter.isEnabled) {
            result.success(true)
            return
        }
        pendingEnable?.success(false)
        pendingEnable = result
        try {
            activity.startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                ENABLE_REQUEST,
            )
        } catch (_: Exception) {
            pendingEnable = null
            result.success(false)
        }
    }

    private fun canAdvertise(): Boolean = adapter()?.bluetoothLeAdvertiser != null

    @SuppressLint("MissingPermission")
    private fun startAdvertising(hexId: String?, uuid: String?, result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("permission", "Bluetooth permission not granted", null)
            return
        }
        val bytes = hexToBytes(hexId)
        val parcel = parcelUuid(uuid)
        val advertiser = adapter()?.bluetoothLeAdvertiser
        if (bytes == null || parcel == null || advertiser == null) {
            result.error("advertise_failed", "Advertising is not available on this phone", null)
            return
        }
        stopAdvertising()
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()
        // Service Data only: UUID + 8 bytes stays inside a legacy 31-byte packet.
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceData(parcel, bytes)
            .build()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                if (advertiseCallback !== this) {
                    return
                }
                advertising = true
                pendingAdvertise?.success(null)
                pendingAdvertise = null
            }

            override fun onStartFailure(errorCode: Int) {
                if (advertiseCallback !== this) {
                    return
                }
                advertising = false
                val message = when (errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Advertisement is too large"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Already advertising"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Bluetooth advertiser failed"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "This phone cannot broadcast BLE"
                    else -> "Could not advertise ($errorCode)"
                }
                Log.w(TAG, message)
                pendingAdvertise?.error("advertise_failed", message, null)
                pendingAdvertise = null
            }
        }
        pendingAdvertise = result
        advertiseCallback = callback
        serviceUuid = parcel
        this.advertiser = advertiser
        try {
            advertiser.startAdvertising(settings, data, callback)
        } catch (e: Exception) {
            advertiseCallback = null
            pendingAdvertise = null
            advertising = false
            result.error("advertise_failed", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertising() {
        val callback = advertiseCallback
        advertiseCallback = null
        pendingAdvertise?.success(null)
        pendingAdvertise = null
        advertising = false
        val advertiser = this.advertiser ?: return
        if (callback != null) {
            try {
                advertiser.stopAdvertising(callback)
            } catch (_: Exception) {
            }
        }
        this.advertiser = null
    }

    @SuppressLint("MissingPermission")
    private fun startScan(uuid: String?, result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("permission", "Bluetooth permission not granted", null)
            return
        }
        val scanner = adapter()?.bluetoothLeScanner
        val parcel = parcelUuid(uuid)
        if (scanner == null || parcel == null) {
            result.error("scan_failed", "Bluetooth scanning is not available", null)
            return
        }
        stopScan()
        serviceUuid = parcel
        this.scanner = scanner
        val mask = ByteArray(8)
        val filter = ScanFilter.Builder()
            .setServiceData(parcel, ByteArray(8), mask)
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanning = true
        try {
            scanner.startScan(listOf(filter), settings, scanCallback)
            result.success(null)
        } catch (e: Exception) {
            try {
                scanner.startScan(null, settings, scanCallback)
                result.success(null)
            } catch (fallback: Exception) {
                scanning = false
                result.error("scan_failed", fallback.message ?: e.message, null)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        val scanner = scanner ?: return
        if (scanning) {
            try {
                scanner.stopScan(scanCallback)
            } catch (_: Exception) {
            }
        }
        scanning = false
        this.scanner = null
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            emit(result)
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach(::emit)
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            Log.w(TAG, "scan failed $errorCode")
        }
    }

    private fun emit(result: ScanResult) {
        val uuid = serviceUuid ?: return
        val data = result.scanRecord?.getServiceData(uuid) ?: return
        if (data.size != 8) {
            return
        }
        val id = data.joinToString("") { "%02x".format(it) }
        val payload = hashMapOf(
            "ephemeral_id" to id,
            "rssi" to result.rssi,
        )
        activity.runOnUiThread { events?.success(payload) }
    }

    private fun stopAll() {
        stopScan()
        stopAdvertising()
    }

    private fun parcelUuid(value: String?): ParcelUuid? = try {
        ParcelUuid(UUID.fromString(value ?: DEFAULT_UUID))
    } catch (_: IllegalArgumentException) {
        null
    }

    private fun hexToBytes(hex: String?): ByteArray? {
        val id = hex?.trim()?.lowercase() ?: return null
        if (id.length != 16) {
            return null
        }
        return try {
            ByteArray(8) { i -> id.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
        } catch (_: NumberFormatException) {
            null
        }
    }

    companion object {
        private const val TAG = "PresenceBle"
        const val PERMISSION_REQUEST = 4202
        const val ENABLE_REQUEST = 4203
        // Keep in sync with frontend/lib/ble/kharcha_uuid.dart
        private const val DEFAULT_UUID = "a7c4e91b-5d2f-4b8a-9e31-6f0c2d8a4b17"
    }
}
