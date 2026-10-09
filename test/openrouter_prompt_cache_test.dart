import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/data/database/database.dart';
import 'package:native_tavern/data/models/chat.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/openrouter_prompt_cache.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/widgets/chat/prompt_cache_usage_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

const router = LLMConfig(
  provider: LLMProvider.openRouter,
  model: 'anthropic/claude-sonnet-5.5',
  apiKey: 'synthetic-key',
  apiUrl: 'https://openrouter.ai/api/v1',
  autoSummarizeEnabled: false,
);
const prompt = [
  {'role': 'system', 'content': 'Stable main instructions.'},
  {'role': 'system', 'content': 'Stable character description and scenario.'},
  {'role': 'user', 'content': 'First question'},
  {'role': 'assistant', 'content': 'First answer'},
  {'role': 'user', 'content': 'Newest question'},
];
const usage = {
  'prompt_tokens': 1200,
  'completion_tokens': 20,
  'prompt_tokens_details': {'cached_tokens': 1000, 'cache_write_tokens': 100},
  'private_provider_payload': 'must-not-persist',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'legacy OpenRouter settings enable caching without changing direct Claude',
      () {
    final legacy = router.toJson()..remove('openRouterPromptCacheEnabled');
    final restored = LLMConfig.fromJson(legacy);
    expect(restored.openRouterPromptCacheEnabled, isTrue);
    expect(restored.promptCacheEnabled, isFalse);
    final off = restored.copyWith(openRouterPromptCacheEnabled: false);
    expect(
        LLMConfig.fromJson(off.toJson()).openRouterPromptCacheEnabled, isFalse);
    expect(
        off.copyWith(temperature: 0.4).openRouterPromptCacheEnabled, isFalse);
  });

  test('supported Claude slugs are scoped to the actual provider', () {
    expect(router.supportsOpenRouterPromptCaching, isTrue);
    expect(
        router
            .copyWith(model: 'anthropic/claude-sonnet-5.5-20260928:beta')
            .supportsOpenRouterPromptCaching,
        isTrue);
    for (final model in [
      'openai/gpt-fixture',
      'google/gemini-fixture',
      'claude-sonnet-5.5',
      'anthropic/claude-unknown',
      'anthropic/claude-3-haiku'
    ]) {
      expect(router.copyWith(model: model).supportsOpenRouterPromptCaching,
          isFalse,
          reason: model);
    }
    for (final provider
        in LLMProvider.values.where((p) => p != LLMProvider.openRouter)) {
      expect(
          router.copyWith(provider: provider).supportsOpenRouterPromptCaching,
          isFalse,
          reason: provider.name);
    }
  });

  test(
      'markers cover instructions and history before newest input; no mutation',
      () {
    final original = jsonEncode(prompt);
    final cached = OpenRouterPromptCache.apply(prompt);
    expect(_count(cached), 3);
    expect(_marked(cached[0]), isTrue);
    expect(_marked(cached[1]), isTrue);
    expect(_marked(cached[3]), isTrue);
    expect(cached.last, prompt.last);
    expect(_plain(cached), prompt);
    expect(jsonEncode(prompt), original);
    expect(jsonEncode(cached), isNot(contains('"ttl"')));
  });

  test('appending turns retains identical previous content and cached prefixes',
      () {
    final first = OpenRouterPromptCache.apply(prompt);
    final next = OpenRouterPromptCache.apply([
      ...prompt,
      const {'role': 'assistant', 'content': 'Second answer'},
      const {'role': 'user', 'content': 'Third question'},
    ]);
    expect(_plain(next).take(4).toList(), _plain(first).take(4).toList());
    expect(_marked(next[5]), isTrue);
    expect(_marked(next.last), isFalse);
    expect(_plain(next)[4]['content'], 'Newest question');
  });

  test(
      'changing instructions sends new text; no local stale prompt cache exists',
      () {
    final changed = prompt.map((m) => Map<String, dynamic>.from(m)).toList();
    changed[1]['content'] = 'Edited character';
    final cached = OpenRouterPromptCache.apply(changed);
    expect(_plain(cached)[1]['content'], 'Edited character');
    expect(_plain(cached)[0], prompt[0]);
    expect(jsonEncode(cached), isNot(contains('Stable character description')));
  });

  test('changing dynamic tail preserves early explicit instruction boundary',
      () {
    final a = OpenRouterPromptCache.apply([
      prompt[0],
      prompt[1],
      const {'role': 'system', 'content': 'Timestamp: first'},
      prompt.last,
    ]);
    final b = OpenRouterPromptCache.apply([
      prompt[0],
      prompt[1],
      const {'role': 'system', 'content': 'Timestamp: second'},
      prompt.last,
    ]);
    expect(_marked(a[1]), isTrue);
    expect(a.take(2).toList(), b.take(2).toList());
    expect(_plain(b)[2]['content'], 'Timestamp: second');
  });

  test('first turn leaves the new question and assistant prefill uncached', () {
    final first = OpenRouterPromptCache.apply([
      prompt[0],
      prompt.last,
      const {'role': 'assistant', 'content': 'Prefill that may change'},
    ]);
    expect(_count(first), 1);
    expect(first[1], prompt.last);
    expect(first.last['content'], 'Prefill that may change');
  });

  test('many sections still have at most four breakpoints', () {
    final input = [
      for (var i = 0; i < 30; i++)
        {'role': 'system', 'content': 'Instruction section ${i + 1}'},
      ...prompt.skip(2),
    ];
    final result = OpenRouterPromptCache.apply(input);
    expect(_count(result), 4);
    expect(_plain(result), input);
    expect(_marked(result[29]), isTrue);
    expect(_marked(result[31]), isTrue);
  });

  test('existing manual breakpoints consume the four-breakpoint budget', () {
    final input = [
      for (var i = 0; i < 3; i++)
        {
          'role': 'system',
          'content': [
            {
              'type': 'text',
              'text': 'Manual ${i + 1}',
              'cache_control': {'type': 'ephemeral', 'ttl': '1h'}
            }
          ]
        },
      ...prompt,
    ];
    final encoded = jsonEncode(input);
    final result = OpenRouterPromptCache.apply(input);
    expect(_count(result), 4);
    expect(jsonEncode(input), encoded);
    expect(jsonEncode(result), contains('"ttl":"1h"'));
  });

  test('manual long retention precedes every app-added short marker', () {
    final input = [
      prompt[0],
      prompt[2],
      const {
        'role': 'assistant',
        'content': [
          {
            'type': 'text',
            'text': 'Manual reusable answer',
            'cache_control': {'type': 'ephemeral', 'ttl': '1h'}
          }
        ]
      },
      const {'role': 'user', 'content': 'Earlier question'},
      const {'role': 'assistant', 'content': 'Earlier answer'},
      prompt.last,
    ];
    final result = OpenRouterPromptCache.apply(input);
    expect(_count(result), 2);
    expect(_marked(result[0]), isFalse);
    expect(result[2], input[2]);
    expect(_marked(result[4]), isTrue);
    expect(result.last, prompt.last);
  });

  test('four existing markers are retained without an additional marker', () {
    final input = [
      for (var i = 0; i < 4; i++)
        {
          'role': 'system',
          'content': [
            {
              'type': 'text',
              'text': 'Manual ${i + 1}',
              'cache_control': {'type': 'ephemeral'}
            }
          ]
        },
      ...prompt,
    ];
    expect(OpenRouterPromptCache.apply(input), input);
    expect(_count(OpenRouterPromptCache.apply(input)), 4);
  });

  test('multimodal blocks are copied without altering images or thinking', () {
    final input = [
      {
        'role': 'system',
        'content': [
          {'type': 'text', 'text': 'Reusable material'},
          {
            'type': 'image_url',
            'image_url': {'url': 'https://example.invalid/image'}
          },
        ]
      },
      prompt.last,
    ];
    final before = jsonEncode(input);
    final result = OpenRouterPromptCache.apply(input);
    expect(_count(result), 1);
    expect((result[0]['content'] as List)[1], (input[0]['content'] as List)[1]);
    expect(jsonEncode(input), before);
    expect(
        _count(OpenRouterPromptCache.apply([
          const {
            'role': 'system',
            'content': [
              {'type': 'thinking', 'thinking': 'opaque', 'signature': 'opaque'}
            ]
          },
          prompt.last,
        ])),
        0);
  });

  test('empty and no reusable-prefix prompts do not gain meaningless markers',
      () {
    expect(OpenRouterPromptCache.apply([]), isEmpty);
    expect(_count(OpenRouterPromptCache.apply([prompt.last])), 0);
    expect(
        _count(OpenRouterPromptCache.apply([
          const {'role': 'system', 'content': ''},
          prompt.last,
        ])),
        0);
  });

  test('cache usage keeps only numeric counters, including reported zeros', () {
    final result = PromptCacheUsage.fromOpenRouter(usage)!;
    expect(result.toJson(), {'cached_tokens': 1000, 'cache_write_tokens': 100});
    expect(jsonEncode(result.toJson()), isNot(contains('must-not-persist')));
    expect(
        PromptCacheUsage.fromOpenRouter({
          'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0}
        })!
            .cachedTokens,
        0);
    expect(PromptCacheUsage.fromOpenRouter({'prompt_tokens': 100}), isNull);
    expect(
        PromptCacheUsage.fromJson(
            {'cached_tokens': '100', 'cache_write_tokens': -1}),
        isNull);
    expect(PromptCacheUsage.fromJson({'cached_tokens': double.nan}), isNull);
    expect(PromptCacheUsage.fromJson({'cached_tokens': 0.5}), isNull);
  });

  test(
      'usage stays with its swipe, survives JSON, and does not overwrite citations',
      () {
    final base = {'citations': 'preserved'};
    final metadata = PromptCacheUsage.forMessage(base,
        const PromptCacheUsage(cachedTokens: 500, cacheWriteTokens: 0), 0);
    final second = PromptCacheUsage.forMessage(
        metadata, const PromptCacheUsage(cachedTokens: 700), 1);
    final restored = jsonDecode(jsonEncode(second)) as Map<String, dynamic>;
    expect(restored['citations'], 'preserved');
    expect(PromptCacheUsage.forSwipe(restored, 0)!.cachedTokens, 500);
    expect(PromptCacheUsage.forSwipe(restored, 1)!.cachedTokens, 700);
    expect(PromptCacheUsage.forSwipe(restored, 2), isNull);
    final cleared = PromptCacheUsage.forMessage(restored, null, 1);
    expect(PromptCacheUsage.forSwipe(cleared, 1), isNull);
    expect(PromptCacheUsage.forSwipe(cleared, 0)!.cachedTokens, 500);
    expect(base, {'citations': 'preserved'});
  });

  test('actual non-stream request includes markers and preserves model/routing',
      () async {
    final h = _Transport();
    final service = LLMService(dio: h.dio);
    final response = await service.generateWithReasoning(
        prompt, router.copyWith(openRouterProvider: 'Google'));
    final request = h.requests.single;
    expect(request.uri.toString(),
        'https://openrouter.ai/api/v1/chat/completions');
    expect((request.data as Map)['model'], router.model);
    expect((request.data as Map)['provider'], {
      'order': ['Google'],
      'allow_fallbacks': true
    });
    expect((request.data as Map).containsKey('cache_control'), isFalse);
    expect(_count((request.data as Map)['messages']), 3);
    expect(response.content, 'Hello');
    expect(response.cacheUsage!.cachedTokens, 1000);
  });

  test(
      'actual streaming request emits content, reasoning and final usage counters',
      () async {
    final h = _Transport(streaming: true);
    final chunks = await LLMService(dio: h.dio)
        .generateStreamWithReasoning(prompt, router)
        .toList();
    expect(chunks.map((c) => c.content ?? '').join(), 'Hello');
    expect(chunks.map((c) => c.reasoning ?? '').join(), 'Thought');
    final reported = chunks.where((c) => c.cacheUsage != null).toList();
    expect(reported, hasLength(1));
    expect(reported.single.cacheUsage!.cacheWriteTokens, 100);
    final data = h.requests.single.data as Map;
    expect(_count(data['messages']), 3);
    expect(data['stream'], isTrue);
    expect(data.containsKey('stream_options'), isFalse);
    expect(data.containsKey('usage'), isFalse);
  });

  test('explicit opt-out removes app-added markers but retains usage reporting',
      () async {
    final h = _Transport();
    final response = await LLMService(dio: h.dio).generateWithReasoning(
        prompt, router.copyWith(openRouterPromptCacheEnabled: false));
    expect((h.requests.single.data as Map)['messages'], prompt);
    expect(_count(h.requests.single.data), 0);
    expect(response.cacheUsage!.cachedTokens, 1000);
  });

  test('other OpenRouter models and ordinary OpenAI requests stay unchanged',
      () async {
    for (final config in [
      router.copyWith(model: 'openai/gpt-fixture'),
      router.copyWith(provider: LLMProvider.openai),
      router.copyWith(provider: LLMProvider.openAICompatible),
    ]) {
      final h = _Transport();
      final response =
          await LLMService(dio: h.dio).generateWithReasoning(prompt, config);
      expect((h.requests.single.data as Map)['messages'], prompt);
      expect(_count(h.requests.single.data), 0);
      if (config.provider != LLMProvider.openRouter)
        expect(response.cacheUsage, isNull);
    }
  });

  test('inline thinking extraction retains cache counters', () async {
    final h = _Transport(content: '<think>Thought</think>Hello');
    final response =
        await LLMService(dio: h.dio).generateWithReasoning(prompt, router);
    expect(response.content, 'Hello');
    expect(response.reasoning, 'Thought');
    expect(response.cacheUsage!.cachedTokens, 1000);
  });

  test('opt-out persists across provider switching and reload', () async {
    SharedPreferences.setMockInitialValues(
        {'llm_config': jsonEncode(router.toJson())});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = LLMConfigNotifier(prefs, db);
    addTearDown(settings.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    settings.updateOpenRouterPromptCacheEnabled(false);
    await settings.flushPersistence();
    await settings.updateProvider(LLMProvider.claude);
    expect(settings.state.promptCacheEnabled, isFalse);
    await settings.updateProvider(LLMProvider.openRouter);
    expect(settings.state.openRouterPromptCacheEnabled, isFalse);
    final restored = LLMConfigNotifier(prefs, db);
    addTearDown(restored.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(restored.state.openRouterPromptCacheEnabled, isFalse);
  });

  testWidgets(
      'selected swipe shows reported counters without estimates or raw data',
      (tester) async {
    final message = ChatMessage(
      id: 'fixture',
      chatId: 'fixture',
      role: MessageRole.assistant,
      content: 'Hello',
      timestamp: DateTime(2026),
      swipes: const ['Hello', 'Other'],
      currentSwipeIndex: 1,
      metadata: PromptCacheUsage.forMessage(
          PromptCacheUsage.forMessage(
              {}, const PromptCacheUsage(cachedTokens: 900), 0),
          const PromptCacheUsage(cachedTokens: 120, cacheWriteTokens: 0),
          1),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PromptCacheUsagePreview(message: message))));
    expect(find.text('Cache read: 120 tokens · Cache write: 0 tokens'),
        findsOneWidget);
    expect(find.textContaining('900'), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PromptCacheUsagePreview(
                message: message.copyWith(currentSwipeIndex: 2)))));
    expect(find.textContaining('Cache read:'), findsNothing);
  });
}

