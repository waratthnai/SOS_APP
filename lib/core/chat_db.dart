import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'chat_models.dart';

class ChatDB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'chat.db');
    return await openDatabase(
      path,
      version: 4, // เพิ่ม version เพื่อสร้าง peers table
      onCreate: (db, v) async {
        // ตาราง chat_messages
        await db.execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            sender TEXT NOT NULL,
            receiver TEXT,
            type TEXT NOT NULL,
            text TEXT,
            filePath TEXT,
            time INTEGER NOT NULL,
            status TEXT DEFAULT 'sent',
            isEmergency INTEGER DEFAULT 0
          )
        ''');
        // ตาราง peers - เก็บชื่ออุปกรณ์
        await db.execute('''
          CREATE TABLE peers (
            peer_id TEXT PRIMARY KEY,
            peer_name TEXT NOT NULL,
            last_seen INTEGER NOT NULL
          )
        ''');
        // เพิ่ม index เพื่อเพิ่มความเร็วในการ query
        await db.execute('CREATE INDEX idx_user_id ON chat_messages(user_id)');
        await db.execute('CREATE INDEX idx_conversation ON chat_messages(user_id, sender, receiver)');
        await db.execute('CREATE INDEX idx_status ON chat_messages(status)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // อัปเกรดจาก version 1 เป็น 2
          await db.execute('ALTER TABLE chat_messages ADD COLUMN user_id TEXT');
          await db.execute('ALTER TABLE chat_messages ADD COLUMN receiver TEXT');
          await db.execute('CREATE INDEX idx_user_id ON chat_messages(user_id)');
          await db.execute('CREATE INDEX idx_conversation ON chat_messages(user_id, sender, receiver)');
        }
        if (oldVersion < 3) {
          // อัปเกรดจาก version 2 เป็น 3 (เพิ่ม status และ isEmergency)
          // ตรวจสอบว่า column มีอยู่แล้วหรือไม่ก่อนเพิ่ม
          try {
            await db.execute('ALTER TABLE chat_messages ADD COLUMN status TEXT DEFAULT "sent"');
          } catch (e) {
            // Column อาจมีอยู่แล้ว ข้ามไป
            print('Column status already exists: $e');
          }
          try {
            await db.execute('ALTER TABLE chat_messages ADD COLUMN isEmergency INTEGER DEFAULT 0');
          } catch (e) {
            // Column อาจมีอยู่แล้ว ข้ามไป
            print('Column isEmergency already exists: $e');
          }
          try {
            await db.execute('CREATE INDEX idx_status ON chat_messages(status)');
          } catch (e) {
            // Index อาจมีอยู่แล้ว ข้ามไป
            print('Index idx_status already exists: $e');
          }
        }
        if (oldVersion < 4) {
          // อัปเกรดจาก version 3 เป็น 4 (เพิ่ม peers table)
          try {
            await db.execute('''
              CREATE TABLE peers (
                peer_id TEXT PRIMARY KEY,
                peer_name TEXT NOT NULL,
                last_seen INTEGER NOT NULL
              )
            ''');
          } catch (e) {
            print('Table peers already exists: $e');
          }
        }
      },
    );
  }
  
  // 👥 บันทึก/อัพเดท Peer (บันทึกชื่ออุปกรณ์)
  static Future<void> savePeerName(String peerId, String peerName) async {
    final database = await db;
    await database.insert(
      'peers',
      {
        'peer_id': peerId,
        'peer_name': peerName,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  // 👥 ดึงชื่อ Peer จาก ID
  static Future<String?> getPeerName(String peerId) async {
    final database = await db;
    final maps = await database.query(
      'peers',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
    if (maps.isEmpty) return null;
    return maps.first['peer_name'] as String?;
  }

  static Future<void> insertMessage(ChatMessage m, String userId, {String? receiver}) async {
    final database = await db;
    await database.insert(
      'chat_messages',
      {
        'id': m.id,
        'user_id': userId,
        'sender': m.from,
        'receiver': receiver,
        'type': m.type.name,
        'text': m.text,
        'filePath': m.filePath,
        'time': m.time.millisecondsSinceEpoch,
        'status': m.status.name,
        'isEmergency': m.isEmergency ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  // อัพเดทสถานะข้อความ
  static Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final database = await db;
    await database.update(
      'chat_messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
  
  // ดึงข้อความที่มีสถานะ pending (รอส่ง)
  static Future<List<ChatMessage>> getPendingMessages(String userId) async {
    final database = await db;
    final maps = await database.query(
      'chat_messages',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, MessageStatus.pending.name],
      orderBy: 'time ASC',
    );
    return _mapsToChatMessages(maps);
  }
  
  // ดึงข้อความที่ส่งแล้วแต่ยังไม่ซิงก์ (sent but not synced)
  static Future<List<ChatMessage>> getUnsyncedMessages(String userId) async {
    final database = await db;
    final maps = await database.query(
      'chat_messages',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, MessageStatus.sent.name],
      orderBy: 'time ASC',
    );
    return _mapsToChatMessages(maps);
  }
  
  // Helper function to convert maps to ChatMessages
  static List<ChatMessage> _mapsToChatMessages(List<Map<String, dynamic>> maps) {
    return maps.map((m) {
      MessageStatus status;
      try {
        status = MessageStatus.values.firstWhere(
          (e) => e.name == (m['status'] as String? ?? 'sent'),
        );
      } catch (e) {
        status = MessageStatus.sent;
      }
      
      return ChatMessage(
        id: m['id'] as String,
        from: m['sender'] as String,
        receiver: m['receiver'] as String?, // เพิ่ม receiver
        type: ChatType.values.firstWhere((e) => e.name == m['type']),
        text: m['text'] as String?,
        filePath: m['filePath'] as String?,
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        status: status,
        isEmergency: (m['isEmergency'] as int?) == 1,
      );
    }).toList();
  }

  // ดึงข้อความทั้งหมดของ user
  static Future<List<ChatMessage>> getMessages(String userId) async {
    final database = await db;
    final maps = await database.query(
      'chat_messages',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'time DESC',
    );
    return _mapsToChatMessages(maps);
  }

  // ดึงข้อความในห้องแชทระหว่าง user กับ peer
  static Future<List<ChatMessage>> getConversation(String userId, String peerId) async {
    final database = await db;
    final maps = await database.query(
      'chat_messages',
      where: 'user_id = ? AND ((sender = ? AND receiver = ?) OR (sender = ? AND receiver = ?))',
      whereArgs: [userId, userId, peerId, peerId, userId],
      orderBy: 'time ASC',
    );
    return _mapsToChatMessages(maps);
  }

  // ลบข้อความทั้งหมดของ user (ตอน logout)
  /// ลบการสนทนาทั้งหมดกับ peer คนหนึ่ง
  static Future<void> deleteConversation(String userId, String peerId) async {
    final database = await db;
    await database.delete(
      'chat_messages',
      where: 'user_id = ? AND (sender = ? OR receiver = ?)',
      whereArgs: [userId, peerId, peerId],
    );
  }

  /// ลบข้อความเดียว (ตาม message ID)
  static Future<void> deleteMessage(String messageId) async {
    final database = await db;
    await database.delete(
      'chat_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
    print('[ChatDB] 🗑️ Deleted message: $messageId');
  }

  static Future<void> clearUserMessages(String userId) async {
    final database = await db;
    await database.delete(
      'chat_messages',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// อัปเดต userId ของข้อความเก่าจาก anonymous เป็น userId ใหม่
  static Future<void> migrateAnonymousMessages(String newUserId) async {
    final database = await db;
    final count = await database.update(
      'chat_messages',
      {'user_id': newUserId},
      where: 'user_id = ?',
      whereArgs: ['anonymous'],
    );
    if (count > 0) {
      print('[ChatDB] 🔄 Migrated $count anonymous messages to user $newUserId');
    }
  }
}