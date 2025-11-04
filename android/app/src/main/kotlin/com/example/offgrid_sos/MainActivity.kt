package com.example.offgrid_sos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "wifi_direct"
    private val PERMISSION_CHANNEL = "nearby_permissions"
    private val EVENT_CHANNEL = "wifi_direct/events"
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
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
