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
import '../cloud/firebase_service.dart';
import '../widgets/message_status_icon.dart';
import 'package:offgrid_sos/core/logger.dart';

void _openFriendFullScreenImage(BuildContext ctx, {required String heroTag, String? filePath, String? url}) {
  Navigator.of(ctx).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => _FullScreenImageViewer(heroTag: heroTag, filePath: filePath, url: url),
  ));
}

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
  int _messageCount = 0; // ⚡ ติดตามจำนวนข้อความเพื่อ rebuild
  bool _listenerStarted = false; // ป้องกัน start listener ซ้ำ

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markMessagesAsRead();

    // ⚡ ฟังการเปลี่ยนแปลงของ friendChats เพื่อ rebuild
    appState.addListener(_onMessagesChanged);

    // แจ้ง AppState ว่าผู้ใช้เปิดห้องแชทนี้อยู่ → suppress notification ซ้ำซ้อน
    appState.setActiveFriendChat(widget.friend.userId);

    // เริ่ม real-time Firestore listener (เมื่อ online) แทน polling
    // ถ้าออฟไลน์ fallback ไป auto-refresh ทุก 30 วินาทีแทน
    _startRealTimeOrFallback();

    // ฟัง connectivity เพื่อ upgrade fallback timer → real-time listener เมื่อเน็ตกลับมา
    firebaseService.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    appState.setActiveFriendChat(null);
    appState.stopFriendChatListener(widget.friend.userId);
    appState.removeListener(_onMessagesChanged);
    firebaseService.removeListener(_onConnectivityChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChanged() {
    // upgrade: offline timer → real-time listener เมื่อเน็ตกลับมา
    if (firebaseService.isOnline && firebaseService.isSignedIn && _autoRefreshTimer != null) {
      _autoRefreshTimer!.cancel();
      _autoRefreshTimer = null;
      appState.startFriendChatListener(widget.friend.userId);
    }
  }

  // ⚡ Callback เมื่อมีข้อความใหม่
  void _onMessagesChanged() {
    final messages = appState.friendChats[widget.friend.userId] ?? [];
    final newCount = messages.length;
    if (newCount != _messageCount) {
      setState(() {
        _messageCount = newCount;
      });
      _scrollToBottom();
    }
  }

  // widget.friend คือ snapshot ตอนเปิดหน้านี้ ไม่อัปเดตเองเมื่อ friendService
  // ได้รับสถานะออนไลน์ใหม่ ต้อง lookup จาก live list ทุกครั้งที่จะแสดงสถานะ
  Friend get _liveFriend => friendService.friends.firstWhere(
        (f) => f.userId == widget.friend.userId,
        orElse: () => widget.friend,
      );

  Timer? _autoRefreshTimer;

  void _startRealTimeOrFallback() {
    if (_listenerStarted) return;
    _listenerStarted = true;

    // ถ้าออนไลน์ → ใช้ Firestore real-time listener (รับข้อความทันที ไม่ poll)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      appState.startFriendChatListener(widget.friend.userId);
    } else {
      // ออฟไลน์ → fallback polling ทุก 30 วินาที (ลดจาก 5 เพื่อประหยัดแบต)
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) _refresh(silent: true);
      });
    }
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
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.animateTo(
          0,
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
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_camera, color: cs.primary),
                title: const Text('ถ่ายรูป'),
                onTap: () { Navigator.pop(ctx); _takePhoto(); },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: cs.primary),
                title: const Text('รูปจากคลัง'),
                onTap: () { Navigator.pop(ctx); _pickImage(); },
              ),
              ListTile(
                leading: Icon(Icons.video_library, color: cs.primary),
                title: const Text('วิดีโอจากคลัง'),
                onTap: () { Navigator.pop(ctx); _pickVideo(); },
              ),
              ListTile(
                leading: Icon(Icons.location_on, color: cs.primary),
                title: const Text('แชร์ตำแหน่ง'),
                onTap: () { Navigator.pop(ctx); _pickLocation(); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 📸 ถ่ายรูปจากกล้อง
  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) await _sendImage(File(image.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ไม่สามารถถ่ายรูปได้: $e')),
        );
      }
    }
  }

  // 📷 เลือกรูปภาพจาก Gallery
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

      await appState.sendFriendImageMessage(
        widget.friend.userId,
        imageFile.path,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งรูปภาพสำเร็จ')),
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

      await appState.sendFriendVideoMessage(
        widget.friend.userId,
        videoFile.path,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งวิดีโอสำเร็จ')),
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
      backgroundColor: cs.surface,
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
                  AnimatedBuilder(
                    animation: friendService,
                    builder: (context, _) {
                      final isOnline = _liveFriend.isOnline;
                      return Row(
                        children: [
                          Icon(
                            isOnline ? Icons.circle : Icons.circle_outlined,
                            size: 8,
                            color: isOnline ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'ออนไลน์' : 'ออฟไลน์',
                            style: TextStyle(
                              fontSize: 12,
                              color: isOnline ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      );
                    },
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
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'เริ่มต้นการสนทนา',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ส่งข้อความให้ ${widget.friend.name} เพื่อเริ่มแชท',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'ไม่พบข้อความที่ค้นหา',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ลองค้นหาด้วยคำอื่น',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          key: ValueKey('messages_${_messageCount}_${messages.length}'),
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];
            final isFromMe = message.fromUserId == friendService.currentUser?.id;

            return _MessageBubble(
              message: message,
              isFromMe: isFromMe,
              isPending: isFromMe && appState.pendingFriendSyncIds.contains(message.id),
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
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'ค้นหาข้อความ...',
          hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
          prefixIcon: Icon(Icons.search, color: cs.onSurface.withValues(alpha: 0.5)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: cs.onSurface.withValues(alpha: 0.5)),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: cs.surface,
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
          top: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
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
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
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
        content: Text(
          'คุณต้องการล้างประวัติแชทกับ ${widget.friend.name} ทั้งหมดหรือไม่?\n\nการกระทำนี้ไม่สามารถย้อนกลับได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await appState.clearFriendChat(widget.friend.userId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ ล้างประวัติแชทเรียบร้อย')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('❌ ล้างแชทไม่สำเร็จ: $e')),
                  );
                }
              }
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
            Text('สถานะ: ${_liveFriend.isOnline ? "ออนไลน์" : "ออฟไลน์"}'),
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
  final bool isPending;
  final String friendName;
  final Function(String)? onOpenUrl;

  const _MessageBubble({
    required this.message,
    required this.isFromMe,
    required this.isPending,
    required this.friendName,
    this.onOpenUrl,
  });

  Widget _buildImageWidget(FriendChatMessage message) {
    final heroTag = 'friend_img_${message.id}';
    Widget imageChild;

    // URL จาก Firebase Storage — ใช้ก่อนเสมอ
    if (message.fileUrl != null) {
      imageChild = Image.network(
        message.fileUrl!,
        width: 200,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: 200,
            height: 150,
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, error, stackTrace) => _imageErrorWidget(),
      );
    } else if (message.filePath != null) {
      imageChild = Image.file(
        File(message.filePath!),
        width: 200,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imageErrorWidget(),
      );
    } else {
      return _imageErrorWidget();
    }

    return Builder(
      builder: (ctx) => GestureDetector(
        onTap: () => _openFriendFullScreenImage(ctx, heroTag: heroTag, filePath: message.filePath, url: message.fileUrl),
        child: Hero(tag: heroTag, child: imageChild),
      ),
    );
  }

  Widget _imageErrorWidget() {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      color: Colors.red.withValues(alpha: 0.1),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(height: 8),
          Text('ไม่สามารถโหลดรูปภาพได้', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

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
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFromMe 
              ? cs.onPrimaryContainer.withValues(alpha: 0.3)
              : cs.onSurfaceVariant.withValues(alpha: 0.3),
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
                  : cs.surfaceContainerHighest,
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
                  if (message.hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildImageWidget(message),
                    ),
                    if (message.text != null && message.text!.isNotEmpty)
                      const SizedBox(height: 8),
                  ],
                  // 🎥 แสดงวิดีโอ (ถ้ามี)
                  if (message.hasVideo) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _VideoPlayerWidget(
                        videoPath: message.filePath,
                        videoUrl: message.fileUrl,
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
                            ? cs.onPrimary.withValues(alpha: 0.7)
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      if (isFromMe) ...[
                        const SizedBox(width: 4),
                        MessageStatusIcon(
                          status: isPending
                              ? MessageStatus.pending
                              : message.isRead
                                  ? MessageStatus.synced
                                  : message.isDelivered
                                      ? MessageStatus.delivered
                                      : MessageStatus.sent,
                          size: 12,
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

class _VideoPlayerWidget extends StatefulWidget {
  final String? videoPath;
  final String? videoUrl;

  const _VideoPlayerWidget({this.videoPath, this.videoUrl});

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
      // ใช้ Network URL ถ้ามี ไม่งั้น fallback ไป local file
      if (widget.videoUrl != null) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!));
      } else if (widget.videoPath != null) {
        _controller = VideoPlayerController.file(File(widget.videoPath!));
      } else {
        setState(() => _hasError = true);
        return;
      }
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      Log.d(' Error initializing video: $e');
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
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            SizedBox(height: 8),
            Text('ไม่สามารถโหลดวิดีโอได้', style: TextStyle(fontSize: 12)),
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
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  size: 48,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final String heroTag;
  final String? filePath;
  final String? url;

  const _FullScreenImageViewer({required this.heroTag, this.filePath, this.url});

  @override
  Widget build(BuildContext context) {
    final imageWidget = url != null
        ? Image.network(url!, fit: BoxFit.contain)
        : Image.file(File(filePath!), fit: BoxFit.contain);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: SizedBox.expand(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(child: Hero(tag: heroTag, child: imageWidget)),
          ),
        ),
      ),
    );
  }
}
