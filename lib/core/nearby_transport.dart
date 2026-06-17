import 'dart:async';
import 'dart:convert'; // เพิ่มสำหรับ utf8 encoding/decoding
import 'dart:typed_data'; // เพิ่มการนำเข้า Uint8List
import 'dart:io'; // เพิ่มสำหรับ File operations
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart'; // เพิ่มสำหรับหา app directory
import 'transport.dart';
import 'package:offgrid_sos/core/logger.dart';

/// ใช้กลยุทธ์ CLUSTER: ยืดหยุ่น เชื่อมต่อได้หลายเครื่อง
const _strategy = Strategy.P2P_CLUSTER;

/// บริการ/ชื่อที่ใช้ค้นหา ควร unique ระดับแอพ
const _serviceId = 'com.example.offgrid_sos.nearby';

/// ข้อมูลไฟล์ที่รอรับ
class _PendingFile {
  final String fromPeerId;
  final String? uri;
  final String? fileType; // 'VIDEO' หรือ 'IMAGE'
  const _PendingFile(this.fromPeerId, this.uri, {this.fileType});
}

class NearbyTransport implements Transport {
  String deviceName; // เปลี่ยนเป็น mutable เพื่อให้อัปเดตได้
  static const _permissionChannel = MethodChannel('nearby_permissions');

  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl = StreamController<Message>.broadcast();
  final _fileCtrl = StreamController<ReceivedFile>.broadcast();
  final Map<String, ConnectionInfo> _connected = {};
  final Set<String> _found = {};
  final Map<int, _PendingFile> _pendingFiles = {}; // payloadId -> file info
  final Set<String> _pendingConnections = {}; // ป้องกันการ request ซ้ำ
  final Map<String, String> _fileMetadata = {}; // peerId -> fileType (VIDEO/IMAGE)
  final Set<String> _cleanupDisconnects = {}; // endpoint IDs ที่กำลัง disconnect เพื่อ cleanup (ไม่ลบจาก _found)
  
  // 🆕 เก็บ persistent peers - peers ที่เคยเชื่อมต่อและต้องการรักษาการเชื่อมต่อ
  final Map<String, ConnectionInfo> _persistentPeers = {}; // endpointId -> ConnectionInfo
  final Map<String, DateTime> _lostPeers = {}; // endpointId -> เวลาที่หาย (สำหรับ grace period)

  DiscoveryState _state = DiscoveryState.idle;
  bool _isAdvertising = false;
  bool _isDiscovering = false;

  NearbyTransport({required this.deviceName}) {
    // ⚡ เริ่ม periodic cleanup สำหรับ lost peers ที่เก่ามาก
    _startPeriodicCleanup();
  }

  // ทำความสะอาด lost peers ที่หายไปนาน > 1 ชั่วโมง
  void _startPeriodicCleanup() {
    Timer.periodic(const Duration(minutes: 10), (_) {
      final now = DateTime.now();
      final toRemove = <String>[];
      
      for (final entry in _lostPeers.entries) {
        final downDuration = now.difference(entry.value);
        if (downDuration.inHours >= 1) {
          Log.d('🧹 Removing lost peer ${entry.key} - down for ${downDuration.inHours} hours');
          toRemove.add(entry.key);
        }
      }
      
      for (final id in toRemove) {
        _lostPeers.remove(id);
        _persistentPeers.remove(id);
        _found.remove(id);
      }
      
      if (toRemove.isNotEmpty) {
        _emitPeers();
      }
    });
  }

  // Stream สำหรับไฟล์ที่ได้รับ
  @override
  Stream<ReceivedFile> get onFileReceived => _fileCtrl.stream;

  // เพิ่ม method สำหรับอัปเดตชื่อเครื่อง
  void updateDeviceName(String newName) {
    deviceName = newName;
    // หาก sedang advertising, ต้อง restart เพื่อใช้ชื่อใหม่
    if (_isAdvertising) {
      _restartAdvertising();
    }
  }

  Future<void> _restartAdvertising() async {
    if (_isAdvertising) {
      await Nearby().stopAdvertising();
      _isAdvertising = false;
      // เริ่ม advertising ใหม่ด้วยชื่อใหม่ โดยใช้ startDiscovery
      await startDiscovery();
    }
  }

  @override
  DiscoveryState get discoveryState => _state;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;

  Future<bool> _ensurePerms() async {
    // Android 12+ ต้องขอ BLUETOOTH_* runtime; Android 13+ มี NEARBY_WIFI_DEVICES
    final req = <Permission>[
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];

    final result = await req.request();
    
    // Check if all critical permissions are granted
    bool hasLocation = result[Permission.location]?.isGranted ?? false;
    bool hasBluetooth = result[Permission.bluetooth]?.isGranted ?? false;
    bool hasBluetoothAdvertise = result[Permission.bluetoothAdvertise]?.isGranted ?? false;
    bool hasBluetoothConnect = result[Permission.bluetoothConnect]?.isGranted ?? false;
    bool hasBluetoothScan = result[Permission.bluetoothScan]?.isGranted ?? false;
    
    // Check NEARBY_WIFI_DEVICES permission via native channel
    bool hasNearbyWifiDevices = true;
    try {
      hasNearbyWifiDevices = await _permissionChannel.invokeMethod('hasNearbyWifiPermission') ?? false;
      if (!hasNearbyWifiDevices) {
        Log.d('📶 Requesting NEARBY_WIFI_DEVICES permission...');
        await _permissionChannel.invokeMethod('requestNearbyWifiPermission');
        // Check again after request
        hasNearbyWifiDevices = await _permissionChannel.invokeMethod('hasNearbyWifiPermission') ?? false;
      }
    } catch (e) {
      Log.d('⚠️ NEARBY_WIFI_DEVICES permission check failed: $e');
      // Continue anyway, might work with location permission
    }
    
    Log.d('🔍 Permissions check:');
    Log.d('📍 Location: $hasLocation');
    Log.d('📶 Bluetooth: $hasBluetooth');
    Log.d('📢 Bluetooth Advertise: $hasBluetoothAdvertise');
    Log.d('🔗 Bluetooth Connect: $hasBluetoothConnect');
    Log.d('🔎 Bluetooth Scan: $hasBluetoothScan');
    Log.d('📶 Nearby WiFi Devices: $hasNearbyWifiDevices');
    
    // Require at least location and bluetooth permissions
    bool hasBasicPerms = hasLocation && hasBluetooth && hasBluetoothAdvertise && hasBluetoothConnect && hasBluetoothScan;
    
    if (!hasBasicPerms) {
      Log.d('❌ Missing basic permissions for Nearby Connections');
      return false;
    }
    
    return true;
  }

