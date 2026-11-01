import 'package:flutter/material.dart';
import 'package:native_tavern/presentation/theme/app_theme.dart';

/// A titled group of settings rendered as one rounded card, used by the
/// Settings and AI Configuration screens.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: context.tavern.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme.merge(
              shape: const RoundedRectangleBorder(),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
