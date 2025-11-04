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
      version: 2, // เพิ่ม version เพื่ออัปเกรด schema
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            sender TEXT NOT NULL,
            receiver TEXT,
            type TEXT NOT NULL,
            text TEXT,
            filePath TEXT,
            time INTEGER NOT NULL
          )
        ''');
        // เพิ่ม index เพื่อเพิ่มความเร็วในการ query
        await db.execute('CREATE INDEX idx_user_id ON chat_messages(user_id)');
        await db.execute('CREATE INDEX idx_conversation ON chat_messages(user_id, sender, receiver)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // อัปเกรดจาก version 1 เป็น 2
          await db.execute('ALTER TABLE chat_messages ADD COLUMN user_id TEXT');
          await db.execute('ALTER TABLE chat_messages ADD COLUMN receiver TEXT');
          await db.execute('CREATE INDEX idx_user_id ON chat_messages(user_id)');
          await db.execute('CREATE INDEX idx_conversation ON chat_messages(user_id, sender, receiver)');
        }
      },
    );
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    return maps.map((m) => ChatMessage(
      id: m['id'] as String,
      from: m['sender'] as String,
      type: ChatType.values.firstWhere((e) => e.name == m['type']),
      text: m['text'] as String?,
      filePath: m['filePath'] as String?,
      time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
    )).toList();
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
    return maps.map((m) => ChatMessage(
      id: m['id'] as String,
      from: m['sender'] as String,
      type: ChatType.values.firstWhere((e) => e.name == m['type']),
      text: m['text'] as String?,
      filePath: m['filePath'] as String?,
      time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
    )).toList();
  }

  // ลบข้อความทั้งหมดของ user (ตอน logout)
  static Future<void> clearUserMessages(String userId) async {
    final database = await db;
    await database.delete(
      'chat_messages',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}