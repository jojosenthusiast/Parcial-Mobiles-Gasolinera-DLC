import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One-line haptic feedback. Silent no-op on web and desktop, and never
/// throws if the platform channel is unavailable.
///
/// Swift mapping: selection/success -> UIImpactFeedbackGenerator(.light),
/// error -> UINotificationFeedbackGenerator(.error),
/// critical -> UINotificationFeedbackGenerator(.warning) or heavy impact.
abstract final class Haptics {
  /// Light tap for selections (filters, segmented controls, dropdowns).
  static Future<void> selection() => _fire('selection', HapticFeedback.lightImpact);

  /// Light tap when something was saved successfully.
  static Future<void> success() => _fire('success', HapticFeedback.lightImpact);

  /// Medium impact for validation or request errors.
  static Future<void> error() => _fire('error', HapticFeedback.mediumImpact);

  /// Strong vibration for critical alerts (for example critical tank levels).
  static Future<void> critical() => _fire('critical', HapticFeedback.vibrate);

  /// Whether this platform can produce haptics at all.
  static bool get supported =>
      debugSupportedOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  @visibleForTesting
  static bool? debugSupportedOverride;

  /// Test hook: receives the kind of every haptic that would fire.
  @visibleForTesting
  static void Function(String kind)? debugListener;

  static Future<void> _fire(String kind, Future<void> Function() action) async {
    if (!supported) return;
    debugListener?.call(kind);
    try {
      await action();
    } catch (_) {
      // Haptics are decoration; never surface failures.
    }
  }
}
