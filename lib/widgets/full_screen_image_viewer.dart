import 'dart:io';
import 'package:flutter/material.dart';

/// เปิดรูปแบบเต็มจอ (ใช้ในหน้าแชท) — รองรับทั้งไฟล์ในเครื่อง (`filePath`) และ URL (`url`)
void openFullScreenImage(
  BuildContext ctx, {
  required String heroTag,
  String? filePath,
  String? url,
}) {
  Navigator.of(ctx).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => FullScreenImageViewer(
        heroTag: heroTag,
        filePath: filePath,
        url: url,
      ),
    ),
  );
}

class FullScreenImageViewer extends StatelessWidget {
  final String heroTag;
  final String? filePath;
  final String? url;

  const FullScreenImageViewer({
    super.key,
    required this.heroTag,
    this.filePath,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidget = filePath != null
        ? Image.file(File(filePath!), fit: BoxFit.contain)
        : Image.network(url!, fit: BoxFit.contain);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: SizedBox.expand(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Hero(tag: heroTag, child: imageWidget),
            ),
          ),
        ),
      ),
    );
  }
}
