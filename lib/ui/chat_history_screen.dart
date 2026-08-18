// lib/ui/chat_history_screen.dart
import 'package:flutter/material.dart';
import '../core/chat_models.dart';
import '../core/chat_db.dart';
import '../core/friend_service.dart';
import '../core/friend_models.dart';
import '../core/transport.dart';
import '../core/app_state.dart';
import '../core/device_id_manager.dart';
import 'emergency_chat_screen.dart';
import 'friend_chat_screen.dart';
import 'package:offgrid_sos/core/logger.dart';

/// Model สำหรับเก็บข้อมูลห้องแชท
class ChatRoom {
  final String peerId;
  final String peerName;
  final ChatMessage? lastMessage;
  final String? lastMessageText; // สำหรับ friend chats ที่ไม่มี ChatMessage
  final int unreadCount;
  final DateTime lastMessageTime;
  final Friend? friend; // null = emergency/nearby, non-null = friend chat

  ChatRoom({
    required this.peerId,
    required this.peerName,
    this.lastMessage,
    this.lastMessageText,
    this.unreadCount = 0,
    required this.lastMessageTime,
    this.friend,
  });
}

/// หน้าประวัติการแชททั้งหมด (แสดงเป็นรายการห้องแชท)
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<ChatRoom> _chatRooms = [];
  bool _isLoading = true;
  int _lastMessageCount = -1;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    friendService.addListener(_onFriendServiceChanged);
    _loadChatRooms();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    friendService.removeListener(_onFriendServiceChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    final count = appState.chatMessages.length;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      _loadChatRooms();
    }
  }

  void _onFriendServiceChanged() {
    if (friendService.currentUser == null) {
      // user logout — clear immediately
      if (mounted) {
        setState(() {
          _chatRooms = [];
          _isLoading = false;
        });
      }
      return;
    }
    _loadChatRooms();
  }

  Future<void> _loadChatRooms() async {
    setState(() => _isLoading = true);
    try {
      final userId = friendService.currentUser?.id ?? 'anonymous';
      final myDeviceId = await DeviceIdManager.getCurrentId();

      // ดึงข้อความทั้งหมดในคำสั่ง SQL เดียว — ไม่มี N+1 query อีกต่อไป
      // ChatMessage.from = sender, ChatMessage.receiver = receiver (ถูก map ใน _mapsToChatMessages)
      final messages = await ChatDB.getMessages(userId);

      // จัดกลุ่มข้อความตาม peer โดยใช้ข้อมูลจาก ChatMessage โดยตรง
      final Map<String, List<ChatMessage>> groupedMessages = {};

      for (final msg in messages) {
        // msg.from = sender, msg.receiver = receiver — ไม่ต้อง query DB ซ้ำ
        final String? peerId;
        if (msg.from == myDeviceId || msg.from == userId || msg.from == 'me') {
          peerId = msg.receiver; // เราเป็นคนส่ง → peer คือ receiver
        } else {
          peerId = msg.from; // peer เป็นคนส่ง → peer คือ sender
        }

        if (peerId == null || peerId.isEmpty) continue;

        groupedMessages.putIfAbsent(peerId, () => []).add(msg);
      }

      // ดึงชื่อ peer ทั้งหมดพร้อมกัน (batch query 1 ครั้ง แทนการ query ทีละ peer)
      final allPeerIds = groupedMessages.keys.toList();
      final peerNameCache = <String, String>{};
      for (final peerId in allPeerIds) {
        final live = appState.peers.firstWhere(
          (p) => p.id == peerId,
          orElse: () => Peer(id: '', name: ''),
        );
        if (live.id.isNotEmpty && live.name.isNotEmpty) {
          peerNameCache[peerId] = live.name;
        } else {
          final saved = await ChatDB.getPeerName(peerId);
          peerNameCache[peerId] = saved?.isNotEmpty == true
              ? saved!
              : 'ID: ${peerId.substring(0, peerId.length > 8 ? 8 : peerId.length)}...';
        }
      }

      // สร้างรายการห้องแชท (emergency/nearby จาก ChatDB)
      final List<ChatRoom> rooms = [];
      for (final entry in groupedMessages.entries) {
        final peerId = entry.key;
        final msgs = entry.value..sort((a, b) => b.time.compareTo(a.time));
        final lastMessage = msgs.first;
        final unreadCount = msgs.where((m) => m.from == peerId && !m.isRead).length;

        rooms.add(ChatRoom(
          peerId: peerId,
          peerName: peerNameCache[peerId] ?? peerId,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
          lastMessageTime: lastMessage.time,
        ));
      }

      // รวม friend chats — โหลดจาก Firebase ผ่าน loadFriendChatMessages
      // เพื่อให้ B เห็น history ที่ A ส่งมา แม้ B เพิ่งลงชื่อเข้าใช้
      if (friendService.friends.isNotEmpty) {
        await Future.wait(
          friendService.friends.map((f) => appState.loadFriendChatMessages(f.userId)),
        );
      }

      final myUserId = friendService.currentUser?.id ?? '';
      for (final friend in friendService.friends) {
        // ไม่ซ้ำกับ emergency room ที่ peerId เดียวกัน
        if (rooms.any((r) => r.peerId == friend.userId)) continue;

        final msgs = appState.friendChats[friend.userId] ?? [];

        // ถ้าไม่มีข้อความเลย และ lastMessage ใน friend record ก็ว่าง — ข้าม
        if (msgs.isEmpty && friend.lastMessage == null && friend.lastMessageTime == null) continue;

        final lastMsg = msgs.isNotEmpty ? msgs.last : null;
        final lastText = lastMsg?.text ??
            (lastMsg?.type == ChatType.image
                ? '📷 รูปภาพ'
                : lastMsg?.type == ChatType.video
                    ? '🎥 วิดีโอ'
                    : friend.lastMessage);

        final unread = msgs.where((m) => m.toUserId == myUserId && !m.isRead).length;

        rooms.add(ChatRoom(
          peerId: friend.userId,
          peerName: friend.name,
          lastMessageText: lastText,
          unreadCount: unread > 0 ? unread : friend.unreadCount,
          lastMessageTime: lastMsg?.time ?? friend.lastMessageTime ?? friend.lastSeen,
          friend: friend,
        ));
      }

      rooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

      setState(() {
        _chatRooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      Log.d('Error loading chat rooms: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteChatRoom(ChatRoom room) async {
    final userId = friendService.currentUser?.id ?? 'anonymous';
    
    // แสดง confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบการสนทนา'),
        content: Text('ต้องการลบการสนทนากับ ${room.peerName} ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        if (room.friend != null) {
          await appState.clearFriendChat(room.friend!.userId);
        } else {
          await ChatDB.deleteConversation(userId, room.peerId);
        }
        
        // Reload รายการ
        _loadChatRooms();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ลบการสนทนากับ ${room.peerName} แล้ว'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        Log.d('Error deleting chat room: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เกิดข้อผิดพลาดในการลบ'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _openChatRoom(ChatRoom room) {
    if (room.friend != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FriendChatScreen(friend: room.friend!),
        ),
      ).then((_) => _loadChatRooms());
      return;
    }

    final peer = Peer(id: room.peerId, name: room.peerName);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmergencyChatScreen(peer: peer),
      ),
    ).then((_) => _loadChatRooms());
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'เมื่อวาน';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} วันที่แล้ว';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  Color _getStatusColor(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return Colors.orange;
      case MessageStatus.sent:
        return Colors.grey;
      case MessageStatus.delivered:
        return Colors.blue;
      case MessageStatus.synced:
        return Colors.green;
    }
  }

  IconData _getStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.synced:
        return Icons.cloud_done;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('แชท'),
        actions: const [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chatRooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ยังไม่มีการสนทนา',
                        style: TextStyle(
                          fontSize: 18,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'เริ่มต้นแชทกับเพื่อนของคุณ',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChatRooms,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _chatRooms.length,
                    itemBuilder: (context, index) {
                      final room = _chatRooms[index];
                      final lastMsg = room.lastMessage;
                      
                      return InkWell(
                        onTap: () => _openChatRoom(room),
                        onLongPress: () => _deleteChatRoom(room),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: cs.outline.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Avatar — เพื่อนใช้ไอคอน person_outline สีเขียว, emergency ใช้ไอคอน wifi สีแดง
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: room.friend != null
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : cs.primaryContainer,
                                child: Icon(
                                  room.friend != null ? Icons.person_outline : Icons.wifi,
                                  size: 30,
                                  color: room.friend != null
                                      ? Colors.green
                                      : cs.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // ข้อมูลแชท
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            room.peerName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          _formatTime(room.lastMessageTime),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurface.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        // Status icon
                                        if (lastMsg != null && lastMsg.from == 'me') ...[
                                          Icon(
                                            _getStatusIcon(lastMsg.status),
                                            size: 14,
                                            color: _getStatusColor(lastMsg.status),
                                          ),
                                          const SizedBox(width: 4),
                                        ],

                                        // ข้อความล่าสุด
                                        Expanded(
                                          child: Text(
                                            room.lastMessageText ?? lastMsg?.text ?? lastMsg?.type.name ?? '',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: cs.onSurface.withValues(alpha: 0.7),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),

                                        // Unread badge
                                        if (room.unreadCount > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: cs.primary,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                                              style: TextStyle(
                                                color: cs.onPrimary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],

                                        // Emergency badge
                                        if (lastMsg?.isEmergency == true) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'SOS',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

