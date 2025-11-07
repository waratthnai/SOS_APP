// lib/ui/emergency_chat_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart'; // สำหรับคำนวณระยะทาง
import '../core/transport.dart';
import '../core/chat_models.dart';
import '../core/chat_db.dart'; // สำหรับบันทึกชื่อ peer
import '../core/app_state.dart';
import '../core/device_id_manager.dart'; // สำหรับ Device ID
import '../core/friend_service.dart'; // สำหรับ friendService
import '../widgets/message_status_icon.dart';

/// หน้าแชทฉุกเฉินสำหรับอุปกรณ์ที่สแกนเจอ
/// ใช้ Nearby Connections แทน Firebase
class EmergencyChatScreen extends StatefulWidget {
  final Peer peer;

  const EmergencyChatScreen({super.key, required this.peer});

  @override
  State<EmergencyChatScreen> createState() => _EmergencyChatScreenState();
}

class _EmergencyChatScreenState extends State<EmergencyChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearchBar = false; // 🔍 สถานะแสดง/ซ่อนแถบค้นหา
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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

    // ตรวจสอบว่าเชื่อมต่อกับ peer หรือไม่
    final isConnected = appState.peers.any((p) => p.id == widget.peer.id);
    
    if (!isConnected) {
      // ถ้าไม่ได้เชื่อมต่อ แสดงข้อความแจ้งเตือน
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ไม่สามารถส่งข้อความได้ เนื่องจากไม่ได้เชื่อมต่อกับ ${widget.peer.name}\n'
                    'ข้อความจะถูกบันทึกและส่งเมื่อเชื่อมต่อใหม่',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    _messageController.clear();
    
    // ส่งข้อความผ่าน sendChatText แทนที่จะใช้ send โดยตรง
    // เพื่อให้การเพิ่มข้อความและ notification ทำงานถูกต้อง
    // ข้อความจะถูกบันทึกเป็น 'pending' ถ้าไม่ได้เชื่อมต่อ
    appState.sendChatText(text, receiverId: widget.peer.id);
    
    _scrollToBottom();
  }

  // 📷 เลือกรูปภาพจาก Gallery
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,  // ลดความกว้างสูงสุด (เดิม 1920)
        maxHeight: 800, // ลดความสูงสูงสุด (เดิม 1080)
        imageQuality: 60, // ลดคุณภาพเพื่อลดขนาดไฟล์ (เดิม 85)
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
      final ImagePicker picker = ImagePicker();
      final XFile? videoFile = await picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (videoFile == null) return;

      // ส่งวิดีโอ
      await _sendVideo(File(videoFile.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ไม่สามารถเลือกวิดีโอได้: $e')),
        );
      }
    }
  }

  // 📤 ส่งวิดีโอผ่าน Nearby Connections
  Future<void> _sendVideo(File videoFile) async {
    // ตรวจสอบการเชื่อมต่อ
    final isConnected = appState.peers.any((p) => p.id == widget.peer.id);
    
    if (!isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถส่งวิดีโอได้ เนื่องจากไม่ได้เชื่อมต่อกับ ${widget.peer.name}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    try {
      // แสดง loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📤 กำลังส่งวิดีโอ...')),
        );
      }

      // 💾 บันทึกชื่อ peer ก่อนส่ง
      ChatDB.savePeerName(widget.peer.id, widget.peer.name);

      // 🆕 เพิ่มวิดีโอในแชทของตัวเองทันที (เพื่อให้เห็นว่าส่งไปแล้ว)
      appState.addChatVideo(videoFile.path, receiverId: widget.peer.id);

      // ส่งไฟล์ผ่าน transport layer
      await appState.transport.sendFile(
        videoFile.path,
        to: widget.peer,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งวิดีโอสำเร็จ')),
        );
      }

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ส่งวิดีโอไม่สำเร็จ: $e')),
        );
      }
    }
  }

  // 📤 ส่งรูปภาพผ่าน Nearby Connections
  Future<void> _sendImage(File imageFile) async {
    // ตรวจสอบการเชื่อมต่อ
    final isConnected = appState.peers.any((p) => p.id == widget.peer.id);
    
    if (!isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถส่งรูปภาพได้ เนื่องจากไม่ได้เชื่อมต่อกับ ${widget.peer.name}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    try {
      // ตรวจสอบขนาดไฟล์ก่อนส่ง
      final fileSize = await imageFile.length();
      print('📊 ขนาดไฟล์รูปภาพ: ${(fileSize / 1024).toStringAsFixed(2)} KB');
      
      // ถ้าไฟล์ใหญ่เกิน 5MB แสดง warning
      if (fileSize > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ รูปภาพมีขนาดใหญ่ อาจใช้เวลาในการส่งนาน'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      
      // แสดง loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📤 กำลังส่งรูปภาพ...')),
        );
      }

      // 💾 บันทึกชื่อ peer ก่อนส่ง
      ChatDB.savePeerName(widget.peer.id, widget.peer.name);

      // 🆕 เพิ่มรูปภาพในแชทของตัวเองทันที (เพื่อให้เห็นว่าส่งไปแล้ว)
      appState.addChatImage(imageFile.path, receiverId: widget.peer.id);

      // ส่งไฟล์ผ่าน transport layer
      await appState.transport.sendFile(
        imageFile.path,
        to: widget.peer,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ ส่งรูปภาพสำเร็จ')),
        );
      }

      _scrollToBottom();
    } catch (e) {
      print('❌ ส่งรูปภาพล้มเหลว: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ส่งรูปภาพไม่สำเร็จ: $e')),
        );
      }
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    // ตรวจสอบสถานะ SOS และ Rescue Mode ของ peer นี้
    final isSOSActive = appState.isSOSPeer(widget.peer.id);
    final isRescueActive = appState.isRescuePeer(widget.peer.id);
    
    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        backgroundColor: cs.surface,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isSOSActive 
                      ? Colors.red.withOpacity(0.2)
                      : isRescueActive
                          ? Colors.blue.withOpacity(0.2)
                          : cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.phone_android,
                    size: 16,
                    color: isSOSActive 
                        ? Colors.red
                        : isRescueActive
                            ? Colors.blue
                            : cs.onSurfaceVariant,
                  ),
                ),
                // Badge สำหรับ SOS (สีแดง)
                if (isSOSActive)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.5),
                      ),
                    ),
                  ),
                // Badge สำหรับ Rescue (สีน้ำเงิน)
                if (isRescueActive && !isSOSActive)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.peer.name.isNotEmpty ? widget.peer.name : 'อุปกรณ์ฉุกเฉิน',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // แสดง emoji badge
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
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: appState.peers.any((p) => p.id == widget.peer.id) 
                            ? Colors.green 
                            : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        appState.peers.any((p) => p.id == widget.peer.id)
                            ? (isSOSActive 
                                ? 'ขอความช่วยเหลือ!'
                                : isRescueActive
                                    ? 'หน่วยกู้ภัย'
                                    : 'เชื่อมต่อแล้ว')
                            : 'ไม่ได้เชื่อมต่อ',
                        style: TextStyle(
                          fontSize: 12,
                          color: appState.peers.any((p) => p.id == widget.peer.id)
                              ? (isSOSActive 
                                  ? Colors.red
                                  : isRescueActive
                                      ? Colors.blue
                                      : Colors.green)
                              : Colors.grey,
                          fontWeight: isSOSActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      // 📍 แสดงระยะห่าง
                      StreamBuilder<Position>(
                        stream: Geolocator.getPositionStream(
                          locationSettings: const LocationSettings(
                            accuracy: LocationAccuracy.high,
                            distanceFilter: 1,
                          ),
                        ),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          
                          final distance = appState.getDistanceToPeerSync(
                            widget.peer.id, 
                            snapshot.data,
                          );
                          
                          if (distance == null) return const SizedBox.shrink();
                          
                          String distanceText;
                          Color distanceColor;
                          
                          if (distance < 1000) {
                            distanceText = '${distance.toStringAsFixed(0)} m';
                            distanceColor = distance < 10 
                                ? Colors.green 
                                : distance < 50 
                                    ? Colors.orange 
                                    : Colors.grey;
                          } else {
                            distanceText = '${(distance / 1000).toStringAsFixed(2)} km';
                            distanceColor = Colors.grey;
                          }
                          
                          return Row(
                            children: [
                              const SizedBox(width: 8),
                              Icon(
                                Icons.my_location,
                                size: 12,
                                color: distanceColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                distanceText,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: distanceColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
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
          // แสดง badge ฉุกเฉินเฉพาะเมื่อ SOS active
          if (isSOSActive)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else if (isRescueActive)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_hospital, color: Colors.blue, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'หน่วยกู้ภัย',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),
          
          // Messages area
          Expanded(
            child: _buildMessagesList(),
          ),
          
          // Input area
          _buildInputArea(),
        ],
      ),
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

  Widget _buildMessagesList() {
    return FutureBuilder<String>(
      future: DeviceIdManager.getCurrentId(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final myDeviceId = snapshot.data!;
        final userId = friendService.currentUser?.id ?? 'anonymous';
        
        return AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            // ดึงข้อความจาก appState.chatMessages และกรองเฉพาะของ peer นี้
            final allMessages = appState.chatMessages.where((msg) {
              // แสดงข้อความที่:
              // 1. เราส่งถึง peer นี้ (from = myDeviceId/userId/'me' AND receiver = widget.peer.id)
              // 2. peer นี้ส่งมาหาเรา (from = widget.peer.id AND receiver = myDeviceId/userId/'me')
              final isFromMe = msg.from == myDeviceId || 
                               msg.from == userId || 
                               msg.from == 'me';
              final isFromPeer = msg.from == widget.peer.id;
              final isToPeer = msg.receiver == widget.peer.id;
              final isToMe = msg.receiver == myDeviceId || 
                            msg.receiver == userId || 
                            msg.receiver == 'me';
              
              // ข้อความต้องเป็น 1 ใน 2 กรณี:
              // - เราส่งถึง peer นี้
              // - peer นี้ส่งมาหาเรา
              return (isFromMe && isToPeer) || (isFromPeer && isToMe);
            }).toList();
            
            // Filter messages based on search query
            final messages = _searchQuery.isEmpty
                ? allMessages
                : allMessages.where((msg) {
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
                      'เริ่มต้นการสนทนาฉุกเฉิน',
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ส่งข้อความฉุกเฉินให้ ${widget.peer.name.isNotEmpty ? widget.peer.name : "อุปกรณ์นี้"}',
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
                // เช็คว่าข้อความนี้เป็นของเราหรือไม่
                final isFromMe = message.from == myDeviceId || 
                                 message.from == userId || 
                                 message.from == 'me';
                
                return _MessageBubble(
                  message: message,
                  isFromMe: isFromMe,
                  peerName: widget.peer.name,
                );
              },
            );
          },
        );
      },
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
            // 📷 ปุ่มเลือกรูปภาพ
            Container(
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                onPressed: _pickImage,
                icon: Icon(
                  Icons.image,
                  color: cs.onPrimaryContainer,
                ),
                tooltip: 'แนบรูปภาพ',
              ),
            ),
            const SizedBox(width: 8),
            // 🎥 ปุ่มแนบวิดีโอ
            Container(
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                onPressed: _pickVideo,
                icon: Icon(
                  Icons.video_library,
                  color: cs.onSecondaryContainer,
                ),
                tooltip: 'แนบวิดีโอ',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'พิมพ์ข้อความฉุกเฉิน...',
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
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                onPressed: _sendMessage,
                icon: const Icon(
                  Icons.send,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isFromMe;
  final String peerName;

  const _MessageBubble({
    required this.message,
    required this.isFromMe,
    required this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isFromMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.red.withOpacity(0.2),
              child: Icon(
                Icons.phone_android,
                size: 14,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              // 🗑️ กดค้างเพื่อลบข้อความ
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('ลบข้อความ'),
                    content: const Text('คุณต้องการลบข้อความนี้หรือไม่?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          // ลบข้อความ
                          await appState.deleteMessage(message.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ ลบข้อความแล้ว'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        child: const Text('ลบ', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isFromMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        peerName.isNotEmpty ? peerName : 'อุปกรณ์ฉุกเฉิน',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isFromMe 
                          ? Colors.red 
                          : cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomRight: isFromMe ? const Radius.circular(4) : null,
                        bottomLeft: !isFromMe ? const Radius.circular(4) : null,
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
                      if (message.text != null && message.text!.isNotEmpty)
                        Text(
                          message.text!,
                          style: TextStyle(
                            color: isFromMe ? Colors.white : cs.onSurface,
                            fontSize: 15,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isFromMe 
                                  ? Colors.white.withOpacity(0.8) 
                                  : cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                          // 📊 แสดงสถานะข้อความ (สำหรับข้อความที่เราส่ง)
                          if (isFromMe) ...[
                            const SizedBox(width: 4),
                            MessageStatusIcon(status: message.status, size: 12),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          if (isFromMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 📊 Widget แสดงสถานะข้อความ (checkmarks)
// 🎬 Video Player Widget - แสดงวิดีโอในแชท
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
      print('❌ Error initializing video: $e');
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
