import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';

/// Kinds of tactile feedback used across the app.
enum TavernHaptic {
  /// Sending a message, confirming an action.
  light,

  /// Moving between discrete choices, such as swipes.
  selection,

  /// Opening a context menu or a destructive gesture.
  medium,
}

/// Play [kind] unless the user turned haptic feedback off in Settings.
///
/// Works from any widget below the app's [ProviderScope].
void playHaptic(BuildContext context,
    [TavernHaptic kind = TavernHaptic.light]) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(appSettingsProvider).enableHaptics) return;
  switch (kind) {
    case TavernHaptic.light:
      HapticFeedback.lightImpact();
    case TavernHaptic.selection:
      HapticFeedback.selectionClick();
    case TavernHaptic.medium:
      HapticFeedback.mediumImpact();
  }
}
