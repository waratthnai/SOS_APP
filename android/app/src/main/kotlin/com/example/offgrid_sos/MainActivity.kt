package com.example.offgrid_sos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.net.Uri
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "wifi_direct"
    private val PERMISSION_CHANNEL = "nearby_permissions"
    private val EVENT_CHANNEL = "wifi_direct/events"
    private val FILE_CHANNEL = "com.example.offgrid_sos/files"
    private lateinit var wifiDirectChannel: WifiDirectChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiDirectChannel = WifiDirectChannel(this)

        // Permission channel for NEARBY_WIFI_DEVICES
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "hasNearbyWifiPermission" -> {
                    result.success(PermissionHelper.hasNearbyWifiDevicesPermission(this))
                }
                "requestNearbyWifiPermission" -> {
                    PermissionHelper.requestNearbyWifiDevicesPermission(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // File channel for reading Content URIs
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "readContentUri" -> {
                    val uriString = call.arguments as? String
                    if (uriString != null) {
                        try {
                            val uri = Uri.parse(uriString)
                            val inputStream = contentResolver.openInputStream(uri)
                            val buffer = ByteArrayOutputStream()
                            
                            inputStream?.use { input ->
                                val data = ByteArray(8192)
                                var count: Int
                                while (input.read(data).also { count = it } != -1) {
                                    buffer.write(data, 0, count)
                                }
                            }
                            
                            result.success(buffer.toByteArray())
                        } catch (e: Exception) {
                            result.error("READ_ERROR", "Failed to read content URI: ${e.message}", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "URI string is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "setDeviceName" -> {
                    val name = call.argument<String>("name")
                    if (name != null) {
                        wifiDirectChannel.setDeviceName(name)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Device name is required", null)
                    }
                }
                "discoverPeers" -> wifiDirectChannel.discoverPeers(call, result)
                "sendMessage" -> wifiDirectChannel.sendMessage(call, result)
                "stopDiscovery" -> wifiDirectChannel.stopDiscovery(call, result)
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    wifiDirectChannel.setEventSink(events)
                }
                override fun onCancel(arguments: Any?) {
                    wifiDirectChannel.setEventSink(null)
                }
            }
        )
    }
}
