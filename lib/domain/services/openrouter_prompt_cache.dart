export '../models/prompt_cache_usage.dart';

import 'prompt_cache_policy.dart';

/// Stable prefix breakpoints for audited content-block protocols.
/// The legacy class name is retained for build-45 source compatibility.
/// This edits only request copies, never persisted prompts or message history.
class OpenRouterPromptCache {
  static bool supportsModel(String model) => PromptCachePolicy.forConnection(
          'openRouter', model, 'https://openrouter.ai/api/v1')
      .appControlled;

  static List<Map<String, dynamic>> apply(
    List<Map<String, dynamic>> messages, {
    String markerField = 'cache_control',
    Map<String, String> marker = const {'type': 'ephemeral'},
    int reservedBreakpoints = 0,
  }) {
    final existing = countBreakpoints(messages) + reservedBreakpoints;
    if (existing >= 4) return messages;

    // Leading instruction sections provide independent fallbacks when later
    // lore/RAG/macros change. The provider hashes exact content: edits cannot
    // accidentally reuse stale text. Do not reorder or rewrite prompt text.
    final leading = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (!const {'system', 'developer'}.contains(messages[i]['role'])) break;
      if (_canMark(messages[i])) leading.add(i);
    }
    final latestUser =
        messages.lastIndexWhere((message) => message['role'] == 'user');
    int? history;
    for (var i = latestUser - 1; i >= 0; i--) {
      if (const {'user', 'assistant'}.contains(messages[i]['role']) &&
          _canMark(messages[i])) {
        history = i;
        break;
      }
    }

    // Reserve a growing-history boundary; newest input and assistant prefill
    // remain outside that boundary. Never add more than four breakpoints.
    final candidates = <int>[
      if (leading.isNotEmpty) leading.last,
      if (history != null) history,
      if (leading.isNotEmpty) leading.first,
      if (leading.length > 2) leading[1],
    ].toSet();
    final result = messages
        .map((message) => _copy(message) as Map<String, dynamic>)
        .toList();
    var remaining = 4 - existing;
    // A manual one-hour marker must precede every new five-minute marker.
    // Skip its entire message conservatively rather than rewriting that marker.
    final lastLongRetention = messages
        .lastIndexWhere((message) => _hasLongRetention(message['content']));
    for (final i in candidates) {
      if (remaining == 0) break;
      if (i <= lastLongRetention) continue;
      final content = result[i]['content'];
      if (content is String) {
        if (content.isEmpty) continue;
        result[i]['content'] = [
          {
            'type': 'text',
            'text': content,
            markerField: Map<String, String>.from(marker),
          },
        ];
        remaining--;
      } else if (content is List) {
        final target = content.lastIndexWhere((part) =>
            part is Map &&
            part['type'] == 'text' &&
            part['text'] is String &&
            (part['text'] as String).isNotEmpty);
        if (target < 0 ||
            ((content[target] as Map).containsKey('cache_control') ||
                (content[target] as Map)
                    .containsKey('prompt_cache_breakpoint'))) {
          continue;
        }
        (content[target] as Map)[markerField] =
            Map<String, String>.from(marker);
        remaining--;
      }
    }
    return result;
  }

  static bool _canMark(Map<String, dynamic> message) {
    final content = message['content'];
    return content is String
        ? content.isNotEmpty
        : content is List &&
            content.any((part) =>
                part is Map &&
                part['type'] == 'text' &&
                part['text'] is String &&
                (part['text'] as String).isNotEmpty);
  }

  static int countBreakpoints(Object? value) {
    if (value is List) {
      return value.fold(0, (total, item) => total + countBreakpoints(item));
    }
    if (value is Map) {
      return (value.containsKey('cache_control') ? 1 : 0) +
          (value.containsKey('prompt_cache_breakpoint') ? 1 : 0) +
          value.values
              .fold<int>(0, (total, item) => total + countBreakpoints(item));
    }
    return 0;
  }

  static bool _hasLongRetention(Object? value) {
    if (value is List) return value.any(_hasLongRetention);
    if (value is Map) {
      final control = value['cache_control'];
      return (control is Map && control['ttl'] == '1h') ||
          value.values.any(_hasLongRetention);
    }
    return false;
  }

  static Object? _copy(Object? value) {
    if (value is List) return value.map(_copy).toList();
    if (value is Map) {
      return value.map<String, dynamic>(
          (key, item) => MapEntry(key as String, _copy(item)));
    }
    return value;
  }
}
