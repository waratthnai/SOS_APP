// lib/ui/add_friend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // เพิ่ม import สำหรับ Clipboard
import 'package:flutter/foundation.dart'; // เพิ่ม import สำหรับ debugPrint
import '../core/friend_service.dart';
import '../core/friend_models.dart';
import 'package:offgrid_sos/core/logger.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _searchController = TextEditingController();
  final _messageController = TextEditingController();
  List<UserProfile> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await friendService.searchUsers(query);
      setState(() {
        _searchResults = results;
        _isLoading = false;
        if (results.isEmpty) {
          _errorMessage = 'ไม่พบผู้ใช้ที่ค้นหา';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'เกิดข้อผิดพลาดในการค้นหา: $e';
      });
    }
  }

  Future<void> _sendFriendRequest(UserProfile user) async {
    final message = _messageController.text.trim();
    
    setState(() => _isLoading = true);

    try {
      Log.d('[AddFriendScreen] 📤 กำลังส่งคำขอไปหา: ${user.name} (${user.id})');
      
      final success = await friendService.sendFriendRequest(
        user, 
        message: message.isNotEmpty ? message : null
      );
      
      setState(() => _isLoading = false);

      if (success) {
        Log.d('[AddFriendScreen] ✅ ส่งคำขอสำเร็จ');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ส่งคำขอเป็นเพื่อนให้ ${user.name} แล้ว\n💡 คำขอจะปรากฏที่ ${user.name} ภายใน 10 วินาที'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        Log.d('[AddFriendScreen] ❌ ส่งคำขอไม่สำเร็จ');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ เกิดข้อผิดพลาดในการส่งคำขอ\nกรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      Log.d('[AddFriendScreen] ❌ Error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: const Text('เพิ่มเพื่อน', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.surface,
      ),
      body: Column(
        children: [
          // Search Section
          Container(
            padding: const EdgeInsets.all(16),
            color: cs.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ค้นหาเพื่อนด้วยชื่อ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'พิมพ์ชื่อหรือ User ID ที่ต้องการค้นหา...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _searchUsers();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cs.background,
                  ),
                  onChanged: (value) {
                    setState(() {}); // อัปเดตปุ่มล้าง
                  },
                  onSubmitted: (value) => _searchUsers(),
                ),
                const SizedBox(height: 8),
                Text(
                  'คุณสามารถค้นหาด้วยชื่อหรือ User ID (เช่น A7X2M9, K4P3R8)',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _searchUsers,
                    icon: _isLoading 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isLoading ? 'กำลังค้นหา...' : 'ค้นหา'),
                  ),
                ),
              ],
            ),
          ),
          
          // Current User Info
          Container(
            padding: const EdgeInsets.all(16),
            child: AnimatedBuilder(
              animation: friendService,
              builder: (context, _) {
                final currentUser = friendService.currentUser;
                if (currentUser == null) return const SizedBox.shrink();
                
                return Card(
                  color: cs.primaryContainer.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: cs.primary,
                          child: Text(
                            currentUser.name.isNotEmpty ? currentUser.name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'โปรไฟล์ของคุณ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.6),
                                ),
                              ),
                              Text(
                                currentUser.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'ID: ${currentUser.id}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withOpacity(0.6),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(Icons.copy, size: 16, color: cs.primary),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: currentUser.id));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('คัดลอก User ID แล้ว! ส่งให้เพื่อนเพื่อเพิ่มคุณ'),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    tooltip: 'คัดลอก User ID',
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

          // Results Section
          Expanded(
            child: _buildResultsSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _searchUsers,
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'ค้นหาเพื่อนด้วยชื่อ',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'พิมพ์ชื่อในช่องค้นหาด้านบนเพื่อเริ่มต้น',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _UserTile(
          user: user,
          onAddFriend: () => _showAddFriendDialog(user),
        );
      },
    );
  }

  void _showAddFriendDialog(UserProfile user) {
    _messageController.clear();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('เพิ่ม ${user.name} เป็นเพื่อน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ข้อความแนะนำตัว (ไม่จำเป็น)',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'สวัสดี! ฉันอยากเป็นเพื่อนกับคุณ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendFriendRequest(user);
            },
            child: const Text('ส่งคำขอ'),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserProfile user;
  final VoidCallback onAddFriend;

  const _UserTile({
    required this.user,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: cs.primaryContainer,
          backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
          child: user.avatar == null 
            ? Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              )
            : null,
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${user.id}',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                user.bio!,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.8),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            Row(
              children: [
                Icon(
                  user.isOnline ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: user.isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  user.isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                  style: TextStyle(
                    fontSize: 12,
                    color: user.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton.icon(
          onPressed: onAddFriend,
          icon: const Icon(Icons.person_add, size: 16),
          label: const Text('เพิ่ม'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(60, 32),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}