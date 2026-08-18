// lib/ui/friend_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/friend_models.dart';
import '../cloud/firebase_service.dart';

/// แสดงโปรไฟล์ของเพื่อน (ชื่อ, ID, คำอธิบาย, รูป) — เปิดจากการกดรูปโปรไฟล์ในหน้าเพื่อน
class FriendProfileScreen extends StatefulWidget {
  final Friend friend;

  const FriendProfileScreen({super.key, required this.friend});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await firebaseService.findPublicProfileByUserId(
      widget.friend.userId,
    );
    if (mounted) {
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final friend = widget.friend;

    // ใช้ข้อมูลจาก public profile ถ้าโหลดสำเร็จ ไม่งั้น fallback เป็นข้อมูลที่มีอยู่แล้วใน Friend
    final name = _profile?.name ?? friend.name;
    final avatar = _profile?.avatar ?? friend.avatar;
    final bio = _profile?.bio;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('โปรไฟล์'), backgroundColor: cs.surface),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 60,
              backgroundColor: cs.primaryContainer,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (friend.isOnline) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ข้อมูล', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    context,
                    label: 'ID',
                    value: friend.userId,
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'คัดลอก ID',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: friend.userId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('คัดลอก ID แล้ว')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'คำอธิบาย',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isLoading)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      (bio != null && bio.isNotEmpty)
                          ? bio
                          : 'ยังไม่ได้ตั้งคำอธิบาย',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontStyle: (bio == null || bio.isEmpty)
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: (bio == null || bio.isEmpty)
                            ? cs.onSurfaceVariant
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}
