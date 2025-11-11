package com.example.offgrid_sos

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pManager.Channel
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

class WifiDirectChannel(private val activity: Activity) {
    private val TAG = "WifiDirectChannel"
    private var eventSink: EventChannel.EventSink? = null
    private var wifiP2pManager: WifiP2pManager? = null
    private var channel: Channel? = null
    private val peers = mutableListOf<WifiP2pDevice>()
    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private val connectedClients = mutableListOf<Socket>() // 🔧 Track all connected clients
    private var isConnected = false // 🔧 Track connection status
    private var customDeviceName: String = "WiFi Device" // 🔧 Custom device name
    private val PORT = 8888

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    val isEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    Log.d(TAG, "📶 WiFi P2P state changed: ${if (isEnabled) "ENABLED ✅" else "DISABLED ❌"}")
                    
                    if (!isEnabled) {
                        Log.w(TAG, "⚠️ WiFi Direct is disabled! Please enable WiFi.")
                    }
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    Log.d(TAG, "👥 Peers changed - requesting peer list...")
                    // Request available peers from the wifi p2p manager
                    wifiP2pManager?.requestPeers(channel) { peerList: WifiP2pDeviceList? ->
                        if (peerList != null) {
                            val oldCount = peers.size
                            peers.clear()
                            peers.addAll(peerList.deviceList)
                            sendPeersToFlutter()
                            Log.d(TAG, "📊 Peers updated: $oldCount → ${peers.size}")
                            
                            if (peers.isNotEmpty()) {
                                peers.forEach { peer ->
                                    Log.d(TAG, "  📱 Found: ${peer.deviceName} (${peer.deviceAddress})")
                                }
                                
                                // 🔧 AUTO-CONNECT: เชื่อมต่อกับ peer ทุกตัวที่พบ (WiFi Direct รองรับ 1:many)
                                if (!isConnected) {
                                    peers.forEach { peer ->
                                        Log.d(TAG, "🔄 Auto-connecting to ${peer.deviceName}...")
                                        connectToPeer(peer) {
                                            Log.d(TAG, "✅ Auto-connected to ${peer.deviceName}")
                                        }
                                    }
                                }
                            } else {
                                Log.d(TAG, "  ℹ️ No peers found in range")
                            }
                        } else {
                            Log.w(TAG, "⚠️ Peer list is null")
                        }
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    Log.d(TAG, "📡 Connection status changed")
                    wifiP2pManager?.requestConnectionInfo(channel) { info: WifiP2pInfo? ->
                        if (info?.groupFormed == true) {
                            isConnected = true
                            Log.d(TAG, "✅ Group formed - Connection established")
                            Log.d(TAG, "   Group Owner: ${if (info.isGroupOwner) "ME" else info.groupOwnerAddress.hostAddress}")
                            
                            if (info.isGroupOwner) {
                                Log.d(TAG, "👑 I am group owner, starting server...")
                                startServer()
                                
                                // แจ้ง Flutter ว่า connected
                                Handler(Looper.getMainLooper()).post {
                                    eventSink?.success(mapOf(
                                        "type" to "connectionStatus",
                                        "isConnected" to true,
                                        "role" to "server"
                                    ))
                                }
                            } else {
                                Log.d(TAG, "📱 I am client, connecting to ${info.groupOwnerAddress.hostAddress}...")
                                connectToServer(info.groupOwnerAddress.hostAddress)
                                
                                // แจ้ง Flutter ว่า connected
                                Handler(Looper.getMainLooper()).post {
                                    eventSink?.success(mapOf(
                                        "type" to "connectionStatus",
                                        "isConnected" to true,
                                        "role" to "client",
                                        "serverAddress" to info.groupOwnerAddress.hostAddress
                                    ))
                                }
                            }
                        } else {
                            isConnected = false
                            Log.d(TAG, "❌ Group not formed - Disconnected")
                            
                            // แจ้ง Flutter ว่า disconnected
                            Handler(Looper.getMainLooper()).post {
                                eventSink?.success(mapOf(
                                    "type" to "connectionStatus",
                                    "isConnected" to false
                                ))
                            }
                        }
                    }
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE, WifiP2pDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    }
                    Log.d(TAG, "This device changed: ${device?.deviceName}")
                }
            }
        }
    }

    init {
        wifiP2pManager = activity.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        channel = wifiP2pManager?.initialize(activity, activity.mainLooper, null)
        
        if (wifiP2pManager == null) {
            Log.e(TAG, "❌ WifiP2pManager is NULL - WiFi Direct not available!")
        } else {
            Log.d(TAG, "✅ WifiP2pManager initialized successfully")
        }
        
        if (channel == null) {
            Log.e(TAG, "❌ Channel is NULL - initialization failed!")
        } else {
            Log.d(TAG, "✅ Channel initialized successfully")
        }
        
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        
        activity.registerReceiver(receiver, intentFilter)
        Log.d(TAG, "✅ WiFi Direct Channel initialized - Receiver registered")
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        Log.d(TAG, "Event sink ${if (sink != null) "connected" else "disconnected"}")
    }
    
    fun setDeviceName(name: String) {
        customDeviceName = name
        Log.d(TAG, "📝 Custom device name set to: $name")
    }

    fun discoverPeers(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "📡 discoverPeers() called")
        
        if (wifiP2pManager == null) {
            Log.e(TAG, "❌ Cannot discover - WifiP2pManager is null")
            result.error("MANAGER_NULL", "WiFi P2P Manager not available", null)
            return
        }
        
        if (channel == null) {
            Log.e(TAG, "❌ Cannot discover - Channel is null")
            result.error("CHANNEL_NULL", "WiFi P2P Channel not available", null)
            return
        }
        
        // 🔧 หยุด discovery เก่าก่อน (ป้องกัน busy)
        wifiP2pManager?.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Stopped previous discovery")
                // เพิ่ม delay เป็น 1000ms (1 วินาที) เพื่อให้ระบบพักผ่อน
                Handler(Looper.getMainLooper()).postDelayed({
                    startNewDiscovery(result)
                }, 1000)
            }
            
            override fun onFailure(reasonCode: Int) {
                Log.w(TAG, "⚠️ Failed to stop previous discovery (code: $reasonCode), trying to start anyway...")
                // เพิ่ม delay เป็น 1500ms เมื่อ stop ล้มเหลว
                Handler(Looper.getMainLooper()).postDelayed({
                    startNewDiscovery(result)
                }, 1500)
            }
        })
    }
    
    private fun startNewDiscovery(result: MethodChannel.Result) {
        Log.d(TAG, "🔍 Starting peer discovery...")
        Log.d(TAG, "📊 Current state: isConnected=$isConnected, peers.size=${peers.size}")
        
        wifiP2pManager?.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Peer discovery initiated successfully")
                Log.d(TAG, "⏳ Waiting for WIFI_P2P_PEERS_CHANGED_ACTION broadcast...")
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                val reason = when (reasonCode) {
                    WifiP2pManager.P2P_UNSUPPORTED -> "WiFi Direct not supported"
                    WifiP2pManager.BUSY -> "System busy"
                    WifiP2pManager.ERROR -> "Internal error"
                    else -> "Unknown error: $reasonCode"
                }
                Log.e(TAG, "❌ Peer discovery failed: $reason (code: $reasonCode)")
                
                // 🔧 ถ้า busy ให้ return success (ไม่ throw error) เพื่อให้ retry ได้
                if (reasonCode == WifiP2pManager.BUSY) {
                    Log.w(TAG, "⏸️ System busy, will retry later")
                    result.success(false) // ส่ง false แทน error
                } else {
                    result.error("DISCOVERY_FAILED", reason, null)
                }
            }
        })
    }

    fun stopDiscovery(call: MethodCall, result: MethodChannel.Result) {
        wifiP2pManager?.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                peers.clear()
                sendPeersToFlutter()
                closeConnections()
                Log.d(TAG, "Stopped peer discovery")
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                Log.e(TAG, "Failed to stop peer discovery: $reasonCode")
                result.error("STOP_FAILED", "Failed to stop discovery", null)
            }
        })
    }

    fun sendMessage(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>("message")
        val peerId = call.argument<String>("peerId")

        if (message == null) {
            result.error("INVALID_ARGS", "Message is required", null)
            return
        }

        // If peerId is specified, connect to that peer first
        if (peerId != null) {
            val peer = peers.find { it.deviceAddress == peerId }
            if (peer != null) {
                connectToPeer(peer) {
                    sendMessageToPeer(message)
                    result.success(true)
                }
            } else {
                result.error("PEER_NOT_FOUND", "Peer $peerId not found", null)
            }
        } else {
            // Broadcast to all connected peers
            sendMessageToPeer(message)
            result.success(true)
        }
    }

    private fun connectToPeer(device: WifiP2pDevice, onConnected: () -> Unit) {
        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
        }

        wifiP2pManager?.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection initiated to ${device.deviceName}")
                // Connection info will come via WIFI_P2P_CONNECTION_CHANGED_ACTION
                thread {
                    Thread.sleep(2000) // Wait for connection to establish
                    onConnected()
                }
            }

            override fun onFailure(reason: Int) {
                Log.e(TAG, "Connection failed: $reason")
            }
        })
    }

    private fun startServer() {
        thread {
            try {
                serverSocket = ServerSocket(PORT)
                Log.d(TAG, "Server socket started on port $PORT")
                
                while (true) {
                    val client = serverSocket?.accept()
                    Log.d(TAG, "Client connected: ${client?.inetAddress?.hostAddress}")
                    
                    thread {
                        handleClient(client)
                    }
                }
            } catch (e: IOException) {
                Log.e(TAG, "Server socket error: ${e.message}")
            }
        }
    }

    private fun connectToServer(hostAddress: String?) {
        if (hostAddress == null) {
            Log.e(TAG, "❌ Host address is null, cannot connect")
            return
        }
        
        thread {
            try {
                Log.d(TAG, "🔌 Connecting to server: $hostAddress:$PORT...")
                
                // 🔧 ใช้ constructor ที่รับ host และ port โดยตรง
                val socket = Socket()
                socket.connect(InetSocketAddress(hostAddress, PORT), 10000) // timeout 10 seconds
                
                clientSocket = socket
                isConnected = true
                Log.d(TAG, "✅ Connected to server: $hostAddress")
                
                // Start listening for messages
                handleClient(clientSocket)
            } catch (e: IOException) {
                Log.e(TAG, "❌ Client connection error: ${e.message}")
                e.printStackTrace()
                isConnected = false
                clientSocket?.close()
                clientSocket = null
            }
        }
    }

    private fun handleClient(socket: Socket?) {
        if (socket == null) return
        
        // 🔧 Track connection status
        isConnected = true
        connectedClients.add(socket)
        Log.d(TAG, "✅ Client connected from ${socket.inetAddress.hostAddress} - Total clients: ${connectedClients.size}")
        
        try {
            val inputStream: InputStream = socket.getInputStream()
            val buffer = ByteArray(1024)
            
            while (true) {
                val bytesRead = inputStream.read(buffer)
                if (bytesRead == -1) break
                
                val message = String(buffer, 0, bytesRead)
                Log.d(TAG, "📥 Received message: $message")
                
                // Send message to Flutter
                activity.runOnUiThread {
                    val data = mapOf(
                        "type" to "message",
                        "fromPeerId" to socket.inetAddress.hostAddress,
                        "body" to message
                    )
                    eventSink?.success(data)
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "❌ Error reading from socket: ${e.message}")
        } finally {
            connectedClients.remove(socket)
            socket.close()
            if (connectedClients.isEmpty() && clientSocket == null) {
                isConnected = false
            }
            Log.d(TAG, "🔌 Client disconnected - Remaining clients: ${connectedClients.size}")
        }
    }

    private fun sendMessageToPeer(message: String) {
        thread {
            // 🔧 ตรวจสอบ connection status ก่อนส่ง
            if (!isConnected) {
                Log.w(TAG, "⚠️ Cannot send message - not connected. isConnected=$isConnected")
                return@thread
            }
            
            var sent = false
            
            try {
                // 📤 ส่งไปยัง client socket (ถ้าเราเป็น client)
                clientSocket?.let { socket ->
                    try {
                        val outputStream: OutputStream = socket.getOutputStream()
                        outputStream.write(message.toByteArray())
                        outputStream.flush()
                        Log.d(TAG, "📤 Message sent (as client): $message")
                        sent = true
                    } catch (e: IOException) {
                        Log.e(TAG, "❌ Failed to send as client: ${e.message}")
                        clientSocket?.close()
                        clientSocket = null
                    }
                }
                
                // 📤 ส่งไปยังทุก connected clients (ถ้าเราเป็น server)
                val clientsToRemove = mutableListOf<Socket>()
                connectedClients.forEach { socket ->
                    try {
                        val outputStream: OutputStream = socket.getOutputStream()
                        outputStream.write(message.toByteArray())
                        outputStream.flush()
                        Log.d(TAG, "📤 Message sent (as server): $message")
                        sent = true
                    } catch (e: IOException) {
                        Log.e(TAG, "❌ Failed to send to client ${socket.inetAddress.hostAddress}: ${e.message}")
                        clientsToRemove.add(socket)
                    }
                }
                
                // ลบ clients ที่ disconnect ออก
                clientsToRemove.forEach { socket ->
                    connectedClients.remove(socket)
                    try {
                        socket.close()
                    } catch (e: IOException) {
                        // Ignore
                    }
                }
                
                if (!sent) {
                    Log.w(TAG, "⚠️ No active connection to send message")
                }
            } catch (e: IOException) {
                Log.e(TAG, "❌ Error sending message: ${e.message}")
            }
        }
    }

    private fun sendPeersToFlutter() {
        val peersList = peers.map { device ->
            mapOf(
                "id" to device.deviceAddress,
                "name" to (device.deviceName ?: device.deviceAddress)
            )
        }
        
        val data = mapOf(
            "type" to "peers",
            "peers" to peersList
        )
        
        activity.runOnUiThread {
            eventSink?.success(data)
            Log.d(TAG, "📤 Sent ${peers.size} peers to Flutter")
            if (peers.isNotEmpty()) {
                peers.forEach { peer ->
                    Log.d(TAG, "   • ${peer.deviceName ?: "Unknown"} (${peer.deviceAddress})")
                }
            }
        }
    }

    private fun closeConnections() {
        try {
            // ปิด client socket
            clientSocket?.close()
            clientSocket = null
            
            // ปิด connected clients ทั้งหมด
            connectedClients.forEach { socket ->
                try {
                    socket.close()
                } catch (e: IOException) {
                    Log.e(TAG, "Error closing client socket: ${e.message}")
                }
            }
            connectedClients.clear()
            
            // ปิด server socket
            serverSocket?.close()
            serverSocket = null
            
            isConnected = false
            Log.d(TAG, "🔌 Closed all connections")
        } catch (e: IOException) {
            Log.e(TAG, "❌ Error closing connections: ${e.message}")
        }
    }

    fun cleanup() {
        try {
            activity.unregisterReceiver(receiver)
            closeConnections()
            wifiP2pManager?.cancelConnect(channel, null)
            Log.d(TAG, "Cleanup completed")
        } catch (e: Exception) {
            Log.e(TAG, "Cleanup error: ${e.message}")
        }
    }
}
