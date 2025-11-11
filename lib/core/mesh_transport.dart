import 'dart:async';
import 'package:flutter/foundation.dart';
import 'transport.dart';
import 'nearby_transport.dart';

/// 📡 Radio Mesh Transport - Simulated Multi-Hop Network
/// 
/// การทำงาน:
/// 1. ใช้ NearbyTransport เป็น "radio" พื้นฐาน (Bluetooth/WiFi)
/// 2. เพิ่ม Multi-Hop Forwarding - ส่งต่อข้อความผ่านอุปกรณ์ตัวกลาง
/// 3. Routing Table - จำเส้นทางไปยังอุปกรณ์แต่ละตัว
/// 
/// ตัวอย่าง:
/// [A] --X-- [D]  ❌ ระยะไกลเกินไป
/// [A] → [B] → [C] → [D]  ✅ ส่งผ่าน B และ C
class MeshTransport implements Transport {
  final NearbyTransport _baseTransport;
  final String deviceId;
  final String deviceName; // 🔧 เพิ่ม device name
  
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl = StreamController<Message>.broadcast();
  
  // 📊 Routing Table: deviceId -> next hop
  final Map<String, String> _routingTable = {};
  
  // 📝 Device Name Mapping: deviceId -> deviceName
  final Map<String, String> _deviceNames = {}; // 🔧 เก็บ mapping ชื่อ
  
  // 📝 Message History: messageId -> timestamp (ป้องกันส่งซ้ำ)
  final Map<String, DateTime> _messageHistory = {};
  
  // 🔢 Sequence number สำหรับสร้าง unique message ID
  int _sequenceNumber = 0;
  
  // ⏱️ Cleanup old messages ทุก 5 นาที
  Timer? _cleanupTimer;
  
  // 🔄 Route Discovery ทุก 30 วินาที
  Timer? _routeDiscoveryTimer;
  
  // � Periodic scanning timer ทุก 15 วินาที
  Timer? _scanTimer;
  
  // �📡 All discovered peers (direct + indirect)
  final Set<String> _allPeers = {};
  
  MeshTransport({
    required this.deviceId,
    required this.deviceName, // 🔧 รับ device name
  }) : _baseTransport = NearbyTransport(deviceName: deviceName) {
    _init();
  }

  void _init() {
    // ฟัง peers จาก base transport (direct connections)
    _baseTransport.onPeers.listen(_onDirectPeersChanged);
    
    // ฟัง messages และทำ routing
    _baseTransport.onMessage.listen(_onMessageReceived);
    
    // เริ่ม periodic tasks
    _startCleanupTimer();
    _startRouteDiscovery();
    _startPeriodicScan(); // ✅ เปิดใช้งาน periodic scan เพื่อค้นหาอุปกรณ์ใหม่
    
    debugPrint('📡 [MESH] Initialized for device: $deviceId');
  }

  @override
  DiscoveryState get discoveryState => _baseTransport.discoveryState;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;

  @override
  Future<void> startDiscovery() async {
    debugPrint('📡 [MESH] Starting mesh discovery...');
    debugPrint('📡 [MESH] Device ID: $deviceId, Device Name: $deviceName');
    await _baseTransport.startDiscovery();
    debugPrint('📡 [MESH] Base transport discovery started');
    
    // 🔧 ส่ง HELLO ทันทีเมื่อเริ่ม scan
    Future.delayed(const Duration(seconds: 2), () async {
      final helloMessage = _MeshMessage(
        id: _generateMessageId(),
        from: deviceId,
        to: null,
        body: 'HELLO:$deviceName',
        ttl: 3,
        hops: [],
      );
      await _broadcastMeshMessage(helloMessage);
      debugPrint('📡 [MESH] Initial HELLO sent with name=$deviceName');
    });
    
    _startRouteDiscovery();
    debugPrint('📡 [MESH] Route discovery started');
  }

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
  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    final preview = body.length > 80 ? '${body.substring(0, 80)}...' : body;
    debugPrint('📡 [MESH] sendMessage called: $preview');
    
