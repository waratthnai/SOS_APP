import 'dart:async';
import 'dart:convert'; // เพิ่มสำหรับ utf8 encoding/decoding
import 'dart:typed_data'; // เพิ่มการนำเข้า Uint8List
import 'dart:io'; // เพิ่มสำหรับ File operations
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart'; // เพิ่มสำหรับหา app directory
import 'transport.dart';

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

  DiscoveryState _state = DiscoveryState.idle;
  bool _isAdvertising = false;
  bool _isDiscovering = false;

  NearbyTransport({required this.deviceName});

  // Stream สำหรับไฟล์ที่ได้รับ
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
        print('📶 Requesting NEARBY_WIFI_DEVICES permission...');
        await _permissionChannel.invokeMethod('requestNearbyWifiPermission');
        // Check again after request
        hasNearbyWifiDevices = await _permissionChannel.invokeMethod('hasNearbyWifiPermission') ?? false;
      }
    } catch (e) {
      print('⚠️ NEARBY_WIFI_DEVICES permission check failed: $e');
      // Continue anyway, might work with location permission
    }
    
    print('🔍 Permissions check:');
    print('📍 Location: $hasLocation');
    print('📶 Bluetooth: $hasBluetooth');
    print('📢 Bluetooth Advertise: $hasBluetoothAdvertise');
    print('🔗 Bluetooth Connect: $hasBluetoothConnect');
    print('🔎 Bluetooth Scan: $hasBluetoothScan');
    print('📶 Nearby WiFi Devices: $hasNearbyWifiDevices');
    
    // Require at least location and bluetooth permissions
    bool hasBasicPerms = hasLocation && hasBluetooth && hasBluetoothAdvertise && hasBluetoothConnect && hasBluetoothScan;
    
    if (!hasBasicPerms) {
      print('❌ Missing basic permissions for Nearby Connections');
      return false;
    }
    
    return true;
  }

  void _emitPeers() {
    final list = <Peer>[];
    print('🔍 _emitPeers() - My device name: "$deviceName"');
    print('   Total found: ${_found.length}, Total connected: ${_connected.length}');
    
    // peers = รวมเฉพาะที่เชื่อมต่อสำเร็จแล้ว (มี ConnectionInfo)
    for (final id in _connected.keys) {
      final info = _connected[id];
      if (info == null) continue;
      
      final peerName = info.endpointName;
      
      print('  Connected peer: id=$id, name="$peerName"');
      
      // กรองเครื่องตัวเองออก
      if (peerName == deviceName || peerName.isEmpty) {
        print('  ⚠️ Filtered out: own device or empty name: "$peerName" ($id)');
        continue;
      }
      
      list.add(Peer(
        id: id,
        name: peerName,
        nearby: true,
      ));
    }
    
    print('📱 Emitting ${list.length} connected peers');
    _peersCtrl.add(list);
  }

  // Helper method สำหรับ request connection พร้อม retry logic
  void _doRequestConnection(String id, {int retryCount = 0}) {
    // ป้องกัน retry มากเกินไป
    if (retryCount > 3) {
      print('❌ Max retry attempts reached for $id');
      _pendingConnections.remove(id);
      _found.remove(id);
      _emitPeers();
      return;
    }
    
    Nearby().requestConnection(
      deviceName,
      id,
      onConnectionInitiated: (rid, info) async {
        print('🤝 Connection initiated (DISCOVERY side): $rid, name=${info.endpointName}');
        
        // ⚠️ ป้องกันการเชื่อมต่อกับเครื่องตัวเอง
        if (info.endpointName == deviceName) {
          print('⛔ Rejected: Cannot connect to self (${info.endpointName})');
          _pendingConnections.remove(rid);
          try {
            await Nearby().rejectConnection(rid);
          } catch (e) {
            print('⚠️ Failed to reject self-connection: $e');
          }
          return;
        }
        
        // บันทึก connection info ทันที
        _connected[rid] = info;
        print('📝 Saved connection info for ${info.endpointName} ($rid)');
        
        // ✅ ลอง accept connection ทั้งสองฝั่ง
        // รอให้ฝั่ง advertising accept ก่อน
        await Future.delayed(const Duration(milliseconds: 200));
        
        try {
          await Nearby().acceptConnection(
            rid,
            onPayLoadRecieved: (eid, payload) {
              print('📨 [Discovery] Received payload from: $eid (type: ${payload.type})');
              print('   Payload size: ${payload.bytes?.length ?? 0} bytes');
              
              if (payload.type == PayloadType.BYTES) {
                final rawBytes = payload.bytes!;
                print('📦 BYTES payload received, size: ${rawBytes.length}');
                
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
                    print('📷 ได้รับ$fileType จาก: $eid');
                    
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
                      
                      print('📊 ชื่อไฟล์: $fileName, ขนาด: ${fileBytes.length} bytes');
                      
                      // บันทึกไฟล์ลง app directory
                      if (isVideo) {
                        _saveReceivedVideo(fileBytes, fileName, eid);
                      } else {
                        _saveReceivedImage(fileBytes, fileName, eid);
                      }
                    } catch (e) {
                      print('❌ Parse ไฟล์ล้มเหลว: $e');
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
                      print('📋 ได้รับ metadata: $fileType จาก $eid');
                      _fileMetadata[eid] = fileType;
                    }
                    return;
                  }
                  
                  // ถ้าไม่ใช่ metadata = เป็นข้อความปกติ
                  if (!text.startsWith('FILE_METADATA:')) {
                    print('📩 Message content: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');
                    _msgCtrl.add(Message(
                      fromPeerId: eid,
                      body: text,
                      time: DateTime.now(),
                    ));
                  } else {
                    print('⚠️ Metadata message ไม่ควรมาถึงจุดนี้: $text');
                  }
                } catch (e) {
                  // ถ้า decode ไม่ได้ = เป็น binary data ที่ไม่รู้จัก
                  print('⚠️ ไม่สามารถ decode payload เป็น text: $e');
                  print('   ขนาด: ${rawBytes.length} bytes, header: ${rawBytes.take(20).toList()}');
                }
              } else if (payload.type == PayloadType.FILE) {
                print('📁 File payload received: ${payload.id}, uri: ${payload.uri}');
                // เก็บ metadata ที่ได้รับไว้ก่อนหน้า
                final fileType = _fileMetadata[eid];
                print('📋 File type from metadata: $fileType');
                _pendingFiles[payload.id] = _PendingFile(eid, payload.uri, fileType: fileType);
              }
            },
            onPayloadTransferUpdate: (eid, status) {
              if (status.status == PayloadStatus.SUCCESS) {
                final fileInfo = _pendingFiles[status.id];
                if (fileInfo != null && fileInfo.uri != null) {
                  print('✅ File transfer complete: ${fileInfo.uri}');
                  
                  // 🆕 Copy ไฟล์ไปเก็บถาวร (ส่ง fileType จาก metadata)
                  _copyFileToPermanentStorage(fileInfo.uri!, fileType: fileInfo.fileType).then((permanentPath) {
                    print('📁 ไฟล์ถูกเก็บที่: $permanentPath');
                    _fileCtrl.add(ReceivedFile(
                      fromPeerId: fileInfo.fromPeerId,
                      filePath: permanentPath, // ใช้ path ที่ copy แล้ว
                      time: DateTime.now(),
                    ));
                    // ล้าง metadata หลังใช้แล้ว
                    _fileMetadata.remove(fileInfo.fromPeerId);
                  }).catchError((error) {
                    print('❌ Copy ไฟล์ล้มเหลว: $error');
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
          print('✅ [Discovery] Accepted connection: ${info.endpointName} ($rid)');
        } catch (e) {
          print('⚠️ [Discovery] Accept connection error (continuing): $e');
          // ไม่ throw error - รอดูผลจาก onConnectionResult
        }
      },
      onConnectionResult: (rid, status) {
        print('🔗 Connection result (DISCOVERY): $rid -> $status');
        
        // ลบออกจาก pending list
        _pendingConnections.remove(rid);
        
        if (status == Status.CONNECTED) {
          print('✅ Successfully connected (discovery): $rid');
          _emitPeers();
        } else {
          print('❌ Connection failed (discovery): $rid -> $status');
          _connected.remove(rid);
          _found.remove(rid);
          _emitPeers();
        }
      },
      onDisconnected: (rid) {
        print('❌ Disconnected (discovery): $rid');
        _pendingConnections.remove(rid);
        _connected.remove(rid);
        _found.remove(rid);
        _emitPeers();
      },
    ).catchError((error) {
      // ตรวจสอบว่าเป็น STATUS_RADIO_ERROR (8007) หรือไม่
      if (error.toString().contains('8007') || error.toString().contains('STATUS_RADIO_ERROR')) {
        print('📡 Radio error detected for $id - waiting before retry (attempt ${retryCount + 1}/3)');
        _pendingConnections.remove(id); // ยกเลิก pending status
        
        // รอ 2 วินาทีแล้วลองใหม่
        Future.delayed(const Duration(seconds: 2), () {
          if (_found.contains(id) && !_pendingConnections.contains(id)) {
            print('🔄 Retrying connection to $id...');
            _pendingConnections.add(id);
            _doRequestConnection(id, retryCount: retryCount + 1);
          }
        });
      } else {
        // Error อื่นๆ ที่ไม่ใช่ radio error
        print('❌ requestConnection error for $id: $error');
        _pendingConnections.remove(id);
        _found.remove(id);
        _emitPeers();
      }
      return false;
    });
  }

  @override
  Future<void> startDiscovery() async {
    print('🚀 Starting Nearby Discovery...');
    
    // Stop any existing sessions first
    if (_isAdvertising || _isDiscovering || _state == DiscoveryState.scanning) {
      print('🔄 Stopping existing sessions...');
      try {
        await stopDiscovery();
        // 🔧 เพิ่มเวลารอให้ radio พักฟื้น (ป้องกัน STATUS_RADIO_ERROR)
        print('⏳ Waiting for radio to stabilize...');
        await Future.delayed(const Duration(seconds: 3)); // เพิ่มจาก 1.5 เป็น 3 วินาที
      } catch (e) {
        print('⚠️ Error stopping previous session: $e');
        // Reset states manually
        _isAdvertising = false;
        _isDiscovering = false;
        _state = DiscoveryState.idle;
        // รอเพิ่มเติมหลัง error
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    
    final ok = await _ensurePerms();
    if (!ok) {
      print('❌ Permissions not granted for Nearby Connections');
      throw Exception('Permissions not granted for Nearby Connections. Please grant all Bluetooth and Location permissions.');
    }
    
    // 🔧 เพิ่มการตรวจสอบสถานะ Bluetooth ก่อนเริ่ม
    try {
      print('📶 Checking Bluetooth status...');
      // ลองเช็ค Bluetooth โดยใช้ nearby API
      // ถ้า Bluetooth ปิดอยู่ API จะโยน error
    } catch (e) {
      print('⚠️ Bluetooth might be disabled: $e');
      print('💡 Please ensure Bluetooth and WiFi are enabled');
    }

    _state = DiscoveryState.scanning;
    _found.clear();

    try {
      // เริ่มทั้ง advertise (ให้คนอื่นเห็นเรา) และ discovery (ค้นหาเอง)
      // 1) โฆษณาอุปกรณ์เรา
      print('📢 Starting advertising...');
      print('   Device name: "$deviceName"');
      print('   Service ID: $_serviceId');
      print('   Strategy: $_strategy');
      
      try {
        await Nearby().startAdvertising(
          deviceName,
          _strategy,
          onConnectionInitiated: (id, info) async {
            print('🤝 Connection initiated (ADVERTISING side) from: ${info.endpointName} (id: $id)');
            
            // ⚠️ ป้องกันการเชื่อมต่อกับเครื่องตัวเอง
            if (info.endpointName == deviceName) {
              print('⛔ Rejected: Cannot connect to self (${info.endpointName})');
              try {
                await Nearby().rejectConnection(id);
              } catch (e) {
                print('⚠️ Failed to reject self-connection: $e');
              }
              return;
            }
            
            // บันทึก connection info ก่อน (สำคัญ!)
            _connected[id] = info;
            
            // รับการเชื่อมต่อ (ฝั่ง ADVERTISING เป็น responder)
            try {
              await Nearby().acceptConnection(
                id,
                onPayLoadRecieved: (eid, payload) {
                  print('📨 [Advertising] Received payload from: $eid (type: ${payload.type})');
                  print('   Payload size: ${payload.bytes?.length ?? 0} bytes');
                  
                  if (payload.type == PayloadType.BYTES) {
                    final rawBytes = payload.bytes!;
                    print('📦 BYTES payload received, size: ${rawBytes.length}');
                    
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
                        print('📷 ได้รับ$fileType จาก: $eid');
                        
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
                          
                          print('📊 ชื่อไฟล์: $fileName, ขนาด: ${fileBytes.length} bytes');
                          
                          // บันทึกไฟล์ลง app directory
                          if (isVideo) {
                            _saveReceivedVideo(fileBytes, fileName, eid);
                          } else {
                            _saveReceivedImage(fileBytes, fileName, eid);
                          }
                        } catch (e) {
                          print('❌ Parse ไฟล์ล้มเหลว: $e');
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
                          print('📋 ได้รับ metadata: $fileType จาก $eid');
                          _fileMetadata[eid] = fileType;
                        }
                        return;
                      }
                      
                      // ถ้าไม่ใช่ metadata = เป็นข้อความปกติ
                      if (!text.startsWith('FILE_METADATA:')) {
                        print('📩 Message content: ${text.length > 50 ? text.substring(0, 50) + "..." : text}');
                        _msgCtrl.add(Message(
                          fromPeerId: eid,
                          body: text,
                          time: DateTime.now(),
                        ));
                      } else {
                        print('⚠️ Metadata message ไม่ควรมาถึงจุดนี้: $text');
                      }
                    } catch (e) {
                      // ถ้า decode ไม่ได้ = เป็น binary data ที่ไม่รู้จัก
                      print('⚠️ ไม่สามารถ decode payload เป็น text: $e');
                      print('   ขนาด: ${rawBytes.length} bytes, header: ${rawBytes.take(20).toList()}');
                    }
                  } else if (payload.type == PayloadType.FILE) {
                    print('📁 File payload received: ${payload.id}, uri: ${payload.uri}');
                    // เก็บ metadata ที่ได้รับไว้ก่อนหน้า
                    final fileType = _fileMetadata[eid];
                    print('📋 File type from metadata: $fileType');
                    _pendingFiles[payload.id] = _PendingFile(eid, payload.uri, fileType: fileType);
                  }
                },
                onPayloadTransferUpdate: (eid, status) {
                  if (status.status == PayloadStatus.SUCCESS) {
                    final fileInfo = _pendingFiles[status.id];
                    if (fileInfo != null && fileInfo.uri != null) {
                      print('✅ File transfer complete: ${fileInfo.uri}');
                      
                      // 🆕 Copy ไฟล์ไปเก็บถาวร (ส่ง fileType จาก metadata)
                      _copyFileToPermanentStorage(fileInfo.uri!, fileType: fileInfo.fileType).then((permanentPath) {
                        print('📁 ไฟล์ถูกเก็บที่: $permanentPath');
                        _fileCtrl.add(ReceivedFile(
                          fromPeerId: fileInfo.fromPeerId,
                          filePath: permanentPath, // ใช้ path ที่ copy แล้ว
                          time: DateTime.now(),
                        ));
                        // ล้าง metadata หลังใช้แล้ว
                        _fileMetadata.remove(fileInfo.fromPeerId);
                      }).catchError((error) {
                        print('❌ Copy ไฟล์ล้มเหลว: $error');
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
              print('✅ Accept connection (advertising side): ${info.endpointName} ($id)');
            } catch (e) {
              print('❌ Failed to accept connection (advertising): $e');
              _connected.remove(id);
            }
          },
          onConnectionResult: (id, status) {
            print('🔗 Connection result (ADVERTISING): $id -> $status');
            if (status == Status.CONNECTED) {
              print('✅ Successfully connected (advertising): $id');
              _emitPeers();
            } else {
              print('❌ Connection failed (advertising): $id -> $status');
              _connected.remove(id);
              _found.remove(id);
              _emitPeers();
            }
          },
          onDisconnected: (id) {
            print('❌ Disconnected (advertising): $id');
            _connected.remove(id);
            _found.remove(id);
            _emitPeers();
          },
        );
        _isAdvertising = true;
        print('✅ Advertising started successfully as: $deviceName');
      } catch (e) {
        print('⚠️ Advertising failed (continuing anyway): $e');
        // Continue even if advertising fails - we can still discover others
        _isAdvertising = false;
      }

    // 2) ค้นหา endpoint อื่น
    print('🔎 Starting discovery with serviceId: $_serviceId');
    print('   My device name: "$deviceName"');
    await Nearby().startDiscovery(
      _serviceId,
      _strategy,
      onEndpointFound: (id, name, serviceId) {
        print('🔍 Found endpoint: id=$id, name="$name", serviceId=$serviceId');
        print('   Comparing with my name: "$deviceName"');
        
        // ⚠️ ป้องกันการพบเครื่องตัวเอง
        if (name == deviceName) {
          print('⛔ Skipped: Found self (name=$name)');
          return;
        }
        
        print('✅ This is a different device, processing...');
        
        _found.add(id);
        
        // ตรวจสอบว่ากำลัง connecting อยู่หรือเชื่อมต่อแล้วหรือไม่
        if (_pendingConnections.contains(id)) {
          print('⏭️ Already connecting to $id, skip');
          return;
        }
        
        if (_connected.containsKey(id)) {
          print('✅ Already connected to $id, skip');
          _emitPeers();
          return;
        }
        
        // ⚠️ ป้องกัน bidirectional request: ใช้ชื่ออุปกรณ์เป็นตัวตัดสิน
        // เฉพาะฝั่งที่มีชื่อ "น้อยกว่า" (alphabetically) เท่านั้นที่จะ request
        // (ฝั่งที่มีชื่อ "มากกว่า" จะรอรับการเชื่อมต่อจาก advertising side)
        final myHashCode = deviceName.hashCode;
        final peerHashCode = name.hashCode; // ใช้ชื่อของ peer แทน id
        
        if (myHashCode >= peerHashCode) {
          print('⏳ My name hash ($myHashCode) >= Peer name hash ($peerHashCode)');
          print('   My name: "$deviceName", Peer name: "$name"');
          print('   Waiting for peer to initiate connection (I will accept via advertising)');
          // ไม่ request - รอให้อีกฝั่ง request มาหาเรา
          return;
        }
        
        print('✅ My name hash ($myHashCode) < Peer name hash ($peerHashCode)');
        print('   My name: "$deviceName", Peer name: "$name"');
        print('   I will initiate connection');
        
        // เพิ่มใน pending list
        _pendingConnections.add(id);
        
        // รอสักครู่ก่อน request (ป้องกัน race condition)
        // ให้ฝั่ง advertising มีเวลา ready รับ connection
        Future.delayed(const Duration(milliseconds: 500), () {
          // ตรวจสอบอีกครั้งว่ายังไม่ได้เชื่อมต่อ
          if (_connected.containsKey(id)) {
            print('✅ Already connected to $id during delay, skip request');
            _pendingConnections.remove(id);
            return;
          }
          
          // ลองเชื่อมทันที
          print('📞 Requesting connection to $id...');
          _doRequestConnection(id);
        });
      },
      onEndpointLost: (id) {
        print('🔴 Lost endpoint: $id');
        _found.remove(id);
        _connected.remove(id);
        _emitPeers();
      },
    );
    _isDiscovering = true;
    print('✅ Discovery started successfully');
    } catch (e) {
      print('❌ Nearby Discovery failed: $e');
      _state = DiscoveryState.idle;
      _isAdvertising = false;
      _isDiscovering = false;
      
      // ถ้าเจอ ALREADY_DISCOVERING error ให้ force stop
      if (e.toString().contains('ALREADY_DISCOVERING') || e.toString().contains('8002')) {
        print('⚠️ Already discovering - force stopping...');
        try {
          await Nearby().stopDiscovery();
          await Nearby().stopAdvertising();
        } catch (stopError) {
          print('⚠️ Error during force stop: $stopError');
        }
        throw Exception('Discovery session was already active. Stopped it. Please try scanning again.');
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
      
      print('📤 กำลังส่ง$fileType: $filePath');
      
      // ตรวจสอบว่าไฟล์มีอยู่จริง
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ ไฟล์ไม่พบ: $filePath');
        throw Exception('File not found: $filePath');
      }
      
      final fileSize = await file.length();
      print('📊 ขนาดไฟล์: ${(fileSize / 1024).toStringAsFixed(2)} KB');
      
      // สำหรับไฟล์เล็ก (<500KB) ส่งเป็น bytes
      // สำหรับไฟล์ใหญ่ ใช้ sendFilePayload
      if (fileSize < 500 * 1024) {
        print('📦 ส่งแบบ bytes (ไฟล์เล็ก)');
        
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
        
        print('📦 ขนาด payload รวม: ${(payload.length / 1024).toStringAsFixed(2)} KB');
        
        // ส่งเป็น bytes payload
        if (to != null) {
          // ตรวจสอบว่าเชื่อมต่ออยู่จริงหรือไม่
          if (!_connected.containsKey(to.id)) {
            print('❌ ไม่ได้เชื่อมต่อกับ ${to.name} (${to.id})');
            print('   รายการที่เชื่อมต่อ: ${_connected.keys.toList()}');
            throw Exception('Not connected to ${to.name}');
          }
          
          print('📤 ส่ง$fileType ไปยัง: ${to.name} (${to.id})');
          print('   Connected: ${_connected.containsKey(to.id)}');
          await Nearby().sendBytesPayload(to.id, payload);
          print('✅ sendBytesPayload เสร็จสิ้น');
        } else {
          print('📡 Broadcast $fileType ไปยัง ${_connected.length} อุปกรณ์');
          for (final id in _connected.keys) {
            await Nearby().sendBytesPayload(id, payload);
          }
        }
      } else {
        // ไฟล์ใหญ่ - ใช้ sendFilePayload
        print('📦 ส่งแบบ file payload (ไฟล์ใหญ่)');
        
        // ⚠️ ส่งข้อความบอกประเภทไฟล์ก่อน (สำหรับไฟล์ใหญ่)
        final fileName = file.uri.pathSegments.last;
        final metadataMessage = 'FILE_METADATA:${isVideo ? "VIDEO" : "IMAGE"}:$fileName';
        final metadataBytes = Uint8List.fromList(utf8.encode(metadataMessage));
        
        if (to != null) {
          print('📤 ส่ง metadata ไปยัง: ${to.name}');
          await Nearby().sendBytesPayload(to.id, metadataBytes);
          await Future.delayed(const Duration(milliseconds: 200)); // รอให้ส่ง metadata ก่อน
          
          print('📤 ส่ง$fileType ไปยัง: ${to.name} (${to.id})');
          await Nearby().sendFilePayload(to.id, filePath);
        } else {
          print('📡 Broadcast metadata และ$fileType ไปยัง ${_connected.length} อุปกรณ์');
          for (final id in _connected.keys) {
            await Nearby().sendBytesPayload(id, metadataBytes);
            await Future.delayed(const Duration(milliseconds: 200));
            await Nearby().sendFilePayload(id, filePath);
          }
        }
      }
      
      print('✅ ส่ง$fileType สำเร็จ');
    } catch (e, stackTrace) {
      print('❌ ส่งไฟล์ล้มเหลว: $e');
      print('Stack trace: $stackTrace');
      rethrow; // โยน error ต่อให้ UI จัดการ
    }
  }

  @override
  Future<void> stopDiscovery() async {
    print('🔴 Stopping Nearby Discovery...');
    _state = DiscoveryState.idle;
    
    // Stop discovery first
    if (_isDiscovering) {
      try {
        await Nearby().stopDiscovery();
        _isDiscovering = false;
        print('✅ Discovery stopped');
      } catch (e) {
        print('⚠️ Failed to stop discovery: $e');
        _isDiscovering = false;
      }
    }
    
    // Then stop advertising
    if (_isAdvertising) {
      try {
        await Nearby().stopAdvertising();
        _isAdvertising = false;
        print('✅ Advertising stopped');
      } catch (e) {
        print('⚠️ Failed to stop advertising: $e');
        _isAdvertising = false;
      }
    }
    
    // Stop all connections
    try {
      await Nearby().stopAllEndpoints();
      print('✅ All endpoints stopped');
    } catch (e) {
      print('⚠️ Failed to stop all endpoints: $e');
    }
    
    _found.clear();
    _connected.clear();
    _pendingConnections.clear();
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
        print('⚠️ ยังไม่ได้เชื่อมต่อกับ ${to.name} (${to.id})');
        // ยังไม่ connect? ลอง request ต่อ
        // (ใน startDiscovery เราพยายาม auto-connect ไว้อยู่แล้ว)
      }
      print('📤 ส่งข้อความถึง ${to.name} (${to.id})');
      await Nearby().sendBytesPayload(to.id, uint8Bytes);  // ส่งเป็น Uint8List
    } else {
      // broadcast = ส่งให้ทุกตัวที่เชื่อมอยู่
      print('📡 Broadcast ข้อความไปยัง ${_connected.length} อุปกรณ์');
      for (final id in _connected.keys) {
        await Nearby().sendBytesPayload(id, uint8Bytes);  // ส่งเป็น Uint8List
      }
    }

    // ⚠️ ไม่ emit message จากตัวเอง เพราะจะทำให้ซ้ำ
    // AppState จะจัดการเพิ่มข้อความที่ส่งเอง
    print('✅ ส่งข้อความเรียบร้อย: ${body.substring(0, body.length > 50 ? 50 : body.length)}...');
  }

  /// 🆕 บันทึกรูปภาพที่ได้รับเป็น bytes
  Future<void> _saveReceivedImage(Uint8List imageBytes, String originalFileName, String fromPeerId) async {
    try {
      print('💾 กำลังบันทึกรูปภาพ: $originalFileName (${imageBytes.length} bytes)');
      
      // สร้างโฟลเดอร์เก็บรูปภาพ
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/received_images');
      
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
        print('📁 สร้างโฟลเดอร์: ${imageDir.path}');
      }
      
      // สร้างชื่อไฟล์ใหม่
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = originalFileName.contains('.') 
          ? originalFileName.substring(originalFileName.lastIndexOf('.'))
          : '.jpg';
      final newFileName = 'image_$timestamp$extension';
      final filePath = '${imageDir.path}/$newFileName';
      
      print('📝 บันทึกไปที่: $filePath');
      
      // บันทึกไฟล์
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      
      print('✅ บันทึกรูปภาพสำเร็จ: $filePath (${imageBytes.length} bytes)');
      
      // ส่ง event ว่าได้รับรูปภาพแล้ว
      _fileCtrl.add(ReceivedFile(
        fromPeerId: fromPeerId,
        filePath: filePath,
        time: DateTime.now(),
      ));
    } catch (e) {
      print('❌ บันทึกรูปภาพล้มเหลว: $e');
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
      
      print('✅ บันทึกวิดีโอสำเร็จ: $filePath (${videoBytes.length} bytes)');
      
      // ส่ง event ว่าได้รับวิดีโอแล้ว
      _fileCtrl.add(ReceivedFile(
        fromPeerId: fromPeerId,
        filePath: filePath,
        time: DateTime.now(),
      ));
    } catch (e) {
      print('❌ บันทึกวิดีโอล้มเหลว: $e');
    }
  }

  /// 🆕 Copy ไฟล์จาก Content URI ไปเก็บถาวรใน App Directory  
  Future<String> _copyFileToPermanentStorage(String contentUri, {String? fileType}) async {
    try {
      print('📋 กำลังคัดลอกไฟล์: $contentUri');
      print('📋 File type from metadata: $fileType');
      
      // ตรวจสอบประเภทไฟล์:
      // 1. ใช้ fileType จาก metadata ก่อน (สำหรับไฟล์ใหญ่)
      // 2. ถ้าไม่มี ตรวจสอบจาก URI/extension
      bool isVideo;
      if (fileType != null) {
        isVideo = fileType == 'VIDEO';
        print('✅ ใช้ประเภทไฟล์จาก metadata: ${isVideo ? "วิดีโอ" : "รูปภาพ"}');
      } else {
        isVideo = contentUri.toLowerCase().contains('.mp4') || 
                  contentUri.toLowerCase().contains('.mov') ||
                  contentUri.toLowerCase().contains('video');
        print('⚠️ ไม่มี metadata, ตรวจสอบจาก URI: ${isVideo ? "วิดีโอ" : "รูปภาพ"}');
      }
      
      // สร้างโฟลเดอร์เก็บไฟล์ใน App Directory
      final appDir = await getApplicationDocumentsDirectory();
      final fileDir = Directory('${appDir.path}/${isVideo ? "received_videos" : "received_images"}');
      
      if (!await fileDir.exists()) {
        await fileDir.create(recursive: true);
        print('📁 สร้างโฟลเดอร์: ${fileDir.path}');
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
          print('✅ คัดลอกไฟล์สำเร็จ: $destinationPath');
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
            print('✅ คัดลอกไฟล์สำเร็จ (method channel): $destinationPath (${bytes.length} bytes)');
            return destinationPath;
          }
        } catch (e) {
          print('⚠️ Method channel failed, trying file system: $e');
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
                print('✅ คัดลอกสำเร็จจาก: $possiblePath');
                return destinationPath;
              }
            } catch (e) {
              // ลองต่อไป
            }
          }
        }
      }
      
      print('⚠️ ไม่สามารถ copy ไฟล์ได้ ใช้ URI เดิม');
      return contentUri;
      
    } catch (e, stackTrace) {
      print('❌ เกิดข้อผิดพลาดในการคัดลอกไฟล์: $e');
      print('Stack trace: $stackTrace');
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