  void _emitPeers() {
    // ป้องกันการ emit หลังจาก dispose
    if (_peersCtrl.isClosed) {
      Log.d('⚠️ _emitPeers() skipped - controller is closed');
      return;
    }
    
    final list = <Peer>[];
    Log.d('🔍 _emitPeers() - My device name: "$deviceName"');
    Log.d('   Total found: ${_found.length}, Total connected: ${_connected.length}');
    
    // peers = รวมเฉพาะที่เชื่อมต่อสำเร็จแล้ว (มี ConnectionInfo)
    for (final id in _connected.keys) {
      final info = _connected[id];
      if (info == null) continue;
      
      final peerName = info.endpointName;
      
      Log.d('  Connected peer: id=$id, name="$peerName"');
      
      // กรองเครื่องตัวเองออก
      if (peerName == deviceName || peerName.isEmpty) {
        Log.d('  ⚠️ Filtered out: own device or empty name: "$peerName" ($id)');
        continue;
      }
      
      list.add(Peer(
        id: id,
        name: peerName,
        nearby: true,
      ));
    }
    
    Log.d('📱 Emitting ${list.length} connected peers');
    // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
    if (!_peersCtrl.isClosed) {
      _peersCtrl.add(list);
    }
  }

  // Helper method สำหรับ request connection พร้อม retry logic
  void _doRequestConnection(String id, {int retryCount = 0}) {
    // ป้องกัน retry มากเกินไป
    if (retryCount > 3) {
      Log.d('❌ Max retry attempts reached for $id');
      _pendingConnections.remove(id);
      _found.remove(id);
      _emitPeers();
      return;
    }
    
    Nearby().requestConnection(
      deviceName,
      id,
      onConnectionInitiated: (rid, info) async {
        Log.d('🤝 Connection initiated (DISCOVERY side): $rid, name=${info.endpointName}');
        
        // ⚠️ ป้องกันการเชื่อมต่อกับเครื่องตัวเอง
        if (info.endpointName == deviceName) {
          Log.d('⛔ Rejected: Cannot connect to self (${info.endpointName})');
          _pendingConnections.remove(rid);
          try {
            await Nearby().rejectConnection(rid);
          } catch (e) {
            Log.d('⚠️ Failed to reject self-connection: $e');
          }
          return;
        }
        
        // บันทึก connection info ทันที
        _connected[rid] = info;
        Log.d('📝 Saved connection info for ${info.endpointName} ($rid)');
        
        // ⚡ บันทึกเป็น persistent peer (เพื่อ auto-reconnect ในอนาคต)
        _persistentPeers[rid] = info;
        Log.d('💾 Added to persistent peers list');
        
        // ⚡ ลด delay จาก 200ms → 100ms เพื่อความเร็ว
        await Future.delayed(const Duration(milliseconds: 100));
        
        try {
          await Nearby().acceptConnection(
            rid,
            onPayLoadRecieved: (eid, payload) {
              Log.d('📨 [Discovery] Received payload from: $eid (type: ${payload.type})');
              Log.d('   Payload size: ${payload.bytes?.length ?? 0} bytes');
              
              if (payload.type == PayloadType.BYTES) {
                final rawBytes = payload.bytes!;
                Log.d('📦 BYTES payload received, size: ${rawBytes.length}');
                
                // ตรวจสอบว่าเป็นรูปภาพ, วิดีโอ หรือข้อความ
                const imageMarker = 'IMAGE:';
                const videoMarker = 'VIDEO:';
                const metadataMarker = 'FILE_METADATA:';
                
                // เช็คว่า bytes ขึ้นต้นด้วย marker หรือไม่
                if (rawBytes.length > 6) { // ความยาวขั้นต่ำของ marker
                  final headerStr = String.fromCharCodes(rawBytes.sublist(0, 6));
                  
                  // ตรวจสอบว่าเป็นไฟล์ (IMAGE: หรือ VIDEO:)
                  if (headerStr == imageMarker || headerStr == videoMarker) {
                    // นี่คือไฟล์ (รูปหรือวิดีโอ)!
                    final isVideo = headerStr == videoMarker;
                    final fileType = isVideo ? 'วิดีโอ' : 'รูปภาพ';
                    Log.d('📷 ได้รับ$fileType จาก: $eid');
                    
                    try {
                      // Parse: [marker][length][name][data]
                      final markerBytes = utf8.encode(headerStr);
                      int offset = markerBytes.length;
                      final fileNameLength = rawBytes[offset];
                      offset++;
                      
                      final fileNameBytes = rawBytes.sublist(offset, offset + fileNameLength);
                      final fileName = utf8.decode(fileNameBytes);
                      offset += fileNameLength;
                      
                      final fileBytes = rawBytes.sublist(offset);
                      
                      Log.d('📊 ชื่อไฟล์: $fileName, ขนาด: ${fileBytes.length} bytes');
                      
                      // บันทึกไฟล์ลง app directory
                      if (isVideo) {
                        _saveReceivedVideo(fileBytes, fileName, eid);
                      } else {
                        _saveReceivedImage(fileBytes, fileName, eid);
                      }
                    } catch (e) {
                      Log.d('❌ Parse ไฟล์ล้มเหลว: $e');
                    }
                    return;
                  }
                }
                
                // ถ้าไม่ใช่ไฟล์ = อาจเป็น metadata หรือข้อความ
                // ลอง decode เป็น text (ใช้ try-catch ป้องกัน binary data)
                try {
                  final text = utf8.decode(rawBytes);
                  
                  // ตรวจสอบ metadata message (สำหรับไฟล์ใหญ่)
                  if (text.startsWith(metadataMarker)) {
                    // Parse: FILE_METADATA:VIDEO:filename.mp4
                    final parts = text.substring(metadataMarker.length).split(':');
                    if (parts.length >= 2) {
                      final fileType = parts[0]; // 'VIDEO' or 'IMAGE'
                      Log.d('📋 ได้รับ metadata: $fileType จาก $eid');
                      _fileMetadata[eid] = fileType;
                    }
                    return;
                  }
                  
                  // ถ้าไม่ใช่ metadata = เป็นข้อความปกติ
                  if (!text.startsWith('FILE_METADATA:')) {
                    Log.d('📩 Message content: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');
                    
                    // ป้องกันการ add หลัง dispose
                    if (!_msgCtrl.isClosed) {
                      _msgCtrl.add(Message(
                        fromPeerId: eid,
                        body: text,
                        time: DateTime.now(),
                      ));
                    } else {
                      Log.d('⚠️ Message dropped - controller is closed');
                    }
                  } else {
                    Log.d('⚠️ Metadata message ไม่ควรมาถึงจุดนี้: $text');
                  }
                } catch (e) {
                  // ถ้า decode ไม่ได้ = เป็น binary data ที่ไม่รู้จัก
                  Log.d('⚠️ ไม่สามารถ decode payload เป็น text: $e');
                  Log.d('   ขนาด: ${rawBytes.length} bytes, header: ${rawBytes.take(20).toList()}');
                }
              } else if (payload.type == PayloadType.FILE) {
                Log.d('📁 File payload received: ${payload.id}, uri: ${payload.uri}');
                // เก็บ metadata ที่ได้รับไว้ก่อนหน้า
                final fileType = _fileMetadata[eid];
                Log.d('📋 File type from metadata: $fileType');
                _pendingFiles[payload.id] = _PendingFile(eid, payload.uri, fileType: fileType);
              }
            },
            onPayloadTransferUpdate: (eid, status) {
              if (status.status == PayloadStatus.SUCCESS) {
                final fileInfo = _pendingFiles[status.id];
                if (fileInfo != null && fileInfo.uri != null) {
                  Log.d('✅ File transfer complete: ${fileInfo.uri}');
                  
                  // 🆕 Copy ไฟล์ไปเก็บถาวร (ส่ง fileType จาก metadata)
                  _copyFileToPermanentStorage(fileInfo.uri!, fileType: fileInfo.fileType).then((permanentPath) {
                    Log.d('📁 ไฟล์ถูกเก็บที่: $permanentPath');
                    _fileCtrl.add(ReceivedFile(
                      fromPeerId: fileInfo.fromPeerId,
                      filePath: permanentPath, // ใช้ path ที่ copy แล้ว
                      time: DateTime.now(),
                    ));
                    // ล้าง metadata หลังใช้แล้ว
                    _fileMetadata.remove(fileInfo.fromPeerId);
                  }).catchError((error) {
                    Log.d('❌ Copy ไฟล์ล้มเหลว: $error');
                    // ถ้า copy ไม่ได้ ใช้ URI เดิม
                    _fileCtrl.add(ReceivedFile(
                      fromPeerId: fileInfo.fromPeerId,
                      filePath: fileInfo.uri!,
                      time: DateTime.now(),
                    ));
                  });
                  
                  _pendingFiles.remove(status.id);
                }
              }
            },
          );
          Log.d('✅ [Discovery] Accepted connection: ${info.endpointName} ($rid)');
        } catch (e) {
          Log.d('⚠️ [Discovery] Accept connection error (continuing): $e');
          // ไม่ throw error - รอดูผลจาก onConnectionResult
        }
      },
      onConnectionResult: (rid, status) {
        Log.d('🔗 Connection result (DISCOVERY): $rid -> $status');
        
        // ลบออกจาก pending list
        _pendingConnections.remove(rid);
        
        if (status == Status.CONNECTED) {
          Log.d('✅ Successfully connected (discovery): $rid');
          _emitPeers();
        } else {
          Log.d('❌ Connection failed (discovery): $rid -> $status');
          _connected.remove(rid);
          _found.remove(rid);
          _emitPeers();
        }
      },
      onDisconnected: (rid) {
        Log.d('❌ Disconnected (discovery): $rid');
        _pendingConnections.remove(rid);
        
        // ⚡ ถ้าเป็น persistent peer → เก็บไว้ (ไม่ลบ) แค่ mark ว่า disconnected
        final wasPersistent = _persistentPeers.containsKey(rid);
        if (wasPersistent) {
          Log.d('💾 Persistent peer disconnected - will keep for auto-reconnect');
          _lostPeers[rid] = DateTime.now();
          // ไม่ลบจาก _persistentPeers
        }
        
        _connected.remove(rid);
        
        // ⚡ ถ้าเป็น cleanup disconnect (เพื่อ retry) → ไม่ลบจาก _found
        if (_cleanupDisconnects.contains(rid)) {
          Log.d('   This is a cleanup disconnect - keeping endpoint in _found for retry');
          _cleanupDisconnects.remove(rid);
        } else if (!wasPersistent) {
          // disconnect จริงๆ และไม่ใช่ persistent → ลบออกจาก _found
          _found.remove(rid);
        } else {
          // persistent peer → เก็บไว้ใน _found เพื่อแสดงใน UI (แต่ status = disconnected)
          Log.d('   Keeping persistent peer in _found for display');
        }
        
        _emitPeers();
      },
    ).catchError((error) {
      // ⚡ ตรวจสอบว่าเชื่อมต่ออยู่แล้วหรือไม่ (8003)
      if (error.toString().contains('8003') || error.toString().contains('STATUS_ALREADY_CONNECTED')) {
        Log.d('⚠️ STATUS_ALREADY_CONNECTED detected for $id');
        Log.d('   This means Nearby API has stale connection - disconnecting first...');
        _pendingConnections.remove(id);
        
        // เพิ่มลง cleanup set ก่อน disconnect (เพื่อไม่ให้ onDisconnected ลบจาก _found)
        _cleanupDisconnects.add(id);
        
        // Disconnect connection เก่าที่ค้างอยู่
        Nearby().disconnectFromEndpoint(id).then((_) {
          Log.d('✅ Disconnected stale connection for $id');
          // รอให้ API cleanup เสร็จ
          return Future.delayed(const Duration(milliseconds: 500));
        }).then((_) {
          // Retry connection ใหม่
          if (_found.contains(id) && retryCount < 2) {
            Log.d('🔄 Retrying connection to $id after cleanup...');
            _pendingConnections.add(id);
            _doRequestConnection(id, retryCount: retryCount + 1);
          } else {
            Log.d('⚠️ Max retries reached or endpoint lost for $id');
            _cleanupDisconnects.remove(id); // ลบออกจาก cleanup set
            _emitPeers();
          }
        }).catchError((disconnectError) {
          Log.d('⚠️ Disconnect error for $id: $disconnectError');
          // ลองใหม่อีกครั้งแม้ disconnect ไม่สำเร็จ
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_found.contains(id) && retryCount < 2) {
              Log.d('🔄 Retrying anyway after disconnect error...');
              _pendingConnections.add(id);
              _doRequestConnection(id, retryCount: retryCount + 1);
            } else {
              _cleanupDisconnects.remove(id); // ลบออกจาก cleanup set
            }
          });
        });
        return true;
      }
      