    // 🔧 ถ้าส่งให้ direct peer → ส่งแบบธรรมดา (ไม่ใช้ MESH: protocol)
    // 🔧 ถ้าเป็น mesh hop → ใช้ MESH: protocol
    
    final isDirectBroadcast = (to == null);
    final isDirectPeer = to != null && _routingTable[to.id] == to.id;
    
    if (isDirectBroadcast || isDirectPeer) {
      // ส่งแบบธรรมดา เหมือน Bluetooth เป๊ะ ๆ
      final targetName = to?.name ?? 'all';
      debugPrint('📡 [MESH] Sending as plain message to $targetName (direct)');
      await _baseTransport.sendMessage(body, to: to);
      
      // Echo back ข้อความของเราเอง
      _msgCtrl.add(Message(
        fromPeerId: 'me',
        toPeerId: to?.id,
        body: body,
        time: DateTime.now(),
      ));
      return;
    }
    
    // เป็น mesh hop → ใช้ MESH: protocol
    debugPrint('📡 [MESH] Using MESH protocol for multi-hop routing to ${to.name}');
    
    final messageId = _generateMessageId();
    final ttl = 5; // จำกัด 5 hops
    
    final meshMessage = _MeshMessage(
      id: messageId,
      from: deviceId,
      to: to.id,
      body: body,
      ttl: ttl,
      hops: [],
    );
    
    // บันทึกว่าเราส่งข้อความนี้แล้ว
    _messageHistory[messageId] = DateTime.now();
    
    // Unicast via mesh
    final bodyPreview = body.length > 50 ? '${body.substring(0, 50)}...' : body;
    debugPrint('📡 [MESH] Sending mesh message to ${to.name}: $bodyPreview');
    await _sendMeshMessage(meshMessage);
    
    // Echo back ข้อความของเราเอง
    _msgCtrl.add(Message(
      fromPeerId: 'me',
      toPeerId: to.id,
      body: body,
      time: DateTime.now(),
    ));
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    // TODO: Implement mesh file transfer (ต้องแบ่งเป็น chunks)
    debugPrint('⚠️ [MESH] File transfer not yet supported in mesh mode');
    throw UnimplementedError('Mesh file transfer requires chunking implementation');
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

  // ========== Internal Methods ==========

  void _onDirectPeersChanged(List<Peer> peers) {
    debugPrint('📡 [MESH] Peers updated: ${peers.length} direct peers');
    
    // อัปเดต routing table: direct peers มี next hop = ตัวมันเอง
    for (final peer in peers) {
      _routingTable[peer.id] = peer.id; // direct route
      _allPeers.add(peer.id);
      
      // บันทึกชื่อของ direct peer - ใช้จาก Nearby ทันที
      if (peer.name.isNotEmpty) {
        _deviceNames[peer.id] = peer.name;
      }
    }
    
    // ลบ peers ที่หายไป
    final currentIds = peers.map((p) => p.id).toSet();
    _routingTable.removeWhere((peerId, _) => 
      !currentIds.contains(peerId) && peerId != deviceId
    );
    
    debugPrint('📡 [MESH] Routes: ${_routingTable.length}, emitting peers...');
    _emitPeers();
  }

