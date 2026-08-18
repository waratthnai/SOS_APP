// lib/ui/debug_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/friend_service.dart';
import '../cloud/firebase_service.dart';
import 'package:offgrid_sos/core/logger.dart';

class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Info'),
      ),
      body: AnimatedBuilder(
        animation: friendService,
        builder: (context, _) {
          final user = friendService.currentUser;
          final firebaseUser = firebaseService.currentUser;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Firebase Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow('Online', firebaseService.isOnline ? '✅ Yes' : '❌ No'),
                      _InfoRow('Signed In', firebaseService.isSignedIn ? '✅ Yes' : '❌ No'),
                      _InfoRow('Firebase UID', firebaseUser?.uid ?? '❌ No UID', copyable: true),
                      _InfoRow('Email', firebaseUser?.email ?? '❌ No email'),
                      _InfoRow('Display Name', firebaseUser?.displayName ?? '❌ No name'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'User Profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (user != null) ...[
                        _InfoRow('User ID', user.id, copyable: true),
                        _InfoRow('Name', user.name),
                        _InfoRow('Email', user.email ?? 'ไม่มี'),
                        _InfoRow('Created', user.createdAt.toString().substring(0, 16)),
                      ] else
                        const Text('❌ ไม่มีข้อมูลผู้ใช้'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Friends',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow('Total Friends', '${friendService.friends.length}'),
                      _InfoRow('Online Friends', '${friendService.onlineFriends.length}'),
                      _InfoRow('Friend Requests', '${friendService.friendRequests.length}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await friendService.syncWithFirebase();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sync แล้ว! ดู log ใน console')),
                  );
                },
                icon: const Icon(Icons.sync),
                label: const Text('Force Sync with Firebase'),
              ),
              const SizedBox(height: 8),
              if (user != null) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await firebaseService.saveFullUserProfile(user);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('บันทึกโปรไฟล์ขึ้น Firebase แล้ว!')),
                    );
                  },
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Upload Profile to Firebase'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    // ทดสอบค้นหา User ID ของตัวเอง
                    final result = await firebaseService.findUserByUserId(user.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result != null 
                          ? '✅ พบ User ID ใน Firebase: ${result.name}' 
                          : '❌ ไม่พบ User ID ใน Firebase'),
                        backgroundColor: result != null ? Colors.green : Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('ทดสอบค้นหา ID ตัวเอง'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    // ตรวจสอบข้อมูลเพื่อนจาก Firebase โดยตรง
                    Log.d('🔍 [Debug] กำลังตรวจสอบข้อมูลเพื่อนใน Firebase...');
                    final friends = await firebaseService.getUserFriends(user.id);
                    Log.d('📊 [Debug] ผลลัพธ์: พบ ${friends.length} เพื่อนใน Firebase');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('พบ ${friends.length} เพื่อนใน Firebase\nดู logs สำหรับรายละเอียด'),
                        backgroundColor: friends.isEmpty ? Colors.orange : Colors.green,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  },
                  icon: const Icon(Icons.people),
                  label: const Text('ตรวจสอบเพื่อนใน Firebase'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _InfoRow(this.label, this.value, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: copyable ? 'monospace' : null,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('คัดลอกแล้ว!'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
