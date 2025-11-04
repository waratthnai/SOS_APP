import 'dart:async';

/// อุปกรณ์ปลายทาง
class Peer {
  final String id;
  final String name;
  final bool nearby; // ไกล้/ไกล
  const Peer({required this.id, required this.name, this.nearby = true});
}

/// ข้อความที่ส่ง-รับ
class Message {
  final String fromPeerId;
  final String? toPeerId; // null = broadcast
  final String body;
  final DateTime time;
  const Message({
    required this.fromPeerId,
    required this.body,
    this.toPeerId,
    required this.time,
  });
}

/// ไฟล์ที่ได้รับ
class ReceivedFile {
  final String fromPeerId;
  final String filePath; // path ของไฟล์ที่บันทึกในเครื่อง
  final DateTime time;
  const ReceivedFile({
    required this.fromPeerId,
    required this.filePath,
    required this.time,
  });
}

/// สถานะการค้นหา
enum DiscoveryState { idle, scanning }

/// สัญญาประกาศชั้นสื่อสาร (Wi-Fi Direct / BLE / อื่นๆ)
abstract class Transport {
  DiscoveryState get discoveryState;

  /// peers ปัจจุบัน
  Stream<List<Peer>> get onPeers;

  /// ข้อความที่เข้ามา
  Stream<Message> get onMessage;

  /// เริ่มค้นหาเพื่อนรอบๆ
  Future<void> startDiscovery();

  /// หยุดค้นหา
  Future<void> stopDiscovery();

  /// ส่งข้อความ (ถ้า to == null = broadcast)
  Future<void> sendMessage(String body, {Peer? to});

  /// ส่งไฟล์ (รูปภาพ, วิดีโอ, etc.)
  Future<void> sendFile(String filePath, {Peer? to});

  /// ปิดทรัพยากร
  Future<void> dispose();
}