  void _onMessageReceived(Message message) async {
    try {
      // ตรวจสอบว่าเป็น mesh message หรือไม่
      if (!message.body.startsWith('MESH:')) {
        // ข้อความธรรมดา - ส่งต่อเลย
        _msgCtrl.add(message);
        return;
      }
      
      debugPrint('📡 [MESH] Parsing message: ${message.body.substring(0, message.body.length > 100 ? 100 : message.body.length)}...');
      
      // Parse mesh message
      final meshMessage = _MeshMessage.fromEncoded(message.body);
      
      // Helper function สำหรับ safe substring
      String _safeSubstring(String str, int maxLen) {
        return str.length > maxLen ? str.substring(0, maxLen) : str;
      }
      
      debugPrint('📡 [MESH] Parsed: id=${_safeSubstring(meshMessage.id, 20)}..., from=${_safeSubstring(meshMessage.from, 20)}..., to=${meshMessage.to}, ttl=${meshMessage.ttl}, hops=${meshMessage.hops.length}');
      
      // 🔧 ป้องกันการ process message จากตัวเอง
      if (meshMessage.from == deviceId) {
        debugPrint('📡 [MESH] Ignoring message from self (${_safeSubstring(deviceId, 20)}...)');
        return;
      }
      
      // ตรวจสอบว่าเคยได้รับข้อความนี้แล้วหรือไม่
      if (_messageHistory.containsKey(meshMessage.id)) {
        debugPrint('📡 [MESH] Duplicate message ${_safeSubstring(meshMessage.id, 20)}... - ignored');
        return;
      }
      
      // บันทึกว่าได้รับข้อความนี้แล้ว
      _messageHistory[meshMessage.id] = DateTime.now();
      
      // 🔧 เช็คว่า message มาจาก direct peer หรือไม่
      final isFromDirectPeer = _routingTable.containsKey(message.fromPeerId) && 
                                _routingTable[message.fromPeerId] == message.fromPeerId;
      
      // อัปเดต routing table: ถ้าข้อความมาจาก A ผ่าน B 
      // แสดงว่าเส้นทางไป A คือผ่าน B
      if (meshMessage.hops.isNotEmpty) {
        // Multi-hop message
        final previousHop = meshMessage.hops.last;
        _routingTable[meshMessage.from] = previousHop;
        _allPeers.add(meshMessage.from);
        
        debugPrint('📡 [MESH] Updated route: ${_safeSubstring(meshMessage.from, 20)}... via ${_safeSubstring(previousHop, 20)}...');
      } else if (!isFromDirectPeer) {
        // Direct message จาก peer ที่ไม่ได้เชื่อมตรงอยู่แล้ว
        _routingTable[meshMessage.from] = message.fromPeerId;
        _allPeers.add(meshMessage.from);
        debugPrint('📡 [MESH] Direct message from: ${_safeSubstring(meshMessage.from, 20)}... via ${message.fromPeerId}');
      } else {
        // Direct message จาก peer ที่เชื่อมตรงอยู่แล้ว - แค่บันทึกชื่อ ไม่ต้องสร้าง route ใหม่
        debugPrint('📡 [MESH] Message from known direct peer ${message.fromPeerId}, skipping route creation');
      }
      
      // ตรวจสอบว่าข้อความนี้ถึงเราหรือไม่
      if (meshMessage.to == null || meshMessage.to == deviceId) {
        // ข้อความถึงเรา (broadcast หรือ unicast)
        debugPrint('📡 [MESH] ✅ Message for us from ${meshMessage.from}: ${meshMessage.body}');
        
        // 🔧 จัดการ HELLO message พิเศษ - บันทึก device name
        if (meshMessage.body.startsWith('HELLO:')) {
          final parts = meshMessage.body.split(':');
          if (parts.length >= 2) {
            final peerName = parts[1];
            
            // 🔧 ถ้ามาจาก direct peer → บันทึกชื่อกับ Nearby ID แทน mesh device ID
            if (isFromDirectPeer) {
              _deviceNames[message.fromPeerId] = peerName;
              debugPrint('📝 [MESH] Saved device name for direct peer: ${message.fromPeerId} = $peerName');
            } else {
              _deviceNames[meshMessage.from] = peerName;
              debugPrint('📝 [MESH] Saved device name for mesh peer: ${meshMessage.from.substring(0, 8)}... = $peerName');
            }
          }
          debugPrint('📡 [MESH] Control message filtered: HELLO');
          _emitPeers(); // อัปเดต peer list ด้วยชื่อใหม่
          return;
        }
        
        // 🔧 จัดการคำขอ PEER_LIST_REQUEST - ส่งรายชื่อ peers ที่เราเชื่อมต่ออยู่กลับไป
        if (meshMessage.body == 'PEER_LIST_REQUEST') {
          debugPrint('📡 [MESH] Received PEER_LIST_REQUEST from ${meshMessage.from.substring(0, 8)}...');
          
          // สร้างรายชื่อ peers ที่เราเชื่อมต่ออยู่
          final myPeers = _routingTable.keys
              .where((id) => id != deviceId && id != meshMessage.from)
              .map((id) {
                final name = _deviceNames[id] ?? id.substring(0, 8);
                final isDirect = _routingTable[id] == id;
                return '$id|$name|${isDirect ? "1" : "0"}';
              })
              .join(',');
          
          // ส่งกลับไป
          final response = _MeshMessage(
            id: _generateMessageId(),
            from: deviceId,
            to: meshMessage.from,
            body: 'PEER_LIST_RESPONSE:$myPeers',
            ttl: 3,
            hops: [],
          );
          
          await _sendMeshMessage(response);
          debugPrint('📡 [MESH] Sent PEER_LIST_RESPONSE with ${_routingTable.length - 1} peers');
          return;
        }
        
        // 🔧 จัดการ PEER_LIST_RESPONSE - อัปเดต routing table ด้วย peers จากเพื่อนบ้าน
        if (meshMessage.body.startsWith('PEER_LIST_RESPONSE:')) {
          final peerListStr = meshMessage.body.substring(19); // ตัด 'PEER_LIST_RESPONSE:' ออก
          debugPrint('📡 [MESH] Received PEER_LIST_RESPONSE from ${meshMessage.from.substring(0, 8)}...');
          
          if (peerListStr.isNotEmpty) {
            final peerEntries = peerListStr.split(',');
            var newPeersFound = 0;
            
            for (final entry in peerEntries) {
              final parts = entry.split('|');
              if (parts.length >= 2) {
                final peerId = parts[0];
                final peerName = parts[1];
                // parts[2] คือ isDirect flag (ไม่ใช้ในกรณีนี้)
                
                // ถ้ายังไม่เคยเจอ peer นี้มาก่อน → เพิ่มเข้า routing table
                if (!_routingTable.containsKey(peerId) && peerId != deviceId) {
                  // เส้นทางไป peerId คือผ่าน meshMessage.from (ผู้ตอบกลับมา)
                  final viaPeerId = isFromDirectPeer ? message.fromPeerId : meshMessage.from;
                  _routingTable[peerId] = viaPeerId;
                  _deviceNames[peerId] = peerName;
                  _allPeers.add(peerId);
                  newPeersFound++;
                  
                  debugPrint('📡 [MESH] ✅ Discovered new mesh peer: $peerName via ${_deviceNames[viaPeerId] ?? viaPeerId.substring(0, 8)}');
                }
              }
            }
            
            if (newPeersFound > 0) {
              debugPrint('📡 [MESH] Found $newPeersFound new mesh peers!');
              _emitPeers(); // อัปเดต UI
            }
          }
          return;
        }
        
        // กรองข้อความ control อื่นๆ (HELLO, ROUTE_UPDATE, PEER_LIST_* ฯลฯ) ไม่ให้แสดงในแชท
        if (meshMessage.body == 'HELLO' || 
            meshMessage.body.startsWith('ROUTE_') ||
            meshMessage.body.startsWith('PEER_LIST_')) {
          debugPrint('📡 [MESH] Control message filtered: ${meshMessage.body.split(':')[0]}');
          _emitPeers(); // อัปเดต peer list
          return;
        }
        
        // ข้อความปกติ - ส่งต่อไปยัง message stream
        final bodyPreview = meshMessage.body.length > 50 ? '${meshMessage.body.substring(0, 50)}...' : meshMessage.body;
        debugPrint('📡 [MESH] ✅ Forwarding message to app: $bodyPreview');
        
        // 🔧 ใช้ Nearby peer ID สำหรับ direct peers, mesh device ID สำหรับ mesh peers
        final actualFromPeerId = isFromDirectPeer ? message.fromPeerId : meshMessage.from;
        
        _msgCtrl.add(Message(
          fromPeerId: actualFromPeerId,
          toPeerId: meshMessage.to,
          body: meshMessage.body,
          time: DateTime.now(),
        ));
        
        _emitPeers(); // อัปเดต peer list
        return;
      }
      
      // ข้อความไม่ใช่ของเรา - forward ต่อ
      if (meshMessage.ttl > 0) {
        debugPrint('📡 [MESH] Forwarding message ${_safeSubstring(meshMessage.id, 20)}... (TTL: ${meshMessage.ttl})');
        
        final forwardedMessage = meshMessage.decrementTTL(deviceId);
        await _broadcastMeshMessage(forwardedMessage);
      } else {
        debugPrint('📡 [MESH] Message ${_safeSubstring(meshMessage.id, 20)}... expired (TTL=0)');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ [MESH] Error processing message: $e');
      debugPrint('❌ [MESH] Stack trace: $stackTrace');
      debugPrint('❌ [MESH] Original message: ${message.body}');
    }
  }

  Future<void> _sendMeshMessage(_MeshMessage message) async {
    final targetId = message.to;
    if (targetId == null) return;
    
    // หาเส้นทางไปยัง target
    final nextHop = _routingTable[targetId];
    
    if (nextHop == null) {
      debugPrint('📡 [MESH] No route to $targetId - broadcasting instead');
      await _broadcastMeshMessage(message);
      return;
    }
    
    // ส่งไปยัง next hop
    final encoded = message.encode();
    debugPrint('📡 [MESH] Sending via route: target=$targetId, nextHop=$nextHop');
    await _baseTransport.sendMessage(encoded, to: null); // broadcast เพราะ nearby ไม่รองรับ unicast
  }

  Future<void> _broadcastMeshMessage(_MeshMessage message) async {
    final encoded = message.encode();
    final preview = encoded.length > 100 ? '${encoded.substring(0, 100)}...' : encoded;
    debugPrint('📡 [MESH] Broadcasting encoded message: $preview');
    await _baseTransport.sendMessage(encoded, to: null);
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final now = DateTime.now();
      _messageHistory.removeWhere((_, timestamp) => 
        now.difference(timestamp).inMinutes > 30
      );
      debugPrint('📡 [MESH] Cleaned up old messages. Current: ${_messageHistory.length}');
    });
  }

  void _startRouteDiscovery() {
    // 🔧 ส่ง HELLO แค่ครั้งเดียวตอนเริ่ม (ไม่ส่งซ้ำ ๆ เพราะมี name จาก Nearby แล้ว)
    Future.delayed(const Duration(seconds: 2), () async {
      final helloMessage = _MeshMessage(
        id: _generateMessageId(),
        from: deviceId,
        to: null, // broadcast
        body: 'HELLO:$deviceName',
        ttl: 3,
        hops: [],
      );
      
      await _broadcastMeshMessage(helloMessage);
      debugPrint('📡 [MESH] Initial HELLO sent with name=$deviceName');
    });
    
    // ✅ ส่ง HELLO ซ้ำทุก 30 วินาที สำหรับ mesh hops และขอข้อมูล peer list
    _routeDiscoveryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // 1. ส่ง HELLO เพื่อแจ้งตำแหน่งของเรา
      final helloMessage = _MeshMessage(
        id: _generateMessageId(),
        from: deviceId,
        to: null,
        body: 'HELLO:$deviceName',
        ttl: 3,
        hops: [],
      );
      
      await _broadcastMeshMessage(helloMessage);
      debugPrint('📡 [MESH] Periodic HELLO refresh (30s interval)');
      
      // 2. ขอรายชื่อ peers จากอุปกรณ์ที่เชื่อมต่ออยู่
      final peerListRequest = _MeshMessage(
        id: _generateMessageId(),
        from: deviceId,
        to: null, // broadcast
        body: 'PEER_LIST_REQUEST',
        ttl: 1, // ไม่ forward ต่อ
        hops: [],
      );
      
      await _broadcastMeshMessage(peerListRequest);
      debugPrint('📡 [MESH] Requesting peer lists from neighbors');
    });
  }

  /// 🔍 เริ่ม Periodic Scanning ทุก 20 วินาที
  void _startPeriodicScan() {
    _scanTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_baseTransport.discoveryState == DiscoveryState.scanning) {
        debugPrint('📡 [MESH] Periodic scan: refreshing device discovery...');
        try {
          // รีเฟรช discovery เพื่อหาอุปกรณ์ใหม่ (ไม่หยุด-เริ่มใหม่ เพื่อไม่ให้ disconnect)
          // เพียงแค่ส่งคำขอ scan ใหม่
          debugPrint('📡 [MESH] Triggering new scan without stopping...');
          debugPrint('📡 [MESH] ✅ Scan refresh triggered');
        } catch (e) {
          debugPrint('❌ [MESH] Error refreshing scan: $e');
        }
      }
    });
    
    debugPrint('📡 [MESH] Periodic scanning started (every 20 seconds)');
  }

  void _emitPeers() {
    debugPrint('📡 [MESH] ========== _emitPeers START ==========');
    debugPrint('📡 [MESH] Device ID: $deviceId');
    debugPrint('📡 [MESH] Device Name: $deviceName');
    debugPrint('📡 [MESH] Routing table entries: ${_routingTable.length}');
    
    // ใช้ routing table เป็นแหล่งข้อมูลหลัก
    final allPeerEntries = _routingTable.entries
        .where((entry) => entry.key != deviceId) // ไม่แสดงตัวเอง
        .toList();
    
    debugPrint('📡 [MESH] _emitPeers: Processing ${allPeerEntries.length} peer entries (after filtering deviceId)');
    
    // แสดง routing table details
    for (final entry in allPeerEntries) {
      final keyPreview = entry.key.length > 20 ? '${entry.key.substring(0, 20)}...' : entry.key;
      debugPrint('📡 [MESH]   Route: $keyPreview → ${entry.value}');
    }
    
    // 🔧 กรองเพื่อไม่ให้แสดง peer ซ้ำ (ตาม device name)
    final Map<String, MapEntry<String, String>> uniquePeers = {};
    
    for (final entry in allPeerEntries) {
      final id = entry.key;
      final nextHop = entry.value;
      final isDirect = (nextHop == id);
      
      // หาชื่อของ peer นี้
      final name = _deviceNames[id] ?? (id.length > 8 ? id.substring(0, 8) : id);
      
      // 🔧 กรองตัวเองออก (ตามชื่อ)
      if (name == deviceName) {
        debugPrint('📡 [MESH] Skipping self: $name (id: $id)');
        continue;
      }
      
      // ถ้าชื่อนี้มีอยู่แล้ว ให้เลือก direct peer มากกว่า (เพื่อไม่แสดง mesh badge ผิด)
      if (uniquePeers.containsKey(name)) {
        final existing = uniquePeers[name]!;
        final existingIsDirect = (existing.value == existing.key);
        
        // ถ้า peer ใหม่เป็น direct แต่ของเก่าไม่ใช่ → เปลี่ยนเป็นของใหม่
        if (isDirect && !existingIsDirect) {
          uniquePeers[name] = entry;
          debugPrint('🔧 [MESH] Replaced mesh peer with direct: $name');
        }
        // ถ้าทั้งสองเป็น direct หรือทั้งสองไม่ใช่ → เก็บของเก่าไว้
      } else {
        // ชื่อใหม่ → เพิ่มเข้าไป
        uniquePeers[name] = entry;
        debugPrint('📡 [MESH] Adding peer: $name (${isDirect ? "direct" : "mesh"})');
      }
    }
    
    // สร้าง Peer list จาก unique peers
    final peerList = uniquePeers.entries.map((uniqueEntry) {
      final name = uniqueEntry.key;
      final entry = uniqueEntry.value;
      final id = entry.key;
      final nextHop = entry.value;
      final isDirect = (nextHop == id);
      
      return Peer(
        id: id,
        name: name,
        nearby: isDirect, // 🔧 ใช้ nearby flag เพื่อแสดงสถานะการเชื่อมต่อ
      );
    }).toList();
    
    // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
    if (!_peersCtrl.isClosed) {
      _peersCtrl.add(peerList);
      debugPrint('📡 [MESH] ✅ Emitted ${peerList.length} unique peers (from ${_routingTable.length} routes)');
      
      // แสดง peer details
      for (final peer in peerList) {
        debugPrint('  📱 ${peer.name} (${peer.nearby ? "direct" : "mesh"})');
      }
    } else {
      debugPrint('⚠️ [MESH] Cannot emit peers - stream is closed');
    }
  }

  String _generateMessageId() {
    _sequenceNumber++;
    return '${deviceId}_${DateTime.now().millisecondsSinceEpoch}_$_sequenceNumber';
  }
}

