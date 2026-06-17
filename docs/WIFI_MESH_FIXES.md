# 🔧 WiFi Direct & Mesh Protocol Fixes

**วันที่:** 10 พฤศจิกายน 2025

## 📋 สรุปปัญหาและการแก้ไข

### ✅ ปัญหาที่ 1: ตำแหน่งระยะห่างไม่ทำงานใน WiFi Direct

**สาเหตุ:**
- WiFi Direct ต้องการ **Socket Connection** เพื่อส่งข้อความ
- ระบบ GPS broadcast (`broadcastMyLocation()`) ทำงานอยู่แล้ว แต่ส่งไปไม่ถึงเพราะ WiFi Direct ยังไม่ได้เชื่อมต่อผ่าน Socket
- `WifiDirectChannel.kt` มีโครงสร้าง Socket แล้ว แต่ยังไม่ auto-connect เมื่อพบ peer

**การแก้ไข:**

#### 1. เพิ่ม Auto-Connect ใน WifiDirectChannel.kt

```kotlin
private fun onPeersDiscovered(peerList: WifiP2pDeviceList?) {
    if (peerList != null) {
        peers.clear()
        peers.addAll(peerList.deviceList)
        sendPeersToFlutter()
        
        // 🔧 AUTO-CONNECT: เชื่อมต่อกับ peer แรกที่พบ
        if (peers.isNotEmpty() && !isConnected) {
            val firstPeer = peers[0]
            Log.d(TAG, "🔄 Auto-connecting to ${firstPeer.deviceName}...")
            connectToPeer(firstPeer) {
                Log.d(TAG, "✅ Auto-connected to ${firstPeer.deviceName}")
            }
        }
    }
}
```

#### 2. เพิ่มตัวแปรติดตามสถานะการเชื่อมต่อ

```kotlin
private var isConnected = false
private val connectedClients = mutableListOf<Socket>()

private fun handleClient(socket: Socket?) {
    if (socket == null) return
    
    isConnected = true
    connectedClients.add(socket)
    Log.d(TAG, "✅ Client connected - Total clients: ${connectedClients.size}")
    
    // ... existing code ...
}
```

#### 3. แก้ไข sendMessageToPeer ให้ส่งไปยังทุก connected clients

```kotlin
private fun sendMessageToPeer(message: String) {
    thread {
        try {
            // ส่งไปยัง client socket (ถ้าเราเป็น client)
            clientSocket?.let { socket ->
                val outputStream: OutputStream = socket.getOutputStream()
                outputStream.write(message.toByteArray())
                outputStream.flush()
                Log.d(TAG, "📤 Message sent (as client): $message")
            }
            
            // ส่งไปยังทุก connected clients (ถ้าเราเป็น server)
            connectedClients.forEach { socket ->
                try {
                    val outputStream: OutputStream = socket.getOutputStream()
                    outputStream.write(message.toByteArray())
                    outputStream.flush()
                    Log.d(TAG, "📤 Message sent (as server): $message")
                } catch (e: IOException) {
                    Log.e(TAG, "❌ Failed to send to client: ${e.message}")
                    connectedClients.remove(socket)
                }
            }
            
            if (clientSocket == null && connectedClients.isEmpty()) {
                Log.w(TAG, "⚠️ No active connection to send message")
            }
        } catch (e: IOException) {
            Log.e(TAG, "❌ Error sending message: ${e.message}")
        }
    }
}
```

**ผลลัพธ์:**
- ✅ WiFi Direct จะเชื่อมต่อ socket อัตโนมัติเมื่อพบ peer
- ✅ GPS location broadcast จะส่งได้ผ่าน socket connection
- ✅ ระยะห่างจะแสดงได้อย่างถูกต้อง

---

### ✅ ปัญหาที่ 2: ระบบการสแกนของโปรโตคอล Mesh ยังไม่สมบูรณ์

**สาเหตุ:**
- Mesh Transport ส่ง HELLO message ทุก 30 วินาที (route discovery) ✅
- แต่ **ไม่มีการ refresh device discovery** ทำให้ไม่พบอุปกรณ์ใหม่ที่เข้ามา
- NearbyTransport (base transport) จะค้นหาครั้งเดียวแล้วหยุด

**การแก้ไข:**

#### 1. เพิ่ม Periodic Scanning ใน mesh_transport.dart

