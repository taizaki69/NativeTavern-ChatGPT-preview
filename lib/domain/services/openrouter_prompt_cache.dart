export '../models/prompt_cache_usage.dart';

/// Explicit five-minute Claude caching for the OpenRouter Chat Completions API.
/// This edits only request copies, never persisted prompts or message history.
class OpenRouterPromptCache {
  static bool supportsModel(String model) => RegExp(
        r'^anthropic/claude-(sonnet|opus|haiku)-[45](?:[.-][0-9]+)*(?::[a-z0-9_-]+)*$',
      ).hasMatch(model.trim().toLowerCase());

  static List<Map<String, dynamic>> apply(
    List<Map<String, dynamic>> messages,
  ) {
    final existing = _breakpointCount(messages);
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
            'cache_control': {'type': 'ephemeral'},
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
            (content[target] as Map).containsKey('cache_control')) {
          continue;
        }
        (content[target] as Map)['cache_control'] = {'type': 'ephemeral'};
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

  static int _breakpointCount(Object? value) {
    if (value is List) {
      return value.fold(0, (total, item) => total + _breakpointCount(item));
    }
    if (value is Map) {
      return (value.containsKey('cache_control') ? 1 : 0) +
          value.values
              .fold<int>(0, (total, item) => total + _breakpointCount(item));
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
