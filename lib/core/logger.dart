import 'package:flutter/foundation.dart';

/// Debug-only logger. All calls are stripped out in release builds
/// so the hot paths (BLE/mesh payload handling, peer discovery, etc.)
/// don't pay for string interpolation or I/O in production.
class Log {
  static void d(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
