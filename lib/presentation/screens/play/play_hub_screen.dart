import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/router/app_router.dart';
import 'package:native_tavern/presentation/theme/app_theme.dart';
import 'package:native_tavern/presentation/widgets/play/ai_play_feature_gate.dart';

/// Play tab hub: four names only. No timeline, switches, or status.
class PlayHubScreen extends ConsumerWidget {
  const PlayHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tavern;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.playHub)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _PlayHubRow(
            key: const Key('play-hub-moments'),
            tint: scheme.primary,
            icon: Icons.dynamic_feed_outlined,
            title: l10n.moments,
            onTap: () async {
              final enabled = await ensureAiPlayFeatureEnabled(
                context,
                ref,
                AiPlayFeature.moments,
              );
              if (enabled && context.mounted) {
                context.push(AppRoutes.playMoments);
              }
            },
          ),
          _PlayHubRow(
            key: const Key('play-hub-story'),
            tint: colors.accent,
            icon: Icons.menu_book_outlined,
            title: l10n.story,
            onTap: () async {
              final enabled = await ensureAiPlayFeatureEnabled(
                context,
                ref,
                AiPlayFeature.story,
              );
              if (enabled && context.mounted) {
                context.push(AppRoutes.playStory);
              }
            },
          ),
          _PlayHubRow(
            key: const Key('play-hub-world-info'),
            tint: scheme.tertiary,
            icon: Icons.public_outlined,
            title: l10n.worldInfo,
            onTap: () => context.push(AppRoutes.worldInfo),
          ),
          _PlayHubRow(
            key: const Key('play-hub-data-bank'),
            tint: colors.success,
            icon: Icons.library_books_outlined,
            title: l10n.dataBank,
            onTap: () => context.push(AppRoutes.dataBank),
          ),
        ],
      ),
    );
  }
}

class _PlayHubRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color tint;
  final VoidCallback onTap;

  const _PlayHubRow({
    super.key,
    required this.icon,
    required this.title,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minTileHeight: 80,
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: 28, color: tint),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: context.tavern.textMuted),
        onTap: onTap,
      ),
    );
  }
}
