// lib/core/message_queue_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_models.dart';
import 'package:offgrid_sos/core/logger.dart';

/// Service จัดการคิวข้อความที่รอส่ง และซิงก์ขึ้น Cloud
class MessageQueueService extends ChangeNotifier {
  static final MessageQueueService _instance = MessageQueueService._internal();
  factory MessageQueueService() => _instance;
  MessageQueueService._internal();

  // คิวข้อความที่รอส่ง (pending messages)
  final List<ChatMessage> _pendingQueue = [];

  // คิวข้อความที่รอซิงก์ขึ้น Cloud (sent but not synced)
  final List<ChatMessage> _syncQueue = [];

  // สถานะการเชื่อมต่อ
  bool _isOnline = false;
  bool _isP2PConnected = false;

  // Timer สำหรับ retry
  Timer? _retryTimer;
  Timer? _syncTimer;

  // Handler ที่ต้องตั้งจากภายนอก (AppState) เพื่อไม่ให้ service นี้ผูกกับ Transport/Firebase ตรงๆ
  Future<bool> Function(ChatMessage message)? _sendHandler;
  Future<bool> Function(ChatMessage message)? _syncHandler;

  /// ตั้ง handler สำหรับส่งข้อความจริงผ่าน Transport
  void setSendHandler(Future<bool> Function(ChatMessage message) handler) {
    _sendHandler = handler;
  }

  /// ตั้ง handler สำหรับซิงก์ข้อความขึ้น Cloud จริง
  void setSyncHandler(Future<bool> Function(ChatMessage message) handler) {
    _syncHandler = handler;
  }

  // Getters
  List<ChatMessage> get pendingQueue => List.unmodifiable(_pendingQueue);
  List<ChatMessage> get syncQueue => List.unmodifiable(_syncQueue);
  bool get isOnline => _isOnline;
  bool get isP2PConnected => _isP2PConnected;

  /// เริ่มต้น Service
  Future<void> init() async {
    await _loadQueuesFromStorage();
    _startRetryTimer();
    _startSyncTimer();
  }

  /// โหลดคิวจาก SharedPreferences
  Future<void> _loadQueuesFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // โหลด pending queue
      final pendingJson = prefs.getString('pending_messages');
      if (pendingJson != null) {
        final List<dynamic> list = jsonDecode(pendingJson);
        _pendingQueue.clear();
        _pendingQueue.addAll(
          list.map((json) => ChatMessage.fromJson(json)).toList(),
        );
      }

      // โหลด sync queue
      final syncJson = prefs.getString('sync_messages');
      if (syncJson != null) {
        final List<dynamic> list = jsonDecode(syncJson);
        _syncQueue.clear();
        _syncQueue.addAll(
          list.map((json) => ChatMessage.fromJson(json)).toList(),
        );
      }

