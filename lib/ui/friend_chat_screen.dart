// lib/ui/friend_chat_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../core/friend_models.dart';
import '../core/chat_models.dart';
import '../core/app_state.dart';
import '../core/friend_service.dart';

class FriendChatScreen extends StatefulWidget {
  final Friend friend;

  const FriendChatScreen({super.key, required this.friend});

  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _picker = ImagePicker();
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _searchQuery = '';
  bool _showSearchBar = false; // 🔍 สถานะแสดง/ซ่อนแถบค้นหา

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markMessagesAsRead();
    
    // 🔥 Auto refresh ทุก 5 วินาที เพื่อดึงข้อความใหม่
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Timer? _autoRefreshTimer;

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _refresh(silent: true); // silent = ไม่แสดง loading indicator
      }
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_isRefreshing) return;
    
    if (!silent) {
      setState(() => _isRefreshing = true);
    }
    
    try {
      // 🔥 ใช้ forceRefresh: true เพื่อบังคับดึงข้อความใหม่
      await appState.loadFriendChatMessages(widget.friend.userId, forceRefresh: true);
      if (mounted && !silent) {
        _scrollToBottom();
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _loadMessages() async {
    await appState.loadFriendChatMessages(widget.friend.userId);
    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _markMessagesAsRead() async {
    await appState.markFriendMessagesAsRead(widget.friend.userId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    
    await appState.sendFriendChatMessage(widget.friend.userId, text);
    
    // 🔥 Refresh ทันทีหลังส่งข้อความเพื่อดูว่าส่งสำเร็จ
    await _refresh(silent: true);
    _scrollToBottom();
  }

  // 🌐 เปิด URL
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ไม่สามารถเปิดลิงก์ได้: $url')),
        );
      }
    }
  }

  // 📎 แสดงเมนูแนบไฟล์
  void _showAttachmentMenu() {
    final cs = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.image, color: cs.primary),
                title: const Text('ส่งรูปภาพ'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.video_library, color: cs.primary),
                title: const Text('ส่งวิดีโอ'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              ListTile(
                leading: Icon(Icons.location_on, color: cs.primary),
                title: const Text('แชร์ตำแหน่ง'),
                onTap: () {
                  Navigator.pop(context);
                  _pickLocation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // �📷 เลือกรูปภาพจาก Gallery
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        await _sendImage(File(image.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ไม่สามารถเลือกรูปภาพได้: $e')),
        );
      }
    }
  }

  // 🎥 เลือกวิดีโอจาก Gallery
  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
      );
      
      if (video != null) {
        await _sendVideo(File(video.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ไม่สามารถเลือกวิดีโอได้: $e')),
        );
      }
    }
  }

  // 📍 ดึงตำแหน่งปัจจุบันและส่งให้เพื่อน
  Future<void> _pickLocation() async {
    try {
      // แสดง loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📍 กำลังรับตำแหน่ง...')),
        );
      }

      // ส่งตำแหน่งผ่าน AppState (จะ request permission อัตโนมัติ)
      await appState.sendFriendLocationMessage(widget.friend.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งตำแหน่งสำเร็จ')),
        );
      }

      await _refresh(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ไม่สามารถรับตำแหน่งได้: $e')),
        );
      }
    }
  }

  // 📤 ส่งรูปภาพ (P2P ถ้าอยู่ใกล้ หรือเก็บ metadata อย่างเดียว)
  Future<void> _sendImage(File imageFile) async {
    try {
      // แสดง loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📤 กำลังส่งรูปภาพ...')),
        );
      }

      // ส่งรูปผ่าน P2P (ถ้าอยู่ใกล้กัน)
      // TODO: ตรวจสอบว่า friend อยู่ใน nearby peers หรือไม่
      // ถ้าอยู่ → ส่งผ่าน transport.sendFile()
      // ถ้าไม่อยู่ → บันทึก metadata อย่างเดียว (ไม่อัพโหลด Firebase Storage)
      
      // ตอนนี้: บันทึก local อย่างเดียว + แสดง metadata
      await appState.sendFriendImageMessage(
        widget.friend.userId, 
        imageFile.path,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งรูปภาพสำเร็จ (P2P/Local)')),
        );
      }

      await _refresh(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ส่งรูปภาพไม่สำเร็จ: $e')),
        );
      }
    }
  }

  // 🎥 ส่งวิดีโอ (P2P ถ้าอยู่ใกล้ หรือเก็บ metadata อย่างเดียว)
  Future<void> _sendVideo(File videoFile) async {
    try {
      // แสดง loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📤 กำลังส่งวิดีโอ...')),
        );
      }

      // ส่งวิดีโอผ่าน P2P (ถ้าอยู่ใกล้กัน)
      // TODO: ตรวจสอบว่า friend อยู่ใน nearby peers หรือไม่
      // ถ้าอยู่ → ส่งผ่าน transport.sendFile()
      // ถ้าไม่อยู่ → บันทึก metadata อย่างเดียว (ไม่อัพโหลด Firebase Storage)
      
      // ตอนนี้: บันทึก local อย่างเดียว + แสดง metadata
      await appState.sendFriendVideoMessage(
        widget.friend.userId, 
        videoFile.path,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งวิดีโอสำเร็จ (P2P/Local)')),
        );
      }

      await _refresh(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ส่งวิดีโอไม่สำเร็จ: $e')),
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
        backgroundColor: cs.surface,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              backgroundImage: widget.friend.avatar != null 
                ? NetworkImage(widget.friend.avatar!) 
                : null,
              child: widget.friend.avatar == null 
                ? Text(
                    widget.friend.name.isNotEmpty ? widget.friend.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  )
                : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.friend.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        widget.friend.isOnline ? Icons.circle : Icons.circle_outlined,
                        size: 8,
                        color: widget.friend.isOnline ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.friend.isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.friend.isOnline ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 🔍 ปุ่มเปิด/ปิดแถบค้นหา
          IconButton(
            icon: Icon(_showSearchBar ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  // ล้างการค้นหาเมื่อปิด
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
            tooltip: _showSearchBar ? 'ปิดการค้นหา' : 'ค้นหาข้อความ',
          ),
          // ปุ่ม Refresh
          IconButton(
            icon: _isRefreshing 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : () => _refresh(),
            tooltip: 'รีเฟรชข้อความ',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'clear':
                  _showClearChatDialog();
                  break;
                case 'info':
                  _showFriendInfo();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Text('ข้อมูลเพื่อน'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, color: Colors.red),
                    SizedBox(width: 8),
                    Text('ล้างแชท', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar for filtering messages
          _buildSearchBar(),
          
          // Messages area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      await _refresh();
                    },
                    child: _buildMessagesList(),
                  ),
          ),
          
          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final allMessages = appState.friendChats[widget.friend.userId] ?? [];
        
        // Filter messages based on search query
        final messages = _searchQuery.isEmpty
            ? allMessages
            : allMessages.where((msg) {
                // Search in text messages only
                if (msg.text != null) {
                  return msg.text!.toLowerCase().contains(_searchQuery);
                }
                return false;
              }).toList();
        
        if (allMessages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'เริ่มต้นการสนทนา',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ส่งข้อความให้ ${widget.friend.name} เพื่อเริ่มแชท',
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
        
        if (messages.isEmpty && _searchQuery.isNotEmpty) {
          // No results found for search
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'ไม่พบข้อความที่ค้นหา',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ลองค้นหาด้วยคำอื่น',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isFromMe = message.fromUserId == friendService.currentUser?.id;
            
            return _MessageBubble(
              message: message,
              isFromMe: isFromMe,
              friendName: widget.friend.name,
              onOpenUrl: _openUrl,
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    
    // ซ่อนแถบค้นหาถ้า _showSearchBar เป็น false
    if (!_showSearchBar) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outline.withOpacity(0.2)),
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'ค้นหาข้อความ...',
          hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.5)),
          prefixIcon: Icon(Icons.search, color: cs.onSurface.withOpacity(0.5)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: cs.onSurface.withOpacity(0.5)),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: cs.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildInputArea() {
    final cs = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outline.withOpacity(0.2)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // � ปุ่มเมนูแนบไฟล์
            Container(
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                onPressed: _showAttachmentMenu,
                icon: Icon(
                  Icons.menu,
                  color: cs.onPrimaryContainer,
                ),
                tooltip: 'แนบไฟล์',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: true, // เพิ่ม enabled
                autofocus: false, // ไม่ต้อง autofocus
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: 'พิมพ์ข้อความ...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onTap: () {
                  // Debug: แสดงว่า TextField ถูกแตะ
                  print('📝 TextField tapped!');
                },
                onChanged: (text) {
                  // Debug: แสดงว่า text กำลังเปลี่ยน
                  print('✍️ Text changed: $text');
                },
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                onPressed: _sendMessage,
                icon: Icon(
                  Icons.send,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ล้างแชท'),
        content: Text('คุณต้องการล้างประวัติแชทกับ ${widget.friend.name} หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement clear chat functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ฟีเจอร์นี้จะพัฒนาในเวอร์ชันต่อไป')),
              );
            },
            child: const Text('ล้าง', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showFriendInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ข้อมูล ${widget.friend.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ชื่อ: ${widget.friend.name}'),
            Text('User ID: ${widget.friend.userId}'),
            Text('สถานะ: ${widget.friend.isOnline ? "ออนไลน์" : "ออฟไลน์"}'),
            Text('เพิ่มเพื่อนเมื่อ: ${_formatDate(widget.friend.addedAt)}'),
            Text('เห็นครั้งล่าสุด: ${_formatDate(widget.friend.lastSeen)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _MessageBubble extends StatelessWidget {
  final FriendChatMessage message;
  final bool isFromMe;
  final String friendName;
  final Function(String)? onOpenUrl;

  const _MessageBubble({
    required this.message,
    required this.isFromMe,
    required this.friendName,
    this.onOpenUrl,
  });

  // สร้าง Widget สำหรับแสดงข้อความตำแหน่ง
  Widget _buildLocationMessage(String text, bool isFromMe, ColorScheme cs) {
    // แยกข้อความและ URL
    final lines = text.split('\n');
    String? locationUrl;
    String displayText = '📍 ดูตำแหน่งบน Google Maps';

    for (var line in lines) {
      if (line.contains('https://www.google.com/maps')) {
        locationUrl = line.trim();
      }
    }

    return InkWell(
      onTap: locationUrl != null ? () => onOpenUrl?.call(locationUrl!) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isFromMe 
            ? cs.primaryContainer.withOpacity(0.3)
            : cs.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFromMe 
              ? cs.onPrimaryContainer.withOpacity(0.3)
              : cs.onSurfaceVariant.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on,
              color: isFromMe ? cs.onPrimaryContainer : cs.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              displayText,
              style: TextStyle(
                color: isFromMe ? cs.onPrimaryContainer : cs.primary,
                fontSize: 16,
                decoration: TextDecoration.underline,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.open_in_new,
              color: isFromMe ? cs.onPrimaryContainer : cs.primary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isFromMe) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: cs.primaryContainer,
              child: Text(
                friendName.isNotEmpty ? friendName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isFromMe 
                  ? cs.primary 
                  : cs.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isFromMe ? 16 : 4),
                  bottomRight: Radius.circular(isFromMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 📷 แสดงรูปภาพ (ถ้ามี)
                  if (message.hasImage && message.filePath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(message.filePath!),
                        width: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            color: Colors.red.withOpacity(0.1),
                            child: Column(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red),
                                const SizedBox(height: 8),
                                const Text(
                                  'ไม่สามารถโหลดรูปภาพได้',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (message.text != null && message.text!.isNotEmpty)
                      const SizedBox(height: 8),
                  ],
                  // 🎥 แสดงวิดีโอ (ถ้ามี)
                  if (message.hasVideo && message.filePath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _VideoPlayerWidget(
                        videoPath: message.filePath!,
                      ),
                    ),
                    if (message.text != null && message.text!.isNotEmpty)
                      const SizedBox(height: 8),
                  ],
                  // ข้อความ (ถ้ามี)
                  if (message.hasText) ...[
                    // ตรวจสอบว่ามี Google Maps link หรือไม่
                    if (message.text!.contains('https://www.google.com/maps'))
                      _buildLocationMessage(message.text!, isFromMe, cs)
                    else
                      Text(
                        message.text!,
                        style: TextStyle(
                          color: isFromMe ? cs.onPrimary : cs.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.time),
                        style: TextStyle(
                          fontSize: 12,
                          color: isFromMe 
                            ? cs.onPrimary.withOpacity(0.7)
                            : cs.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                      if (isFromMe) ...[
                        const SizedBox(width: 4),
                        _MessageStatusIcon(
                          isDelivered: message.isDelivered,
                          isRead: message.isRead,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isFromMe) const SizedBox(width: 32),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    
    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// 📊 Widget แสดงสถานะข้อความสำหรับ Friend Chat
class _MessageStatusIcon extends StatelessWidget {
  final bool isDelivered;
  final bool isRead;
  
  const _MessageStatusIcon({
    required this.isDelivered,
    required this.isRead,
  });
  
  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;
    
    if (!isDelivered) {
      // ⏳ ค้างส่ง / กำลังส่ง
      icon = Icons.access_time;
      iconColor = Colors.grey;
    } else if (!isRead) {
      // ✓ ส่งแล้ว (ยังไม่อ่าน)
      icon = Icons.done;
      iconColor = Colors.grey;
    } else {
      // ✓✓ อ่านแล้ว
      icon = Icons.done_all;
      iconColor = Colors.blue;
    }
    
    return Icon(
      icon,
      size: 14,
      color: iconColor,
    );
  }
}
//  Video Player Widget - ???????????????
class _VideoPlayerWidget extends StatefulWidget {
  final String videoPath;

  const _VideoPlayerWidget({required this.videoPath});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.file(File(widget.videoPath));
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print(' Error initializing video: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            SizedBox(height: 8),
            Text('??????????????????????', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_controller.value.isPlaying) {
            _controller.pause();
          } else {
            _controller.play();
          }
        });
      },
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video display
            SizedBox(
              width: 200,
              height: 150,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
            // Play/Pause overlay
            if (!_controller.value.isPlaying)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  size: 48,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