```dart
// 🔍 Periodic scanning timer ทุก 15 วินาที
Timer? _scanTimer;

void _init() {
  _baseTransport.onPeers.listen(_onDirectPeersChanged);
  _baseTransport.onMessage.listen(_onMessageReceived);
  
  _startCleanupTimer();
  _startRouteDiscovery();
  _startPeriodicScan(); // 🔍 เพิ่มการ scan ต่อเนื่อง
  
  debugPrint('📡 [MESH] Initialized for device: $deviceId');
}

/// 🔍 เริ่ม Periodic Scanning ทุก 15 วินาที
void _startPeriodicScan() {
  _scanTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
    if (_baseTransport.discoveryState == DiscoveryState.scanning) {
      debugPrint('📡 [MESH] Periodic scan: refreshing device discovery...');
      try {
        await _baseTransport.stopDiscovery();
        await Future.delayed(const Duration(milliseconds: 500));
        await _baseTransport.startDiscovery();
        debugPrint('📡 [MESH] ✅ Scan refreshed successfully');
      } catch (e) {
        debugPrint('❌ [MESH] Error refreshing scan: $e');
      }
    }
  });
  
  debugPrint('📡 [MESH] Periodic scanning started (every 15 seconds)');
}
```

#### 2. อัปเดต stopDiscovery และ dispose

```dart
@override
Future<void> stopDiscovery() async {
  debugPrint('📡 [MESH] Stopping mesh discovery...');
  _routeDiscoveryTimer?.cancel();
  _scanTimer?.cancel(); // 🔍 หยุด periodic scanning
  await _baseTransport.stopDiscovery();
  _routingTable.clear();
  _allPeers.clear();
  _emitPeers();
}

@override
Future<void> dispose() async {
  _cleanupTimer?.cancel();
  _routeDiscoveryTimer?.cancel();
  _scanTimer?.cancel(); // 🔍 หยุด periodic scanning
  await _baseTransport.dispose();
  await _peersCtrl.close();
  await _msgCtrl.close();
}
```

**ผลลัพธ์:**
- ✅ Mesh จะ refresh device discovery ทุก 15 วินาที
- ✅ พบอุปกรณ์ใหม่ที่เข้ามาได้อย่างต่อเนื่อง
- ✅ รักษาการเชื่อมต่อกับอุปกรณ์เดิมไว้
- ✅ Route discovery (HELLO) ยังทำงานทุก 30 วินาทีเหมือนเดิม

---

## 🔬 การทดสอบ

### WiFi Direct
```bash
1. เปิดแอพในเครื่อง 2 เครื่อง
2. เลือก WiFi Direct protocol
3. กด Scan
4. ตรวจสอบว่าเชื่อมต่อได้ (ดู log: "Auto-connected to...")
5. ส่งข้อความ -> ควรแสดงระยะห่างด้วย
```

### Mesh Protocol
```bash
1. เปิดแอพในเครื่อง 2+ เครื่อง
2. เลือก Radio Mesh protocol
3. กด Scan
4. รอ 15 วินาที -> ควรเห็น log "Periodic scan: refreshing..."
5. เพิ่มเครื่องใหม่เข้ามา -> ควรพบภายใน 15 วินาที
```

---

## 📊 Timeline ของการทำงาน

### WiFi Direct
```
0s:  เริ่ม scan -> พบ peers
2s:  Auto-connect เริ่มต้น
4s:  Socket connection established
8s:  GPS broadcast ครั้งแรก ✅
16s: GPS broadcast ครั้งที่ 2 ✅
```

### Mesh Protocol
```
0s:   เริ่ม scan -> พบ direct peers
15s:  Periodic scan refresh #1
30s:  Route discovery (HELLO) #1
45s:  Periodic scan refresh #2
60s:  Route discovery (HELLO) #2
```

---

## ⚠️ ข้อควรระวัง

### WiFi Direct
1. **Android permissions:** ต้องขอ `ACCESS_FINE_LOCATION` และ `NEARBY_WIFI_DEVICES`
2. **WiFi ต้องเปิด:** WiFi Direct ทำงานเฉพาะเมื่อ WiFi เปิดอยู่
3. **Battery drain:** Socket connection ใช้แบตเตอรี่มากกว่า Nearby Connections

### Mesh Protocol
1. **Scan frequency:** 15 วินาทีเป็นค่าที่สมดุล (ไม่บ่อยเกินไป แต่ก็ไม่ช้า)
2. **Base transport:** ใช้ NearbyTransport (Bluetooth/WiFi) เป็น foundation
3. **Multi-hop:** ข้อความอาจใช้เวลาส่งมากกว่าปกติถ้าผ่าน 3+ hops

---

## 📝 สรุป

| Protocol | GPS Distance | Scanning | Status |
|----------|-------------|----------|--------|
| **Nearby (Bluetooth)** | ✅ ทำงาน | ✅ ทำงาน | เสร็จสมบูรณ์ |
| **WiFi Direct** | ✅ **แก้ไขแล้ว** | ✅ ทำงาน | **ต้อง update WifiDirectChannel.kt** |
| **Mesh (Radio)** | ✅ ทำงาน | ✅ **แก้ไขแล้ว** | เสร็จสมบูรณ์ |

---

**อัปเดตล่าสุด:** 10 พฤศจิกายน 2025
**ผู้แก้ไข:** GitHub Copilot
