// lib/ui/chat_history_screen.dart
import 'package:flutter/material.dart';
import '../core/chat_models.dart';
import '../core/chat_db.dart';
import '../core/friend_service.dart'; // สำหรับ global friendService
import '../core/transport.dart'; // สำหรับ Peer class
import '../core/app_state.dart'; // สำหรับ global appState
import '../core/device_id_manager.dart'; // สำหรับ Device ID
import 'emergency_chat_screen.dart'; // สำหรับเปิดห้องแชท

/// Model สำหรับเก็บข้อมูลห้องแชท
class ChatRoom {
  final String peerId;
  final String peerName;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final DateTime lastMessageTime;

  ChatRoom({
    required this.peerId,
    required this.peerName,
    this.lastMessage,
    this.unreadCount = 0,
    required this.lastMessageTime,
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

  @override
  void initState() {
    super.initState();
    _loadChatRooms();
  }

  Future<void> _loadChatRooms() async {
    setState(() => _isLoading = true);
    try {
      final userId = friendService.currentUser?.id ?? 'anonymous';
      
      // ดึง Device ID ปัจจุบัน (อาจเป็น device ID หรือ user ID)
      final myDeviceId = await DeviceIdManager.getCurrentId();
      
      final messages = await ChatDB.getMessages(userId);
      
      // จัดกลุ่มข้อความตาม peer (ใช้คู่สนทนาแทนการแยก sender/receiver)
      final Map<String, List<ChatMessage>> groupedMessages = {};
      
      for (final msg in messages) {
        String? peerId;
        
        // ดึง peerId จากฐานข้อมูล
        final database = await ChatDB.db;
        final msgData = await database.query(
          'chat_messages',
          where: 'id = ?',
          whereArgs: [msg.id],
          limit: 1,
        );
        
        if (msgData.isNotEmpty) {
          final sender = msgData.first['sender'] as String?;
          final receiver = msgData.first['receiver'] as String?;
          
          // 🔄 หา peer ID โดยดูว่าใครที่ไม่ใช่เรา
          // ถ้า sender เป็นเรา → peer คือ receiver
          // ถ้า sender ไม่ใช่เรา → peer คือ sender
          if (sender == myDeviceId || sender == userId || sender == 'me') {
            peerId = receiver;
          } else {
            peerId = sender;
          }
        }
        
        if (peerId == null || peerId.isEmpty) continue;
        
        // 🎯 Key point: ใช้ peerId เดียวกันสำหรับทั้งส่งและรับ
        if (!groupedMessages.containsKey(peerId)) {
          groupedMessages[peerId] = [];
        }
        groupedMessages[peerId]!.add(msg);
      }
      
      // สร้างรายการห้องแชท
      final List<ChatRoom> rooms = [];
      for (final entry in groupedMessages.entries) {
        final peerId = entry.key;
        final messages = entry.value;
        
        // เรียงตามเวลาเพื่อหาข้อความล่าสุด
        messages.sort((a, b) => b.time.compareTo(a.time));
        final lastMessage = messages.first;
        
        // หาชื่อ peer จาก appState.peers (nearby connections)
        // ถ้าไม่เจอ → ดึงจาก SQLite peers table (ชื่อที่บันทึกไว้)
        String peerName = peerId;
        
        // ลองหาจาก peers ที่เชื่อมต่ออยู่
        final peer = appState.peers.firstWhere(
          (p) => p.id == peerId,
          orElse: () => Peer(id: '', name: ''),
        );
        
        if (peer.id.isNotEmpty && peer.name.isNotEmpty) {
          peerName = peer.name;
        } else {
          // ดึงชื่อจาก SQLite peers table (ชื่อที่บันทึกไว้)
          final savedName = await ChatDB.getPeerName(peerId);
          if (savedName != null && savedName.isNotEmpty) {
            peerName = savedName;
          } else {
            // ถ้าไม่มีเลย ใช้ peerId แบบย่อ
            peerName = 'ID: ${peerId.substring(0, peerId.length > 8 ? 8 : peerId.length)}...';
          }
        }
        
        // นับข้อความที่ยังไม่ได้อ่าน (ถ้ามี unread flag)
        final unreadCount = 0; // TODO: implement unread count
        
        rooms.add(ChatRoom(
          peerId: peerId,
          peerName: peerName,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
          lastMessageTime: lastMessage.time,
        ));
      }
      
      // เรียงตามเวลาล่าสุด
      rooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      
      setState(() {
        _chatRooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading chat rooms: $e');
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
        // ลบข้อความทั้งหมดจากห้องแชทนี้
        await ChatDB.deleteConversation(userId, room.peerId);
        
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
        debugPrint('Error deleting chat room: $e');
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
    // สร้าง Peer object จาก room
    final peer = Peer(
      id: room.peerId,
      name: room.peerName,
    );
    
    // เปิดห้องแชทกับ peer นี้
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmergencyChatScreen(
          peer: peer,
        ),
      ),
    ).then((_) {
      // Reload เมื่อกลับมา
      _loadChatRooms();
    });
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

  Widget _buildSummaryCard(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<List<ChatMessage>>(
            future: ChatDB.getMessages(friendService.currentUser?.id ?? 'anonymous'),
            builder: (context, snapshot) {
              final allMessages = snapshot.data ?? [];
              final pendingCount = allMessages.where((m) => m.status == MessageStatus.pending).length;
              final sentCount = allMessages.where((m) => m.status == MessageStatus.sent).length;
              final syncedCount = allMessages.where((m) => m.status == MessageStatus.synced).length;
              final emergencyCount = allMessages.where((m) => m.isEmergency).length;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'สถานะข้อความ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.schedule,
                          label: 'รอส่ง',
                          value: '$pendingCount',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.check,
                          label: 'ส่งแล้ว',
                          value: '$sentCount',
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.cloud_done,
                          label: 'ซิงก์แล้ว',
                          value: '$syncedCount',
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.warning_amber,
                          label: 'ฉุกเฉิน',
                          value: '$emergencyCount',
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('แชท'),
        actions: [
          // ปุ่ม Force Sync
          IconButton(
            icon: const Icon(Icons.cloud_sync),
            onPressed: () async {
              // แสดง loading
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 12),
                      Text('กำลังซิงก์กับ Firebase...'),
                    ],
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
              
              // Force sync
              await appState.forceSyncWithFirebase();
              
              // โหลดข้อมูลใหม่
              await _loadChatRooms();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ ซิงก์เสร็จสิ้น'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            tooltip: 'Force Sync กับ Firebase',
          ),
          // ปุ่ม Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChatRooms,
            tooltip: 'รีเฟรช',
          ),
        ],
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
                        color: cs.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ยังไม่มีการสนทนา',
                        style: TextStyle(
                          fontSize: 18,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'เริ่มต้นแชทกับเพื่อนของคุณ',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChatRooms,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _chatRooms.length + 1, // +1 สำหรับ summary card
                    itemBuilder: (context, index) {
                      // Summary card ที่ index 0
                      if (index == 0) {
                        return _buildSummaryCard(cs);
                      }
                      
                      // Chat rooms
                      final room = _chatRooms[index - 1];
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
                                color: cs.outline.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: cs.primaryContainer,
                                child: Icon(
                                  Icons.person,
                                  size: 30,
                                  color: cs.onPrimaryContainer,
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
                                            color: cs.onSurface.withOpacity(0.6),
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
                                            lastMsg?.text ?? lastMsg?.type.name ?? '',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: cs.onSurface.withOpacity(0.7),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        
                                        // Emergency badge
                                        if (lastMsg?.isEmergency == true)
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
