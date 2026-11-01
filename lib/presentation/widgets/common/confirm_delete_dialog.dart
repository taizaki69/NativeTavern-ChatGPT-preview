import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';

/// Ask the user to confirm deleting chats or messages.
///
/// Returns `true` when the deletion should proceed. When the user turned off
/// "Confirm before deleting" in Settings the dialog is skipped entirely.
Future<bool> confirmDeletion(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  String? confirmLabel,
}) async {
  if (!ref.read(appSettingsProvider).confirmBeforeDelete) return true;

  final l10n = AppLocalizations.of(context);
  final colorScheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.delete_outline, color: colorScheme.error),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel ?? l10n.delete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
