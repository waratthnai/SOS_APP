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
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

/// ข้อมูลไฟล์ที่กำลังรับอยู่ (ต่อ socket หนึ่งตัว)
private class IncomingFile(
    val name: String,
    val size: Long,
    val path: String,
    val out: FileOutputStream,
    var written: Long = 0
)

class WifiDirectChannel(private val activity: Activity) {
    private val TAG = "WifiDirectChannel"
    private var eventSink: EventChannel.EventSink? = null
    private var wifiP2pManager: WifiP2pManager? = null
    private var channel: Channel? = null
    private val peers = mutableListOf<WifiP2pDevice>()
    private var lastEmittedPeerAddresses: Set<String> = emptySet()
    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private val connectedClients = mutableListOf<Socket>() // 🔧 Track all connected clients
    private var isConnected = false // 🔧 Track connection status
    private var customDeviceName: String = "WiFi Device" // 🔧 Custom device name
    private val PORT = 8888

    // 📦 Framed wire protocol: [1 byte type][4 byte length BE][payload]
    // ทำให้แยกข้อความ/ไฟล์บน stream เดียวกันได้แน่นอน ไม่พึ่ง buffer ขนาดคงที่แบบเดิม
    private val FRAME_TEXT = 1
    private val FRAME_FILE_META = 2
    private val FRAME_FILE_DATA = 3

