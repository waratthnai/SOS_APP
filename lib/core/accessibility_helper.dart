// lib/core/accessibility_helper.dart
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Helper class for accessibility features
class AccessibilityHelper {
  // Minimum touch target size (48x48 logical pixels)
  static const double minTouchTargetSize = 48.0;

  // Text scaling limits
  static const double minTextScale = 0.8;
  static const double maxTextScale = 3.0;

  /// Get accessible text scale factor
  static double getAccessibleTextScale(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final textScale = mediaQuery.textScaleFactor;
    
    // Clamp text scale factor
    return textScale.clamp(minTextScale, maxTextScale);
  }

  /// Announce message to screen readers
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  /// Check if high contrast is needed
  static bool isHighContrastNeeded(BuildContext context) {
    return MediaQuery.of(context).highContrast;
  }

  /// Check if screen reader is enabled
  static bool isScreenReaderEnabled(BuildContext context) {
    return MediaQuery.of(context).accessibleNavigation;
  }

  /// Get semantic label for emergency button
  static String getEmergencyButtonLabel(bool isActive) {
    return isActive 
        ? 'Emergency SOS activated. Double tap to deactivate.'
        : 'Emergency SOS button. Double tap to activate emergency mode.';
  }

  /// Get semantic label for notification count
  static String getNotificationCountLabel(int count) {
    if (count == 0) {
      return 'No notifications';
    } else if (count == 1) {
      return '1 unread notification';
    } else {
      return '$count unread notifications';
    }
  }

  /// Get semantic label for chat message
  static String getChatMessageLabel(String sender, String message, DateTime time, bool isEmergency) {
    final timeStr = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    final emergencyPrefix = isEmergency ? 'Emergency message. ' : '';
    return '${emergencyPrefix}Message from $sender at $timeStr. $message';
  }

  /// Create accessible button
  static Widget accessibleButton({
    required VoidCallback onPressed,
    required Widget child,
    String? semanticLabel,
    String? tooltip,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: true,
      child: Tooltip(
        message: tooltip ?? semanticLabel ?? '',
        child: InkWell(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: minTouchTargetSize,
              minHeight: minTouchTargetSize,
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Get contrast ratio between two colors
  static double getContrastRatio(Color color1, Color color2) {
    final luminance1 = color1.computeLuminance();
    final luminance2 = color2.computeLuminance();
    
    final lighter = luminance1 > luminance2 ? luminance1 : luminance2;
    final darker = luminance1 > luminance2 ? luminance2 : luminance1;
    
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Check if color combination meets WCAG AA standards (4.5:1 for normal text)
  static bool meetsWCAGAA(Color foreground, Color background) {
    return getContrastRatio(foreground, background) >= 4.5;
  }

  /// Check if color combination meets WCAG AAA standards (7:1 for normal text)
  static bool meetsWCAGAAA(Color foreground, Color background) {
    return getContrastRatio(foreground, background) >= 7.0;
  }
}
