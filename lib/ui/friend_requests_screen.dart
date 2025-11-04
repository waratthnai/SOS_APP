// lib/ui/friend_requests_screen.dart
import 'package:flutter/material.dart';
import '../core/friend_service.dart';
import '../core/friend_models.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // 🔥 Sync ทันทีเมื่อเข้าหน้านี้
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
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
      backgroundColor: cs.background,
      appBar: AppBar(
        title: const Text('คำขอเป็นเพื่อน', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.surface,
        actions: [
          // ปุ่ม Refresh
          IconButton(
            icon: _isRefreshing 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refresh,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: friendService,
        builder: (context, _) {
          if (friendService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = friendService.friendRequests;
          
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: cs.onBackground.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ไม่มีคำขอเป็นเพื่อน',
                    style: TextStyle(
                      fontSize: 18,
                      color: cs.onBackground.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'คำขอเป็นเพื่อนที่ได้รับจะปรากฏที่นี่',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onBackground.withOpacity(0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _FriendRequestTile(request: request);
            },
          );
        },
      ),
    );
  }
}

class _FriendRequestTile extends StatefulWidget {
  final FriendRequest request;

  const _FriendRequestTile({required this.request});

  @override
  State<_FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends State<_FriendRequestTile> {
  bool _isLoading = false;

  Future<void> _acceptRequest() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await friendService.acceptFriendRequest(widget.request);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? 'ยอมรับคำขอจาก ${widget.request.fromUserName} แล้ว' 
              : 'เกิดข้อผิดพลาดในการยอมรับคำขอ'
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rejectRequest() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await friendService.rejectFriendRequest(widget.request);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? 'ปฏิเสธคำขอจาก ${widget.request.fromUserName} แล้ว' 
              : 'เกิดข้อผิดพลาดในการปฏิเสธคำขอ'
            ),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with user info
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: widget.request.fromUserAvatar != null 
                    ? NetworkImage(widget.request.fromUserAvatar!) 
                    : null,
                  child: widget.request.fromUserAvatar == null 
                    ? Text(
                        widget.request.fromUserName.isNotEmpty 
                          ? widget.request.fromUserName[0].toUpperCase() 
                          : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer,
                        ),
                      )
                    : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.fromUserName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ID: ${widget.request.fromUserId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        _formatTime(widget.request.sentAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Message (if any)
            if (widget.request.message != null && widget.request.message!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ข้อความ:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.request.message!,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Action buttons
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectDialog(),
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text(
                        'ปฏิเสธ',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showAcceptDialog(),
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text(
                        'ยอมรับ',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
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

  void _showAcceptDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยอมรับคำขอ'),
        content: Text(
          'คุณต้องการยอมรับคำขอเป็นเพื่อนจาก ${widget.request.fromUserName} หรือไม่?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _acceptRequest();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('ยอมรับ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ปฏิเสธคำขอ'),
        content: Text(
          'คุณต้องการปฏิเสธคำขอเป็นเพื่อนจาก ${widget.request.fromUserName} หรือไม่?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectRequest();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}