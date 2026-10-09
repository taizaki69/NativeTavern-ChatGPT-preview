import 'package:flutter/material.dart';
import 'package:native_tavern/data/models/chat.dart';
import 'package:native_tavern/domain/services/openrouter_prompt_cache.dart';

/// Provider-reported counters for the selected reply; no savings estimates.
class PromptCacheUsagePreview extends StatelessWidget {
  const PromptCacheUsagePreview({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final usage =
        PromptCacheUsage.forSwipe(message.metadata, message.currentSwipeIndex);
    if (usage == null) return const SizedBox.shrink();
    final labels = [
      if (usage.cachedTokens != null)
        'Cache read: ${usage.cachedTokens} tokens',
      if (usage.cacheWriteTokens != null)
        'Cache write: ${usage.cacheWriteTokens} tokens',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Tooltip(
        message: 'Cache usage reported for this reply’s generation requests. '
            'Zero reads means no reported cache hit.',
        child: Text(
          labels.join(' · '),
          key: ValueKey('prompt-cache-usage-${message.id}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