    // ไฟล์ที่กำลังรับอยู่ ต่อ socket (รองรับหลาย client พร้อมกัน)
    private val incomingFiles = mutableMapOf<Socket, IncomingFile>()

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
                Handler(Looper.getMainLooper()).postDelayed({
                    startNewDiscovery(result)
                }, 300)
            }

            override fun onFailure(reasonCode: Int) {
                Log.w(TAG, "⚠️ Failed to stop previous discovery (code: $reasonCode), trying to start anyway...")
                Handler(Looper.getMainLooper()).postDelayed({
                    startNewDiscovery(result)
                }, 500)
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
                lastEmittedPeerAddresses = emptySet()
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
            val input = DataInputStream(socket.getInputStream())

            while (true) {
                val type = input.readByte().toInt()
                val length = input.readInt()
                val payload = ByteArray(length)
                input.readFully(payload)

                when (type) {
                    FRAME_TEXT -> {
                        val message = String(payload, Charsets.UTF_8)
                        Log.d(TAG, "📥 Received message: $message")
                        activity.runOnUiThread {
                            eventSink?.success(mapOf(
                                "type" to "message",
                                "fromPeerId" to socket.inetAddress.hostAddress,
                                "body" to message
                            ))
                        }
                    }
                    FRAME_FILE_META -> {
                        try {
                            val meta = JSONObject(String(payload, Charsets.UTF_8))
                            // sanitize ชื่อไฟล์ที่ peer ส่งมา ป้องกัน path traversal (เช่น "../../shared_prefs/x.xml")
                            val rawName = meta.getString("name")
                            val name = File(rawName).name.ifEmpty { "received_file" }
                            val size = meta.getLong("size")
                            val dir = File(activity.cacheDir, "wifi_direct_received")
                            if (!dir.exists()) dir.mkdirs()
                            val destPath = "${dir.path}/${System.currentTimeMillis()}_$name"
                            incomingFiles[socket] = IncomingFile(name, size, destPath, FileOutputStream(destPath))
                            Log.d(TAG, "📋 รับ metadata ไฟล์: $name ($size bytes)")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Parse file metadata ล้มเหลว: ${e.message}")
                        }
                    }
                    FRAME_FILE_DATA -> {
                        val state = incomingFiles[socket]
                        if (state == null) {
                            Log.w(TAG, "⚠️ ได้รับ file data แต่ไม่มี metadata มาก่อน - ข้าม")
                        } else {
                            state.out.write(payload)
                            state.written += payload.size
                            if (state.written >= state.size) {
                                state.out.flush()
                                state.out.close()
                                incomingFiles.remove(socket)
                                Log.d(TAG, "✅ รับไฟล์เสร็จสมบูรณ์: ${state.path} (${state.written} bytes)")
                                activity.runOnUiThread {
                                    eventSink?.success(mapOf(
                                        "type" to "file",
                                        "fromPeerId" to socket.inetAddress.hostAddress,
                                        "filePath" to state.path,
                                        "name" to state.name
                                    ))
                                }
                            }
                        }
                    }
                    else -> Log.w(TAG, "⚠️ Unknown frame type: $type")
                }
            }
        } catch (e: EOFException) {
            // ปลายทางปิด socket ตามปกติ
        } catch (e: IOException) {
            Log.e(TAG, "❌ Error reading from socket: ${e.message}")
        } finally {
            connectedClients.remove(socket)
            incomingFiles.remove(socket)?.out?.let { out ->
                try { out.close() } catch (_: IOException) {}
            }
            socket.close()
            if (connectedClients.isEmpty() && clientSocket == null) {
                isConnected = false
            }
            Log.d(TAG, "🔌 Client disconnected - Remaining clients: ${connectedClients.size}")
        }
    }

    /// เขียน frame หนึ่งชุดลง socket ที่ระบุ คืนค่า true ถ้าสำเร็จ
    private fun writeFrame(socket: Socket, type: Int, payload: ByteArray): Boolean {
        return try {
            val out = DataOutputStream(socket.getOutputStream())
            out.writeByte(type)
            out.writeInt(payload.size)
            out.write(payload)
            out.flush()
            true
        } catch (e: IOException) {
            Log.e(TAG, "❌ writeFrame failed (${socket.inetAddress?.hostAddress}): ${e.message}")
            false
        }
    }

    /// ส่ง frame ไปยังทุก socket ที่เชื่อมต่ออยู่ (client socket ของเรา + connected clients ฝั่ง server)
    /// คืนค่า true ถ้าส่งสำเร็จไปยังอย่างน้อยหนึ่งปลายทาง
    private fun sendFrameToPeers(type: Int, payload: ByteArray): Boolean {
        var sent = false

        clientSocket?.let { socket ->
            if (writeFrame(socket, type, payload)) {
                sent = true
            } else {
                try { socket.close() } catch (_: IOException) {}
                clientSocket = null
            }
        }

        val clientsToRemove = mutableListOf<Socket>()
        connectedClients.forEach { socket ->
            if (writeFrame(socket, type, payload)) {
                sent = true
            } else {
                clientsToRemove.add(socket)
            }
        }
        clientsToRemove.forEach { socket ->
            connectedClients.remove(socket)
            try { socket.close() } catch (_: IOException) {}
        }

        return sent
    }

    private fun sendMessageToPeer(message: String) {
        thread {
            // 🔧 ตรวจสอบ connection status ก่อนส่ง
            if (!isConnected) {
                Log.w(TAG, "⚠️ Cannot send message - not connected. isConnected=$isConnected")
                return@thread
            }

            val sent = sendFrameToPeers(FRAME_TEXT, message.toByteArray(Charsets.UTF_8))
            if (sent) {
                Log.d(TAG, "📤 Message sent: $message")
            } else {
                Log.w(TAG, "⚠️ No active connection to send message")
            }
        }
    }

    /// ส่งไฟล์จริงผ่าน socket: ส่ง metadata (ชื่อ+ขนาด) ก่อน แล้วค่อยส่ง binary แบบ chunk
    fun sendFile(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }

        thread {
            try {
                if (!isConnected) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("NOT_CONNECTED", "ยังไม่ได้เชื่อมต่อกับ peer", null)
                    }
                    return@thread
                }

                val file = File(filePath)
                if (!file.exists()) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("FILE_NOT_FOUND", "File not found: $filePath", null)
                    }
                    return@thread
                }

                val name = file.name
                val size = file.length()
                val meta = JSONObject().apply {
                    put("name", name)
                    put("size", size)
                }
                sendFrameToPeers(FRAME_FILE_META, meta.toString().toByteArray(Charsets.UTF_8))

                val chunkSize = 64 * 1024
                val buffer = ByteArray(chunkSize)
                file.inputStream().use { input ->
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        val chunk = if (read == buffer.size) buffer else buffer.copyOf(read)
                        sendFrameToPeers(FRAME_FILE_DATA, chunk)
                    }
                }

                Log.d(TAG, "✅ ส่งไฟล์เสร็จสมบูรณ์: $name ($size bytes)")
                Handler(Looper.getMainLooper()).post { result.success(true) }
            } catch (e: Exception) {
                Log.e(TAG, "❌ sendFile failed: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("SEND_FILE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun sendPeersToFlutter() {
        val currentAddresses = peers.map { it.deviceAddress }.toSet()
        if (currentAddresses == lastEmittedPeerAddresses) {
            Log.d(TAG, "⏭️ Peer list unchanged (${peers.size}), skipping emit")
            return
        }
        lastEmittedPeerAddresses = currentAddresses

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
            Log.d(TAG, "📤 Peers changed → sent ${peers.size} peers to Flutter")
            peers.forEach { peer ->
                Log.d(TAG, "   • ${peer.deviceName ?: "Unknown"} (${peer.deviceAddress})")
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
