// lib/ui/friends_screen.dart
import 'package:flutter/material.dart';
import '../core/friend_service.dart';
import '../core/friend_models.dart';
import '../core/app_state.dart'; // เพิ่ม import AppState
import 'friend_chat_screen.dart';
import 'add_friend_screen.dart';
import 'friend_requests_screen.dart';
import 'friend_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 🔥 Sync ทันทีเมื่อเข้าหน้านี้
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);
    try {
      await friendService.syncWithFirebase();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เพื่อน',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: cs.surface,
        actions: [
          // ปุ่ม Refresh
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refresh,
            tooltip: 'รีเฟรช',
          ),
          // Friend Requests Badge
          AnimatedBuilder(
            animation: friendService,
            builder: (context, _) {
              final requestCount = friendService.friendRequests.length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.person_add),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FriendRequestsScreen(),
                        ),
                      );
                    },
                  ),
                  if (requestCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$requestCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Add Friend Button
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddFriendScreen(),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'เพื่อนทั้งหมด'),
            Tab(text: 'ออนไลน์'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          RefreshIndicator(onRefresh: _refresh, child: _AllFriendsTab()),
          RefreshIndicator(onRefresh: _refresh, child: _OnlineFriendsTab()),
        ],
      ),
    );
  }
}

class _AllFriendsTab extends StatelessWidget {
  const _AllFriendsTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: friendService,
      builder: (context, _) {
        if (friendService.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final friends = friendService.friends;

        if (friends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'ยังไม่มีเพื่อน',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'เริ่มต้นการค้นหาและเพิ่มเพื่อนกันเถอะ!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddFriendScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('เพิ่มเพื่อน'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: friends.length,
          itemBuilder: (context, index) {
            final friend = friends[index];
            return _FriendTile(friend: friend);
          },
        );
      },
    );
  }
}

class _OnlineFriendsTab extends StatelessWidget {
  const _OnlineFriendsTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: friendService,
      builder: (context, _) {
        final onlineFriends = friendService.onlineFriends;

        if (onlineFriends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'ไม่มีเพื่อนออนไลน์',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'เพื่อนของคุณจะปรากฏที่นี่เมื่อพวกเขาออนไลน์',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: onlineFriends.length,
          itemBuilder: (context, index) {
            final friend = onlineFriends[index];
            return _FriendTile(friend: friend);
          },
        );
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final Friend friend;

  const _FriendTile({required this.friend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ตรวจสอบสถานะ SOS/Rescue (ใช้ friend.id เป็น peer ID)
    // 🔧 ใช้ friend.name แทน friend.id เพื่อรองรับ mesh (ที่มีหลาย ID แต่ name เดียว)
    final isSOSActive = appState.isSOSPeer(friend.name);
    final isRescueActive = appState.isRescuePeer(friend.name);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: GestureDetector(
          // กดที่รูปโปรไฟล์ → ไปหน้าโปรไฟล์เพื่อน (แยกจากกดที่เหลือของ tile ที่เปิดแชท)
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FriendProfileScreen(friend: friend),
              ),
            );
          },
          child: Stack(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: isSOSActive
                    ? Colors.red.withValues(alpha: 0.2)
                    : isRescueActive
                    ? Colors.blue.withValues(alpha: 0.2)
                    : cs.primaryContainer,
                backgroundImage: friend.avatar != null
                    ? NetworkImage(friend.avatar!)
                    : null,
                child: friend.avatar == null
                    ? Text(
                        friend.name.isNotEmpty
                            ? friend.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isSOSActive
                              ? Colors.red
                              : isRescueActive
                              ? Colors.blue
                              : cs.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
              // SOS Badge (สีแดง - มีความสำคัญสูงสุด)
              if (isSOSActive)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Center(
                      child: Text(
                        '!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )
              // Rescue Badge (สีน้ำเงิน)
              else if (isRescueActive)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 21, 39, 54),
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.local_hospital,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
                )
              // Online status indicator (แสดงเฉพาะเมื่อไม่มี SOS/Rescue)
              else if (friend.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      friend.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  // แสดง emoji indicator
                  if (isSOSActive)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('🚨', style: TextStyle(fontSize: 14)),
                    ),
                  if (isRescueActive && !isSOSActive)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('🚑', style: TextStyle(fontSize: 14)),
                    ),
                ],
              ),
            ),
            if (friend.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${friend.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ลบบรรทัดแสดง ID ออก
            if (friend.lastMessage != null) ...[
              Text(
                friend.lastMessage!,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (friend.lastMessageTime != null)
                Text(
                  _formatTime(friend.lastMessageTime!),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
            ] else ...[
              // ถ้าไม่มีข้อความ แสดงสถานะออนไลน์แทน
              Text(
                friend.isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                style: TextStyle(
                  fontSize: 12,
                  color: friend.isOnline
                      ? Colors.green
                      : cs.onSurface.withValues(alpha: 0.5),
                  fontWeight: friend.isOnline
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FriendChatScreen(friend: friend),
            ),
          );
        },
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'remove':
                _showRemoveFriendDialog(context, friend);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.person_remove, color: Colors.red),
                  SizedBox(width: 8),
                  Text('ลบเพื่อน', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'เพิ่งกี้';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} นาทีที่แล้ว';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} ชั่วโมงที่แล้ว';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} วันที่แล้ว';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  void _showRemoveFriendDialog(BuildContext context, Friend friend) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบเพื่อน'),
        content: Text(
          'คุณต้องการลบ ${friend.name} ออกจากรายชื่อเพื่อนหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await friendService.removeFriend(friend);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'ลบเพื่อนเรียบร้อยแล้ว'
                          : 'เกิดข้อผิดพลาดในการลบเพื่อน',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