      Log.d(
        '📦 โหลดคิวข้อความ: ${_pendingQueue.length} รอส่ง, ${_syncQueue.length} รอซิงก์',
      );
    } catch (e) {
      Log.d('❌ โหลดคิวไม่สำเร็จ: $e');
    }
  }

  /// บันทึกคิวลง SharedPreferences
  Future<void> _saveQueuesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // บันทึก pending queue
      final pendingJson = jsonEncode(
        _pendingQueue.map((msg) => msg.toJson()).toList(),
      );
      await prefs.setString('pending_messages', pendingJson);

      // บันทึก sync queue
      final syncJson = jsonEncode(
        _syncQueue.map((msg) => msg.toJson()).toList(),
      );
      await prefs.setString('sync_messages', syncJson);

      Log.d('💾 บันทึกคิวข้อความแล้ว');
    } catch (e) {
      Log.d('❌ บันทึกคิวไม่สำเร็จ: $e');
    }
  }

  /// เพิ่มข้อความเข้าคิว (เมื่อส่งไม่สำเร็จ)
  Future<void> addToPendingQueue(ChatMessage message) async {
    _pendingQueue.add(message.copyWith(status: MessageStatus.pending));
    await _saveQueuesToStorage();
    notifyListeners();
    Log.d('📥 เพิ่มข้อความเข้าคิว: ${message.id}');
  }

  /// เพิ่มข้อความเข้าคิวซิงก์ (เมื่อส่ง P2P สำเร็จแล้ว)
  Future<void> addToSyncQueue(ChatMessage message) async {
    // ลบออกจาก pending queue ถ้ามี
    _pendingQueue.removeWhere((m) => m.id == message.id);

    // เพิ่มเข้า sync queue
    _syncQueue.add(message.copyWith(status: MessageStatus.sent));
    await _saveQueuesToStorage();
    notifyListeners();
    Log.d('📤 เพิ่มข้อความเข้าคิวซิงก์: ${message.id}');
  }

  /// ลบข้อความออกจากคิว (เมื่อซิงก์สำเร็จแล้ว)
  Future<void> removeFromSyncQueue(String messageId) async {
    _syncQueue.removeWhere((m) => m.id == messageId);
    await _saveQueuesToStorage();
    notifyListeners();
    Log.d('✅ ลบข้อความออกจากคิวซิงก์: $messageId');
  }

  /// อัพเดทสถานะการเชื่อมต่อ P2P
  void updateP2PConnection(bool connected) {
    _isP2PConnected = connected;
    notifyListeners();

    if (connected && _pendingQueue.isNotEmpty) {
      Log.d('🔄 เชื่อมต่อ P2P แล้ว - พยายามส่งข้อความที่ค้างอยู่');
      _retryPendingMessages();
    }
  }

  /// อัพเดทสถานะการเชื่อมต่ออินเทอร์เน็ต
  void updateOnlineStatus(bool online) {
    _isOnline = online;
    notifyListeners();

    if (online && _syncQueue.isNotEmpty) {
      Log.d('🌐 ออนไลน์แล้ว - พยายามซิงก์ข้อความ');
      _syncToCloud();
    }
  }

  /// Timer สำหรับ retry ส่งข้อความที่ค้างอยู่
  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isP2PConnected && _pendingQueue.isNotEmpty) {
        _retryPendingMessages();
      }
    });
  }

  /// Timer สำหรับซิงก์ข้อความขึ้น Cloud
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isOnline && _syncQueue.isNotEmpty) {
        _syncToCloud();
      }
    });
  }

  /// retry ข้อความชิ้นเดียวจาก messageId (ใช้จาก UI)
  Future<void> retryMessage(String messageId) async {
    if (_sendHandler == null) return;
    final msg = _pendingQueue.cast<ChatMessage?>().firstWhere(
      (m) => m?.id == messageId,
      orElse: () => null,
    );
    if (msg == null) return;
    try {
      final success = await _sendHandler!(msg);
      if (success) {
        Log.d('✅ Retry สำเร็จ: ${msg.id}');
        await addToSyncQueue(msg);
      }
    } catch (e) {
      Log.d('❌ Retry error: ${msg.id} - $e');
    }
  }

  /// พยายามส่งข้อความที่ค้างอยู่ใหม่
  Future<void> _retryPendingMessages() async {
    if (_pendingQueue.isEmpty || _sendHandler == null) return;

    Log.d('🔄 กำลัง retry ส่งข้อความ ${_pendingQueue.length} ข้อความ...');

    for (final msg in List.from(_pendingQueue)) {
      try {
        final success = await _sendHandler!(msg);
        if (success) {
          Log.d('✅ Retry สำเร็จ: ${msg.id}');
          await addToSyncQueue(msg);
        } else {
          Log.d('❌ Retry ไม่สำเร็จ: ${msg.id}');
        }
      } catch (e) {
        Log.d('❌ Retry error: ${msg.id} - $e');
      }
    }
  }

  /// ซิงก์ข้อความขึ้น Cloud
  Future<void> _syncToCloud() async {
    if (_syncQueue.isEmpty || _syncHandler == null) return;

    Log.d('☁️ กำลังซิงก์ข้อความขึ้น Cloud ${_syncQueue.length} ข้อความ...');

    for (final msg in List.from(_syncQueue)) {
      try {
        final success = await _syncHandler!(msg);
        if (success) {
          Log.d('✅ ซิงก์สำเร็จ: ${msg.id}');
          await removeFromSyncQueue(msg.id);
        } else {
          Log.d('❌ ซิงก์ไม่สำเร็จ: ${msg.id}');
        }
      } catch (e) {
        Log.d('❌ Sync error: ${msg.id} - $e');
      }
    }
  }

  /// ดึงสถานะของข้อความ
  MessageStatus getMessageStatus(String messageId) {
    // เช็คว่าอยู่ในคิวไหน
    if (_pendingQueue.any((m) => m.id == messageId)) {
      return MessageStatus.pending;
    }
    if (_syncQueue.any((m) => m.id == messageId)) {
      return MessageStatus.sent;
    }
    // ถ้าไม่อยู่ในคิวแสดงว่าซิงก์แล้ว
    return MessageStatus.synced;
  }

  /// ล้างคิวทั้งหมด
  Future<void> clearAllQueues() async {
    _pendingQueue.clear();
    _syncQueue.clear();
    await _saveQueuesToStorage();
    notifyListeners();
    Log.d('🗑️ ล้างคิวข้อความทั้งหมดแล้ว');
  }

  /// ทำลาย Service
  @override
  void dispose() {
    _retryTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
