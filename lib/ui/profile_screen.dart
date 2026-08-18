// lib/ui/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/friend_service.dart';
import '../cloud/firebase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isLoading = false;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _loadUserProfile() {
    final user = friendService.currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _bioController.text = user.bio ?? '';
    }
  }

  Future<void> _updateProfile() async {
    final currentUser = friendService.currentUser;
    if (currentUser == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาใส่ชื่อ')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedProfile = currentUser.copyWith(
        name: name,
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        lastActiveAt: DateTime.now(),
      );

      await friendService.updateUserProfile(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตโปรไฟล์เรียบร้อยแล้ว')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// เปิดเมนูเลือกถ่ายรูป/เลือกจากคลัง แล้วอัปโหลดขึ้น Firebase Storage เป็นรูปโปรไฟล์
  Future<void> _pickAndUploadAvatar() async {
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ต้องออนไลน์และเข้าสู่ระบบก่อนถึงจะเปลี่ยนรูปโปรไฟล์ได้',
          ),
        ),
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลัง'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final currentUser = friendService.currentUser;
    if (currentUser == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final ext = picked.path.split('.').last;
      final storagePath = 'avatars/${currentUser.id}.$ext';
      final url = await firebaseService.uploadFile(picked.path, storagePath);
      if (url == null) throw Exception('อัปโหลดรูปไม่สำเร็จ');

      final updatedProfile = currentUser.copyWith(
        avatar: url,
        lastActiveAt: DateTime.now(),
      );
      await friendService.updateUserProfile(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('อัปเดตรูปโปรไฟล์แล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('โปรไฟล์'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(onPressed: _updateProfile, child: const Text('บันทึก')),
        ],
      ),
      body: AnimatedBuilder(
        animation: friendService,
        builder: (context, _) {
          final currentUser = friendService.currentUser;
          if (currentUser == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Cloud Sync Banner
                AnimatedBuilder(
                  animation: firebaseService,
                  builder: (context, _) {
                    final isSignedIn = firebaseService.isSignedIn;
                    final isOnline = firebaseService.isOnline;
                    final email = firebaseService.currentUser?.email;

                    if (isSignedIn) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B3A2A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2E7D4F),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isOnline ? Icons.cloud_done : Icons.cloud_off,
                              color: isOnline
                                  ? const Color(0xFF43A047)
                                  : const Color(0xFF8A9BC2),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isOnline
                                        ? 'เชื่อมต่อ Cloud แล้ว'
                                        : 'login อยู่ (ออฟไลน์)',
                                    style: const TextStyle(
                                      color: Color(0xFF43A047),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (email != null)
                                    Text(
                                      email,
                                      style: const TextStyle(
                                        color: Color(0xFF8A9BC2),
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // ยังไม่ได้ login → แสดง soft prompt
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2A40),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF2E3D5A),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_off,
                            color: Color(0xFF6A7A9A),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'เข้าสู่ระบบเพื่อ sync กับเพื่อนและสำรองข้อมูลบน Cloud\nใช้งานออฟไลน์ได้โดยไม่ต้อง login',
                              style: TextStyle(
                                color: Color(0xFF8A9BC2),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              // กลับไปที่หน้าหลักแล้วให้ user ไปที่ Settings tab ด้วยตัวเอง
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'ไปที่แท็บ "การตั้งค่า" เพื่อเข้าสู่ระบบ',
                                  ),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF1A90FF),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                            child: const Text(
                              'Login',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Profile Picture Section
                const SizedBox(height: 16),
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: cs.primaryContainer,
                        backgroundImage: currentUser.avatar != null
                            ? NetworkImage(currentUser.avatar!)
                            : null,
                        child: currentUser.avatar == null
                            ? Text(
                                currentUser.name.isNotEmpty
                                    ? currentUser.name[0].toUpperCase()
                                    : '?',
                                style: theme.textTheme.displayMedium?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                          child: _isUploadingAvatar
                              ? Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onPrimary,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    Icons.camera_alt,
                                    color: cs.onPrimary,
                                    size: 20,
                                  ),
                                  onPressed: _pickAndUploadAvatar,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // User ID Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ID ของคุณ',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  currentUser.id,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: currentUser.id),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('คัดลอก ID แล้ว'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'แชร์ ID นี้กับเพื่อนเพื่อให้พวกเขาสามารถเพิ่มคุณเป็นเพื่อนได้',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Name Field
                _buildTextField(
                  controller: _nameController,
                  label: 'ชื่อ',
                  icon: Icons.person,
                  required: true,
                ),

                const SizedBox(height: 16),

                // Bio Field
                _buildTextField(
                  controller: _bioController,
                  label: 'คำอธิบาย (ไม่จำเป็น)',
                  icon: Icons.info_outline,
                  maxLines: 3,
                  maxLength: 200,
                ),

                const SizedBox(height: 32),

                // Stats Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('สถิติ', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatItem(
                                context,
                                'เพื่อน',
                                '${friendService.friends.length}',
                                Icons.people,
                                cs.tertiary,
                              ),
                            ),
                            Expanded(
                              child: _buildStatItem(
                                context,
                                'ออนไลน์',
                                '${friendService.onlineFriends.length}',
                                Icons.circle,
                                const Color(0xFF43A047),
                              ),
                            ),
                            Expanded(
                              child: _buildStatItem(
                                context,
                                'ข้อความ',
                                '${friendService.totalUnreadCount}',
                                Icons.message,
                                cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Account Info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ข้อมูลบัญชี', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          context,
                          'สร้างเมื่อ',
                          _formatDate(currentUser.createdAt),
                        ),
                        _buildInfoRow(
                          context,
                          'เข้าใช้ล่าสุด',
                          _formatDate(currentUser.lastActiveAt),
                        ),
                        if (currentUser.email != null)
                          _buildInfoRow(context, 'อีเมล', currentUser.email!),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        counterText: maxLength != null ? null : '',
      ),
      maxLines: maxLines,
      maxLength: maxLength,
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