int _count(Object? value) {
  if (value is List) return value.fold(0, (n, item) => n + _count(item));
  if (value is Map)
    return (value.containsKey('cache_control') ? 1 : 0) +
        value.values.fold<int>(0, (n, item) => n + _count(item));
  return 0;
}

bool _marked(Map<dynamic, dynamic> message) => _count(message['content']) > 0;
List<Map<String, dynamic>> _plain(List<Map<String, dynamic>> messages) =>
    messages.map((message) {
      final content = message['content'];
      return {
        ...message,
        if (content is List &&
            content.every((part) => part is Map && part['type'] == 'text'))
          'content': content.map((part) => part['text']).join()
      };
    }).toList();

class _Transport implements HttpClientAdapter {
  _Transport({this.streaming = false, this.content = 'Hello'}) {
    dio = Dio()..httpClientAdapter = this;
  }
  final bool streaming;
  final String content;
  late final Dio dio;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (streaming) {
      final events = [
        {
          'choices': [
            {
              'delta': {'reasoning_content': 'Thought'}
            }
          ]
        },
        {
          'choices': [
            {
              'delta': {'content': content}
            }
          ]
        },
        {'choices': <Map<String, dynamic>>[], 'usage': usage},
      ];
      return ResponseBody.fromString(
          events.map((e) => 'data: ${jsonEncode(e)}\n\n').join() +
              'data: [DONE]\n\n',
          200,
          headers: {
            'content-type': ['text/event-stream']
          });
    }
    return ResponseBody.fromString(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content}
            }
          ],
          'usage': usage,
        }),
        200,
        headers: {
          'content-type': ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}