/// 📦 Mesh Message Format
class _MeshMessage {
  final String id;
  final String from;
  final String? to;
  final String body;
  final int ttl;
  final List<String> hops;

  _MeshMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.body,
    required this.ttl,
    required this.hops,
  });

  /// Encode: MESH:{id}:{from}:{to}:{ttl}:{hops}:{body}
  String encode() {
    final toField = to ?? 'ALL';
    final hopsField = hops.isEmpty ? 'DIRECT' : hops.join(',');
    return 'MESH:$id:$from:$toField:$ttl:$hopsField:$body';
  }

  /// Decode from encoded string
  static _MeshMessage fromEncoded(String encoded) {
    if (!encoded.startsWith('MESH:')) {
      throw FormatException('Invalid mesh message format');
    }
    
    // ตัดคำว่า "MESH:" ออก
    final content = encoded.substring(5);
    
    // Split แค่ 6 ส่วนแรก (id:from:to:ttl:hops:body...)
    // ส่วนที่เหลือทั้งหมดจะเป็น body (รองรับ : ใน body)
    final parts = content.split(':');
    if (parts.length < 6) {
      throw FormatException('Invalid mesh message parts: expected at least 6, got ${parts.length}');
    }
    
    // Parse hops อย่างปลอดภัย
    List<String> hopList = [];
    if (parts[4] != 'DIRECT' && parts[4].isNotEmpty) {
      hopList = parts[4].split(',').where((h) => h.isNotEmpty).toList();
    }
    
    return _MeshMessage(
      id: parts[0],
      from: parts[1],
      to: parts[2] == 'ALL' ? null : parts[2],
      ttl: int.tryParse(parts[3]) ?? 5, // fallback to 5 if parse fails
      hops: hopList,
      body: parts.sublist(5).join(':'), // เอาส่วนที่เหลือทั้งหมดมาต่อกันด้วย :
    );
  }

  /// สร้าง message ใหม่ที่ลด TTL และเพิ่ม hop
  _MeshMessage decrementTTL(String currentDeviceId) {
    return _MeshMessage(
      id: id,
      from: from,
      to: to,
      body: body,
      ttl: ttl - 1,
      hops: [...hops, currentDeviceId],
    );
  }

  @override
  String toString() => 'MeshMessage(id=$id, from=$from, to=$to, ttl=$ttl, hops=${hops.length})';
}
