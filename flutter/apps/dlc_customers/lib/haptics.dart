import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tactile feedback for key customer actions.
///
/// Only mobile platforms that support haptics produce feedback; everywhere
/// else (desktop, web, tests) every call is a silent no-op.
abstract final class Haptics {
  /// Light impact for a completed action (login, sign-up, payment confirmed).
  static void success() => _perform(HapticFeedback.lightImpact);

  /// Light impact for a selection or a neutral decision (logout, decline).
  static void selection() => _perform(HapticFeedback.lightImpact);

  /// Medium impact for a failed action or invalid input.
  static void error() => _perform(HapticFeedback.mediumImpact);

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void _perform(Future<void> Function() feedback) {
    if (!_supported) return;
    // Haptics are best-effort: a missing platform implementation must never
    // break the flow that triggered them.
    feedback().catchError((Object _) {});
  }
}
