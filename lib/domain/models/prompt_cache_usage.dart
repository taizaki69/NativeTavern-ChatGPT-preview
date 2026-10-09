/// Only numeric cache counters are retained. No raw response or prompt data.
class PromptCacheUsage {
  const PromptCacheUsage({this.cachedTokens, this.cacheWriteTokens});

  final int? cachedTokens;
  final int? cacheWriteTokens;

  static PromptCacheUsage? fromOpenRouter(Object? usage) {
    if (usage is! Map) return null;
    final details = usage['prompt_tokens_details'];
    return fromJson(details);
  }

  static PromptCacheUsage? fromJson(Object? json) {
    if (json is! Map) return null;
    final read = _counter(json['cached_tokens']);
    final write = _counter(json['cache_write_tokens']);
    if (read == null && write == null) return null;
    return PromptCacheUsage(cachedTokens: read, cacheWriteTokens: write);
  }

  static int? _counter(Object? value) =>
      value is num && value.isFinite && value >= 0 && value == value.floor()
          ? value.toInt()
          : null;

  static PromptCacheUsage? combine(
      PromptCacheUsage? left, PromptCacheUsage? right) {
    if (left == null) return right;
    if (right == null) return left;
    int? sum(int? a, int? b) =>
        a == null && b == null ? null : (a ?? 0) + (b ?? 0);
    return PromptCacheUsage(
      cachedTokens: sum(left.cachedTokens, right.cachedTokens),
      cacheWriteTokens: sum(left.cacheWriteTokens, right.cacheWriteTokens),
    );
  }

  Map<String, dynamic> toJson() => {
        if (cachedTokens != null) 'cached_tokens': cachedTokens,
        if (cacheWriteTokens != null) 'cache_write_tokens': cacheWriteTokens,
      };

  static const metadataKey = 'openRouterCacheUsageBySwipe';

  static Map<String, dynamic> forMessage(
    Map<String, dynamic>? metadata,
    PromptCacheUsage? usage,
    int swipeIndex,
  ) {
    final result = <String, dynamic>{...?metadata};
    final bySwipe = <String, dynamic>{};
    final old = metadata?[metadataKey];
    if (old is Map) {
      for (final entry in old.entries) {
        final safe = fromJson(entry.value);
        if (entry.key is String && safe != null) {
          bySwipe[entry.key as String] = safe.toJson();
        }
      }
    }
    if (usage == null) {
      bySwipe.remove(swipeIndex.toString());
    } else {
      bySwipe[swipeIndex.toString()] = usage.toJson();
    }
    if (bySwipe.isEmpty) {
      result.remove(metadataKey);
    } else {
      result[metadataKey] = bySwipe;
    }
    return result;
  }

  static Map<String, dynamic> removeSwipe(
      Map<String, dynamic> metadata, int deletedIndex) {
    final result = <String, dynamic>{...metadata};
    final previous = metadata[metadataKey];
    if (previous is! Map) return result;
    final shifted = <String, dynamic>{};
    for (final entry in previous.entries) {
      final index = int.tryParse(entry.key.toString());
      final safe = fromJson(entry.value);
      if (index == null || index < 0 || index == deletedIndex || safe == null) {
        continue;
      }
      shifted[(index > deletedIndex ? index - 1 : index).toString()] =
          safe.toJson();
    }
    if (shifted.isEmpty) {
      result.remove(metadataKey);
    } else {
      result[metadataKey] = shifted;
    }
    return result;
  }

  static PromptCacheUsage? forSwipe(
          Map<String, dynamic>? metadata, int swipeIndex) =>
      fromJson((metadata?[metadataKey] is Map)
          ? (metadata![metadataKey] as Map)[swipeIndex.toString()]
          : null);
}