      // ตรวจสอบว่าเป็น STATUS_RADIO_ERROR (8007) หรือไม่
      if (error.toString().contains('8007') || error.toString().contains('STATUS_RADIO_ERROR')) {
        Log.d('📡 Radio error detected for $id - waiting before retry (attempt ${retryCount + 1}/3)');
        _pendingConnections.remove(id); // ยกเลิก pending status
        
        // รอ 2 วินาทีแล้วลองใหม่
        Future.delayed(const Duration(seconds: 2), () {
          if (_found.contains(id) && !_pendingConnections.contains(id)) {
            Log.d('🔄 Retrying connection to $id...');
            _pendingConnections.add(id);
            _doRequestConnection(id, retryCount: retryCount + 1);
          }
        });
      } else {
        // Error อื่นๆ ที่ไม่ใช่ radio error
        Log.d('❌ requestConnection error for $id: $error');
        _pendingConnections.remove(id);
        _found.remove(id);
        _emitPeers();
      }
      return false;
    });
  }

  @override
  Future<void> startDiscovery() async {
    Log.d('🚀 [NearbyTransport] startDiscovery() called');
    Log.d('   Device name: "$deviceName"');
    Log.d('   Current state: $_state');
    
    // ⚡ ถ้ากำลัง scan อยู่แล้ว ไม่ต้องทำอะไร
    if (_state == DiscoveryState.scanning && _isAdvertising && _isDiscovering) {
      Log.d('✅ Already scanning and active, skip restart');
      return;
    }
    
    // Stop any existing sessions first
    if (_isAdvertising || _isDiscovering) {
      Log.d('🔄 Stopping existing sessions...');
      try {
        await stopDiscovery();
        // ⚡ ลด delay ลงเหลือ 1 วินาที (จาก 3 วินาที)
        Log.d('⏳ Waiting for radio to stabilize...');
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        Log.d('⚠️ Error stopping previous session: $e');
        // Reset states manually
        _isAdvertising = false;
        _isDiscovering = false;
        _state = DiscoveryState.idle;
        // รอเพิ่มเติมหลัง error
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    
    final ok = await _ensurePerms();
    if (!ok) {
      Log.d('❌ Permissions not granted for Nearby Connections');
      throw Exception('Permissions not granted for Nearby Connections. Please grant all Bluetooth and Location permissions.');
    }

    _state = DiscoveryState.scanning;
    _found.clear();

    try {
      // เริ่มทั้ง advertise (ให้คนอื่นเห็นเรา) และ discovery (ค้นหาเอง)
      // 1) โฆษณาอุปกรณ์เรา
      Log.d('📢 Starting advertising...');
      Log.d('   Device name: "$deviceName"');
      Log.d('   Service ID: $_serviceId');
      Log.d('   Strategy: $_strategy');
      
      try {
        await Nearby().startAdvertising(
          deviceName,
          _strategy,
          onConnectionInitiated: (id, info) async {
            Log.d('🤝 Connection initiated (ADVERTISING side) from: ${info.endpointName} (id: $id)');
            
            // ⚠️ ป้องกันการเชื่อมต่อกับเครื่องตัวเอง
            if (info.endpointName == deviceName) {
              Log.d('⛔ Rejected: Cannot connect to self (${info.endpointName})');
              try {
                await Nearby().rejectConnection(id);
              } catch (e) {
                Log.d('⚠️ Failed to reject self-connection: $e');
              }
              return;
            }
            
            // บันทึก connection info ก่อน (สำคัญ!)
            _connected[id] = info;
            
            // ⚡ บันทึกเป็น persistent peer (เพื่อ auto-reconnect ในอนาคต)
            _persistentPeers[id] = info;
            Log.d('💾 Added to persistent peers list (advertising side)');
            
            // รับการเชื่อมต่อ (ฝั่ง ADVERTISING เป็น responder)
            try {
              await Nearby().acceptConnection(
                id,
                onPayLoadRecieved: (eid, payload) {
                  Log.d('📨 [Advertising] Received payload from: $eid (type: ${payload.type})');
                  Log.d('   Payload size: ${payload.bytes?.length ?? 0} bytes');
                  
                  if (payload.type == PayloadType.BYTES) {
                    final rawBytes = payload.bytes!;
                    Log.d('📦 BYTES payload received, size: ${rawBytes.length}');
                    
                    // ตรวจสอบว่าเป็นรูปภาพ, วิดีโอ หรือข้อความ
                    const imageMarker = 'IMAGE:';
                    const videoMarker = 'VIDEO:';
                    const metadataMarker = 'FILE_METADATA:';
                    
                    // เช็คว่า bytes ขึ้นต้นด้วย marker หรือไม่
                    if (rawBytes.length > 6) { // ความยาวขั้นต่ำของ marker
                      final headerStr = String.fromCharCodes(rawBytes.sublist(0, 6));
                      
                      // ตรวจสอบว่าเป็นไฟล์ (IMAGE: หรือ VIDEO:)
                      if (headerStr == imageMarker || headerStr == videoMarker) {
                        // นี่คือไฟล์ (รูปหรือวิดีโอ)!
                        final isVideo = headerStr == videoMarker;
                        final fileType = isVideo ? 'วิดีโอ' : 'รูปภาพ';
                        Log.d('📷 ได้รับ$fileType จาก: $eid');
                        
                        try {
                          // Parse: [marker][length][name][data]
                          final markerBytes = utf8.encode(headerStr);
                          int offset = markerBytes.length;
                          final fileNameLength = rawBytes[offset];
                          offset++;
                          
                          final fileNameBytes = rawBytes.sublist(offset, offset + fileNameLength);
                          final fileName = utf8.decode(fileNameBytes);
                          offset += fileNameLength;
                          
                          final fileBytes = rawBytes.sublist(offset);
                          
                          Log.d('📊 ชื่อไฟล์: $fileName, ขนาด: ${fileBytes.length} bytes');
                          
                          // บันทึกไฟล์ลง app directory
                          if (isVideo) {
                            _saveReceivedVideo(fileBytes, fileName, eid);
                          } else {
                            _saveReceivedImage(fileBytes, fileName, eid);
                          }
                        } catch (e) {
                          Log.d('❌ Parse ไฟล์ล้มเหลว: $e');
                        }
                        return;
                      }
                    }
                    
                    // ถ้าไม่ใช่ไฟล์ = อาจเป็น metadata หรือข้อความ
                    // ลอง decode เป็น text (ใช้ try-catch ป้องกัน binary data)
                    try {
                      final text = utf8.decode(rawBytes);
                      
                      // ตรวจสอบ metadata message (สำหรับไฟล์ใหญ่)
                      if (text.startsWith(metadataMarker)) {
                        // Parse: FILE_METADATA:VIDEO:filename.mp4
                        final parts = text.substring(metadataMarker.length).split(':');
                        if (parts.length >= 2) {
                          final fileType = parts[0]; // 'VIDEO' or 'IMAGE'
                          Log.d('📋 ได้รับ metadata: $fileType จาก $eid');
                          _fileMetadata[eid] = fileType;
                        }
                        return;
                      }
                      
                      // ถ้าไม่ใช่ metadata = เป็นข้อความปกติ
                      if (!text.startsWith('FILE_METADATA:')) {
                        Log.d('📩 Message content: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');
                        
                        // ป้องกันการ add หลัง dispose
                        if (!_msgCtrl.isClosed) {
                          _msgCtrl.add(Message(
                            fromPeerId: eid,
                            body: text,
                            time: DateTime.now(),
                          ));
                        } else {
                          Log.d('⚠️ Message dropped - controller is closed');
                        }
                      } else {
                        Log.d('⚠️ Metadata message ไม่ควรมาถึงจุดนี้: $text');
                      }
                    } catch (e) {
                      // ถ้า decode ไม่ได้ = เป็น binary data ที่ไม่รู้จัก
                      Log.d('⚠️ ไม่สามารถ decode payload เป็น text: $e');
                      Log.d('   ขนาด: ${rawBytes.length} bytes, header: ${rawBytes.take(20).toList()}');
                    }
                  } else if (payload.type == PayloadType.FILE) {
                    Log.d('📁 File payload received: ${payload.id}, uri: ${payload.uri}');
                    // เก็บ metadata ที่ได้รับไว้ก่อนหน้า
                    final fileType = _fileMetadata[eid];
                    Log.d('📋 File type from metadata: $fileType');
                    _pendingFiles[payload.id] = _PendingFile(eid, payload.uri, fileType: fileType);
                  }
                },
                onPayloadTransferUpdate: (eid, status) {
                  if (status.status == PayloadStatus.SUCCESS) {
                    final fileInfo = _pendingFiles[status.id];
                    if (fileInfo != null && fileInfo.uri != null) {
                      Log.d('✅ File transfer complete: ${fileInfo.uri}');
                      
                      // 🆕 Copy ไฟล์ไปเก็บถาวร (ส่ง fileType จาก metadata)
                      _copyFileToPermanentStorage(fileInfo.uri!, fileType: fileInfo.fileType).then((permanentPath) {
                        Log.d('📁 ไฟล์ถูกเก็บที่: $permanentPath');
                        _fileCtrl.add(ReceivedFile(
                          fromPeerId: fileInfo.fromPeerId,
                          filePath: permanentPath, // ใช้ path ที่ copy แล้ว
                          time: DateTime.now(),
                        ));
                        // ล้าง metadata หลังใช้แล้ว
                        _fileMetadata.remove(fileInfo.fromPeerId);
                      }).catchError((error) {
                        Log.d('❌ Copy ไฟล์ล้มเหลว: $error');
                        // ถ้า copy ไม่ได้ ใช้ URI เดิม
                        _fileCtrl.add(ReceivedFile(
                          fromPeerId: fileInfo.fromPeerId,
                          filePath: fileInfo.uri!,
                          time: DateTime.now(),
                        ));
                      });
                      
                      _pendingFiles.remove(status.id);
                    }
                  }
                },
              );
              Log.d('✅ Accept connection (advertising side): ${info.endpointName} ($id)');
            } catch (e) {
              Log.d('❌ Failed to accept connection (advertising): $e');
              _connected.remove(id);
            }
          },
          onConnectionResult: (id, status) {
            Log.d('🔗 Connection result (ADVERTISING): $id -> $status');
            if (status == Status.CONNECTED) {
              Log.d('✅ Successfully connected (advertising): $id');
              _emitPeers();
            } else {
              Log.d('❌ Connection failed (advertising): $id -> $status');
              _connected.remove(id);
              _found.remove(id);
              _emitPeers();
            }
          },
          onDisconnected: (id) {
            Log.d('❌ Disconnected (advertising): $id');
            
            // ⚡ ถ้าเป็น persistent peer → เก็บไว้ (ไม่ลบ) แค่ mark ว่า disconnected
            final wasPersistent = _persistentPeers.containsKey(id);
            if (wasPersistent) {
              Log.d('💾 Persistent peer disconnected - will keep for auto-reconnect');
              _lostPeers[id] = DateTime.now();
              // ไม่ลบจาก _persistentPeers
            }
            
            _connected.remove(id);
            
            // ⚡ ถ้าเป็น cleanup disconnect (เพื่อ retry) → ไม่ลบจาก _found
            if (_cleanupDisconnects.contains(id)) {
              Log.d('   This is a cleanup disconnect - keeping endpoint in _found for retry');
              _cleanupDisconnects.remove(id);
            } else if (!wasPersistent) {
              // disconnect จริงๆ และไม่ใช่ persistent → ลบออกจาก _found
              _found.remove(id);
            } else {
              // persistent peer → เก็บไว้ใน _found เพื่อแสดงใน UI (แต่ status = disconnected)
              Log.d('   Keeping persistent peer in _found for display');
            }
            
            _emitPeers();
          },
        );
        _isAdvertising = true;
        Log.d('✅ Advertising started successfully as: $deviceName');
      } catch (e) {
        Log.d('⚠️ Advertising failed (continuing anyway): $e');
        // Continue even if advertising fails - we can still discover others
        _isAdvertising = false;
      }

    // 2) ค้นหา endpoint อื่น
    Log.d('🔎 Starting discovery with serviceId: $_serviceId');
    Log.d('   My device name: "$deviceName"');
    await Nearby().startDiscovery(
      _serviceId,
      _strategy,
      onEndpointFound: (id, name, serviceId) {
        Log.d('🔍 Found endpoint: id=$id, name="$name", serviceId=$serviceId');
        Log.d('   Comparing with my name: "$deviceName"');
        
        // ⚠️ ป้องกันการพบเครื่องตัวเอง
        if (name == deviceName) {
          Log.d('⛔ Skipped: Found self (name=$name)');
          return;
        }
        
        Log.d('✅ This is a different device, processing...');
        
        // ⚡ ถ้าเคย lost ไป → ลบออกจาก lost list (กลับมาแล้ว!)
        if (_lostPeers.containsKey(id)) {
          final lostTime = _lostPeers[id]!;
          final downDuration = DateTime.now().difference(lostTime);
          Log.d('🔄 Peer $id was lost for ${downDuration.inSeconds} seconds - reconnecting...');
          _lostPeers.remove(id);
        }
        
        _found.add(id);
        
        // ตรวจสอบว่ากำลัง connecting อยู่หรือเชื่อมต่อแล้วหรือไม่
        if (_pendingConnections.contains(id)) {
          Log.d('⏭️ Already connecting to $id, skip');
          return;
        }
        
        if (_connected.containsKey(id)) {
          Log.d('✅ Already connected to $id, skip');
          _emitPeers();
          return;
        }
        
        // ⚡ ถ้าเป็น persistent peer → ให้ priority สูง (reconnect เลย)
        final isPersistent = _persistentPeers.containsKey(id);
        if (isPersistent) {
          Log.d('⭐ Persistent peer detected - auto-reconnecting immediately');
        }
        
        // ⚠️ ป้องกัน bidirectional request: ใช้ชื่ออุปกรณ์เปรียบเทียบ
        // ฝั่งที่มีชื่อ "น้อยกว่า" (alphabetically) จะเป็นผู้ request
        // ฝั่งที่มีชื่อ "มากกว่า" จะรอรับการเชื่อมต่อ
        // 🔧 ยกเว้นสำหรับ persistent peers ให้ connect เลย
        final comparison = deviceName.compareTo(name);
        
        if (comparison > 0 && !isPersistent) {
          // deviceName > name → ฉันมีชื่อมากกว่า → รอให้อีกฝั่ง request (ยกเว้น persistent peers)
          Log.d('⏳ My name "$deviceName" > Peer name "$name"');
          Log.d('   Waiting for peer to initiate connection (I will accept via advertising)');
          
          // 🔧 แต่ถ้ารอนานเกิน 5 วินาที แล้วยังไม่มี connection → ลอง request เอง
          Future.delayed(const Duration(seconds: 5), () {
            if (!_connected.containsKey(id) && _found.contains(id)) {
              Log.d('⏰ Timeout waiting for peer $name to connect - initiating connection myself');
              _pendingConnections.add(id);
              final delay = isPersistent ? 500 : 1500;
              Future.delayed(Duration(milliseconds: delay), () {
                if (!_found.contains(id) || _connected.containsKey(id)) {
                  _pendingConnections.remove(id);
                  return;
                }
                _doRequestConnection(id);
              });
            }
          });
          
          return;
        } else if (comparison == 0 && !isPersistent) {
          // ชื่อเหมือนกัน (ไม่ควรเกิด แต่ป้องกันไว้) → ใช้ ID เป็นตัวตัดสิน
          final idComparison = deviceName.hashCode.compareTo(id.hashCode);
          if (idComparison >= 0) {
            Log.d('⏳ Same name - using ID comparison → waiting');
            return;
          }
        }
        
        Log.d('✅ My name "$deviceName" < Peer name "$name" ${isPersistent ? "(or persistent peer)" : ""}');
        Log.d('   I will initiate connection');
        
        // เพิ่มใน pending list
        _pendingConnections.add(id);
        
        // ⚡ ลด delay สำหรับ persistent peers (500ms แทน 1000ms)
        final delay = isPersistent ? 500 : 1500; // 🔧 เพิ่มเป็น 1500ms ให้ advertising พร้อม
        Log.d('📡 Endpoint found: $id (name: $name) - รอ ${delay}ms ให้ advertising พร้อม...');
        
        Future.delayed(Duration(milliseconds: delay), () {
          // ตรวจสอบว่า endpoint ยังอยู่ไหม
          if (!_found.contains(id)) {
            Log.d('⚠️ Endpoint $id หายไปแล้ว - ยกเลิกการเชื่อมต่อ');
            _pendingConnections.remove(id);
            return;
          }
          
          // ตรวจสอบอีกครั้งว่ายังไม่ได้เชื่อมต่อ
          if (_connected.containsKey(id)) {
            Log.d('✅ Already connected to $id during delay, skip request');
            _pendingConnections.remove(id);
            _emitPeers(); // ⚡ emit ทันทีเมื่อพบว่า connected แล้ว
            return;
          }
          
          // ลองเชื่อมต่อ
          Log.d('📞 Requesting connection to $id (after ${delay}ms delay - advertising should be ready)...');
          _doRequestConnection(id);
        });
        
        _emitPeers();
      },
      onEndpointLost: (id) {
        if (id == null) return;
        
        Log.d('🔴 Lost endpoint: $id');
        
        // ⚡ ถ้าเคยเชื่อมต่อแล้ว → เก็บไว้ใน persistent peers (ไม่ลบทันที)
        if (_connected.containsKey(id)) {
          Log.d('💾 Keeping peer $id in persistent list - will auto-reconnect if found again');
          _persistentPeers[id] = _connected[id]!;
          _lostPeers[id] = DateTime.now();
          
          // ⚡ ไม่ลบจาก _connected ทันที - ให้ onDisconnected จัดการ
          // ไม่ลบจาก _found เพื่อให้ยังแสดงใน UI (แต่ mark ว่าหายชั่วคราว)
        } else {
          // ถ้ายังไม่เคยเชื่อมต่อ (เจอแต่ยังไม่ได้ connect) → ลบได้เลย
          Log.d('   Peer was not connected - removing from _found');
          _found.remove(id);
        }
        
        _emitPeers();
      },
    );
    _isDiscovering = true;
    Log.d('✅ Discovery started successfully');
    } catch (e) {
      Log.d('❌ Nearby Discovery failed: $e');
      _state = DiscoveryState.idle;
      _isAdvertising = false;
      _isDiscovering = false;
      
      // ถ้าเจอ ALREADY_DISCOVERING error ให้ force stop และลองใหม่
      if (e.toString().contains('ALREADY_DISCOVERING') || e.toString().contains('8002')) {
        Log.d('⚠️ Already discovering - force stopping and retrying...');
        try {
          await Nearby().stopDiscovery();
          await Nearby().stopAdvertising();
          // ⚡ ลด delay จาก 1500ms → 1000ms
          await Future.delayed(const Duration(milliseconds: 1000));
          
          // ลองเริ่มใหม่อีกครั้ง (recursive call)
          Log.d('🔄 Retrying discovery after cleanup...');
          return await startDiscovery();
        } catch (stopError) {
          Log.d('⚠️ Error during force stop: $stopError');
          // ถ้ายังไม่ได้ ให้ throw error เพื่อบอกว่าต้องลองใหม่ทีหลัง
          throw Exception('Failed to start discovery. Please try again.');
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    try {
      // ตรวจสอบประเภทไฟล์
      final isVideo = filePath.toLowerCase().endsWith('.mp4') ||
                      filePath.toLowerCase().endsWith('.mov') ||
                      filePath.toLowerCase().endsWith('.avi');
      final fileType = isVideo ? 'วิดีโอ' : 'รูปภาพ';
      
      Log.d('📤 กำลังส่ง$fileType: $filePath');
      
      // ตรวจสอบว่าไฟล์มีอยู่จริง
      final file = File(filePath);
      if (!await file.exists()) {
        Log.d('❌ ไฟล์ไม่พบ: $filePath');
        throw Exception('File not found: $filePath');
      }
      
      final fileSize = await file.length();
      Log.d('📊 ขนาดไฟล์: ${(fileSize / 1024).toStringAsFixed(2)} KB');
      
      // สำหรับไฟล์เล็ก (<500KB) ส่งเป็น bytes
      // สำหรับไฟล์ใหญ่ ใช้ sendFilePayload
      if (fileSize < 500 * 1024) {
        Log.d('📦 ส่งแบบ bytes (ไฟล์เล็ก)');
        
        final bytes = await file.readAsBytes();
        
        // สร้าง payload: [file_marker][filename_length][filename][file_bytes]
        final marker = isVideo ? 'VIDEO:' : 'IMAGE:';
        final fileName = file.uri.pathSegments.last;
        final markerBytes = utf8.encode(marker);
        final fileNameBytes = utf8.encode(fileName);
        final fileNameLength = fileNameBytes.length;
        
        // สร้าง payload แบบรวม: [marker][length][name][data]
        final payload = Uint8List.fromList([
          ...markerBytes,
          fileNameLength,
          ...fileNameBytes,
          ...bytes,
        ]);
        
        Log.d('📦 ขนาด payload รวม: ${(payload.length / 1024).toStringAsFixed(2)} KB');
        
        // ส่งเป็น bytes payload
        if (to != null) {
          // ตรวจสอบว่าเชื่อมต่ออยู่จริงหรือไม่
          if (!_connected.containsKey(to.id)) {
            Log.d('❌ ไม่ได้เชื่อมต่อกับ ${to.name} (${to.id})');
            Log.d('   รายการที่เชื่อมต่อ: ${_connected.keys.toList()}');
            throw Exception('Not connected to ${to.name}');
          }
          
          Log.d('📤 ส่ง$fileType ไปยัง: ${to.name} (${to.id})');
          Log.d('   Connected: ${_connected.containsKey(to.id)}');
          await Nearby().sendBytesPayload(to.id, payload);
          Log.d('✅ sendBytesPayload เสร็จสิ้น');
        } else {
          Log.d('📡 Broadcast $fileType ไปยัง ${_connected.length} อุปกรณ์');
          for (final id in _connected.keys) {
            await Nearby().sendBytesPayload(id, payload);
          }
        }
      } else {
        // ไฟล์ใหญ่ - ใช้ sendFilePayload
        Log.d('📦 ส่งแบบ file payload (ไฟล์ใหญ่)');
        
        // ⚠️ ส่งข้อความบอกประเภทไฟล์ก่อน (สำหรับไฟล์ใหญ่)
        final fileName = file.uri.pathSegments.last;
        final metadataMessage = 'FILE_METADATA:${isVideo ? "VIDEO" : "IMAGE"}:$fileName';
        final metadataBytes = Uint8List.fromList(utf8.encode(metadataMessage));
        
        if (to != null) {
          Log.d('📤 ส่ง metadata ไปยัง: ${to.name}');
          await Nearby().sendBytesPayload(to.id, metadataBytes);
          await Future.delayed(const Duration(milliseconds: 200)); // รอให้ส่ง metadata ก่อน
          
          Log.d('📤 ส่ง$fileType ไปยัง: ${to.name} (${to.id})');
          await Nearby().sendFilePayload(to.id, filePath);
        } else {
          Log.d('📡 Broadcast metadata และ$fileType ไปยัง ${_connected.length} อุปกรณ์');
          for (final id in _connected.keys) {
            await Nearby().sendBytesPayload(id, metadataBytes);
            await Future.delayed(const Duration(milliseconds: 200));
            await Nearby().sendFilePayload(id, filePath);
          }
        }
      }
      
      Log.d('✅ ส่ง$fileType สำเร็จ');
    } catch (e, stackTrace) {
      Log.d('❌ ส่งไฟล์ล้มเหลว: $e');
      Log.d('Stack trace: $stackTrace');
      rethrow; // โยน error ต่อให้ UI จัดการ
    }
  }

  @override
  Future<void> stopDiscovery() async {
    Log.d('🔴 Stopping Nearby Discovery...');
    _state = DiscoveryState.idle;
    
    // Stop discovery first
    if (_isDiscovering) {
      try {
        await Nearby().stopDiscovery();
        _isDiscovering = false;
        Log.d('✅ Discovery stopped');
      } catch (e) {
        Log.d('⚠️ Failed to stop discovery: $e');
        _isDiscovering = false;
      }
    }
    
    // Then stop advertising
    if (_isAdvertising) {
      try {
        await Nearby().stopAdvertising();
        _isAdvertising = false;
        Log.d('✅ Advertising stopped');
      } catch (e) {
        Log.d('⚠️ Failed to stop advertising: $e');
        _isAdvertising = false;
      }
    }
    
    // Stop all connections
    try {
      await Nearby().stopAllEndpoints();
      Log.d('✅ All endpoints stopped');
    } catch (e) {
      Log.d('⚠️ Failed to stop all endpoints: $e');
    }
    
    _found.clear();
    _connected.clear();
    _pendingConnections.clear();
    _emitPeers();
  }

  /// 🆕 บังคับลบ persistent peer (ถ้าผู้ใช้ต้องการลบถาวร)
  void removePersistentPeer(String peerId) {
    Log.d('🗑️ Removing persistent peer: $peerId');
    _persistentPeers.remove(peerId);
    _lostPeers.remove(peerId);
    _connected.remove(peerId);
    _found.remove(peerId);
    _emitPeers();
  }

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    // แปลงข้อความเป็น UTF-8 bytes เพื่อรองรับภาษาไทย
    final bytes = utf8.encode(body);

    // แปลง List<int> เป็น Uint8List ก่อนส่ง
    final uint8Bytes = Uint8List.fromList(bytes);

    if (to != null) {
      // ส่งเจาะจง
      if (!_connected.containsKey(to.id)) {
        Log.d('⚠️ ยังไม่ได้เชื่อมต่อกับ ${to.name} (${to.id})');
        // ยังไม่ connect? ลอง request ต่อ
        // (ใน startDiscovery เราพยายาม auto-connect ไว้อยู่แล้ว)
      }
      Log.d('📤 ส่งข้อความถึง ${to.name} (${to.id})');
      await Nearby().sendBytesPayload(to.id, uint8Bytes);  // ส่งเป็น Uint8List
    } else {
      // broadcast = ส่งให้ทุกตัวที่เชื่อมอยู่
      Log.d('📡 Broadcast ข้อความไปยัง ${_connected.length} อุปกรณ์');
      for (final id in _connected.keys) {
        await Nearby().sendBytesPayload(id, uint8Bytes);  // ส่งเป็น Uint8List
      }
    }

    // ⚠️ ไม่ emit message จากตัวเอง เพราะจะทำให้ซ้ำ
    // AppState จะจัดการเพิ่มข้อความที่ส่งเอง
    Log.d('✅ ส่งข้อความเรียบร้อย: ${body.substring(0, body.length > 50 ? 50 : body.length)}...');
  }

  /// 🆕 บันทึกรูปภาพที่ได้รับเป็น bytes
  Future<void> _saveReceivedImage(Uint8List imageBytes, String originalFileName, String fromPeerId) async {
    try {
      Log.d('💾 กำลังบันทึกรูปภาพ: $originalFileName (${imageBytes.length} bytes)');
      
      // สร้างโฟลเดอร์เก็บรูปภาพ
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/received_images');
      
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
        Log.d('📁 สร้างโฟลเดอร์: ${imageDir.path}');
      }
      
      // สร้างชื่อไฟล์ใหม่
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = originalFileName.contains('.') 
          ? originalFileName.substring(originalFileName.lastIndexOf('.'))
          : '.jpg';
      final newFileName = 'image_$timestamp$extension';
      final filePath = '${imageDir.path}/$newFileName';
      
      Log.d('📝 บันทึกไปที่: $filePath');
      
      // บันทึกไฟล์
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      
      Log.d('✅ บันทึกรูปภาพสำเร็จ: $filePath (${imageBytes.length} bytes)');
      
      // ส่ง event ว่าได้รับรูปภาพแล้ว
      _fileCtrl.add(ReceivedFile(
        fromPeerId: fromPeerId,
        filePath: filePath,
        time: DateTime.now(),
      ));
    } catch (e) {
      Log.d('❌ บันทึกรูปภาพล้มเหลว: $e');
    }
  }

  /// 🆕 บันทึกวิดีโอที่ได้รับเป็น bytes
  Future<void> _saveReceivedVideo(Uint8List videoBytes, String originalFileName, String fromPeerId) async {
    try {
      // สร้างโฟลเดอร์เก็บวิดีโอ
      final appDir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${appDir.path}/received_videos');
      
      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }
      
      // สร้างชื่อไฟล์ใหม่
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = originalFileName.contains('.') 
          ? originalFileName.substring(originalFileName.lastIndexOf('.'))
          : '.mp4';
      final newFileName = 'video_$timestamp$extension';
      final filePath = '${videoDir.path}/$newFileName';
      
      // บันทึกไฟล์
      final file = File(filePath);
      await file.writeAsBytes(videoBytes);
      
      Log.d('✅ บันทึกวิดีโอสำเร็จ: $filePath (${videoBytes.length} bytes)');
      
      // ส่ง event ว่าได้รับวิดีโอแล้ว
      _fileCtrl.add(ReceivedFile(
        fromPeerId: fromPeerId,
        filePath: filePath,
        time: DateTime.now(),
      ));
    } catch (e) {
      Log.d('❌ บันทึกวิดีโอล้มเหลว: $e');
    }
  }

  /// 🆕 Copy ไฟล์จาก Content URI ไปเก็บถาวรใน App Directory  
  Future<String> _copyFileToPermanentStorage(String contentUri, {String? fileType}) async {
    try {
      Log.d('📋 กำลังคัดลอกไฟล์: $contentUri');
      Log.d('📋 File type from metadata: $fileType');
      
      // ตรวจสอบประเภทไฟล์:
      // 1. ใช้ fileType จาก metadata ก่อน (สำหรับไฟล์ใหญ่)
      // 2. ถ้าไม่มี ตรวจสอบจาก URI/extension
      bool isVideo;
      if (fileType != null) {
        isVideo = fileType == 'VIDEO';
        Log.d('✅ ใช้ประเภทไฟล์จาก metadata: ${isVideo ? "วิดีโอ" : "รูปภาพ"}');
      } else {
        isVideo = contentUri.toLowerCase().contains('.mp4') || 
                  contentUri.toLowerCase().contains('.mov') ||
                  contentUri.toLowerCase().contains('video');
        Log.d('⚠️ ไม่มี metadata, ตรวจสอบจาก URI: ${isVideo ? "วิดีโอ" : "รูปภาพ"}');
      }
      
      // สร้างโฟลเดอร์เก็บไฟล์ใน App Directory
      final appDir = await getApplicationDocumentsDirectory();
      final fileDir = Directory('${appDir.path}/${isVideo ? "received_videos" : "received_images"}');
      
      if (!await fileDir.exists()) {
        await fileDir.create(recursive: true);
        Log.d('📁 สร้างโฟลเดอร์: ${fileDir.path}');
      }
      
      // สร้างชื่อไฟล์ปลายทาง
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = isVideo ? '.mp4' : '.jpg';
      final prefix = isVideo ? 'video' : 'image';
      final newFileName = '${prefix}_$timestamp$extension';
      final destinationPath = '${fileDir.path}/$newFileName';
      
      // ลอง copy ไฟล์จาก content URI
      final uri = Uri.parse(contentUri);
      
      // วิธีที่ 1: ใช้ File API ถ้าเป็น file:// หรือ path ปกติ
      if (!contentUri.startsWith('content://')) {
        final sourceFile = File(uri.path);
        if (await sourceFile.exists()) {
          await sourceFile.copy(destinationPath);
          Log.d('✅ คัดลอกไฟล์สำเร็จ: $destinationPath');
          return destinationPath;
        }
      }
      
      // วิธีที่ 2: สำหรับ content:// URI - อ่าน bytes แล้วเขียนใหม่
      if (contentUri.startsWith('content://')) {
        try {
          // ใช้ method channel เพื่ออ่านไฟล์จาก content URI
          const platform = MethodChannel('com.example.offgrid_sos/files');
          final Uint8List? bytes = await platform.invokeMethod('readContentUri', contentUri);
          
          if (bytes != null && bytes.isNotEmpty) {
            // เขียนไฟล์
            final destinationFile = File(destinationPath);
            await destinationFile.writeAsBytes(bytes);
            Log.d('✅ คัดลอกไฟล์สำเร็จ (method channel): $destinationPath (${bytes.length} bytes)');
            return destinationPath;
          }
        } catch (e) {
          Log.d('⚠️ Method channel failed, trying file system: $e');
        }
        
        // Fallback: ลองใช้ file system โดยตรง
        // Nearby Connections อาจเก็บไฟล์ไว้ใน cache ที่เข้าถึงได้
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final fileId = pathSegments.last;
          final cacheDir = await getTemporaryDirectory();
          
          // ลองหาในหลายตำแหน่ง
          final possiblePaths = [
            '${cacheDir.path}/nearby_connections/$fileId',
            '${cacheDir.path}/$fileId',
            uri.path, // ลอง path จาก URI โดยตรง
          ];
          
          for (final possiblePath in possiblePaths) {
            try {
              final testFile = File(possiblePath);
              if (await testFile.exists()) {
                await testFile.copy(destinationPath);
                Log.d('✅ คัดลอกสำเร็จจาก: $possiblePath');
                return destinationPath;
              }
            } catch (e) {
              // ลองต่อไป
            }
          }
        }
      }
      
      Log.d('⚠️ ไม่สามารถ copy ไฟล์ได้ ใช้ URI เดิม');
      return contentUri;
      
    } catch (e, stackTrace) {
      Log.d('❌ เกิดข้อผิดพลาดในการคัดลอกไฟล์: $e');
      Log.d('Stack trace: $stackTrace');
      return contentUri;
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    _peersCtrl.close();
    _msgCtrl.close();
  }
}
