// lib/widgets/message_status_icon.dart
import 'package:flutter/material.dart';
import '../core/chat_models.dart';

/// Widget แสดงไอคอนสถานะข้อความ
class MessageStatusIcon extends StatelessWidget {
  final MessageStatus status;
  final double size;
  
  const MessageStatusIcon({
    super.key,
    required this.status,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.pending:
        // ⏳ รอส่ง (สีเทา + หมุน)
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.grey.shade400,
            ),
          ),
        );
        
      case MessageStatus.sent:
        // ✓ ส่งแล้ว (เครื่องหมายถูกเดี่ยว)
        return Icon(
          Icons.check,
          size: size,
          color: Colors.grey.shade600,
        );
        
      case MessageStatus.delivered:
        // ✓✓ ส่งถึงผู้รับแล้ว (เครื่องหมายถูกคู่)
        return Icon(
          Icons.done_all,
          size: size,
          color: Colors.grey.shade600,
        );
        
      case MessageStatus.synced:
        // ☁️✓ ซิงก์ขึ้น Cloud แล้ว (เครื่องหมายถูก + เมฆ)
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.cloud_done,
              size: size,
              color: Colors.blue.shade600,
            ),
          ],
        );
    }
  }
}

/// Widget แสดงข้อความสถานะแบบเต็ม (ใช้ใน debug หรือ tooltip)
class MessageStatusText extends StatelessWidget {
  final MessageStatus status;
  
  const MessageStatusText({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    
    switch (status) {
      case MessageStatus.pending:
        text = 'กำลังส่ง...';
        color = Colors.orange;
        break;
      case MessageStatus.sent:
        text = 'ส่งแล้ว';
        color = Colors.grey.shade600;
        break;
      case MessageStatus.delivered:
        text = 'ส่งถึงแล้ว';
        color = Colors.blue;
        break;
      case MessageStatus.synced:
        text = 'ซิงก์แล้ว';
        color = Colors.green;
        break;
    }
    
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: color,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
