import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/data/database/database.dart';
import 'package:native_tavern/domain/models/tool_calling.dart';
import 'package:native_tavern/domain/services/tool_calling/claude_tool_calling_adapter.dart';
import 'package:native_tavern/domain/services/tool_calling/gemini_tool_calling_adapter.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/openrouter_prompt_cache.dart';
import 'package:native_tavern/domain/services/prompt_cache_policy.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_responses.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const transcript = <Map<String, dynamic>>[
  {'role': 'system', 'content': 'Stable instructions'},
  {'role': 'user', 'content': 'Old question'},
  {'role': 'assistant', 'content': 'Old answer'},
  {'role': 'user', 'content': 'New question'},
];
const explicitConfigs = [
  LLMConfig(
      provider: LLMProvider.claude,
      model: 'claude-sonnet-5-5',
      apiKey: 'synthetic',
      apiUrl: 'https://api.anthropic.com'),
  LLMConfig(
      provider: LLMProvider.openai,
      model: 'gpt-6.1-sol',
      apiKey: 'synthetic',
      apiUrl: 'https://api.openai.com/v1'),
  LLMConfig(
      provider: LLMProvider.qwen,
      model: 'qwen3.8-max',
      apiKey: 'synthetic',
      apiUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1'),
  LLMConfig(
      provider: LLMProvider.openRouter,
      model: 'qwen/qwen3.6-plus',
      apiKey: 'synthetic',
      apiUrl: 'https://openrouter.ai/api/v1'),
  LLMConfig(
      provider: LLMProvider.openRouter,
      model: 'openai/gpt-5.6',
      apiKey: 'synthetic',
      apiUrl: 'https://openrouter.ai/api/v1'),
  LLMConfig(
      provider: LLMProvider.openRouter,
      model: 'anthropic/claude-fable-5.1',
      apiKey: 'synthetic',
      apiUrl: 'https://openrouter.ai/api/v1'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every existing provider has a transparent caching policy', () {
    for (final provider in LLMProvider.values) {
      final policy = PromptCachePolicy.forConnection(
          provider.name, 'unknown', 'https://custom.invalid');
      expect(policy.description, isNotEmpty);
      expect(policy.appControlled, isFalse, reason: provider.name);
    }
    expect(
        PromptCachePolicy.forConnection(
                'chatgptPlan', 'gpt-6-astra', 'https://api.openai.com/v1')
            .description,
        contains('official'));
    for (final p in ['ollama', 'koboldCpp']) {
      expect(
          PromptCachePolicy.forConnection(p, 'local', 'http://localhost').mode,
          PromptCacheMode.local);
    }
  });

  test(
      'documented explicit gates include newer Claude, OpenAI and Qwen; aliases stay conservative',
      () {
    for (final config in explicitConfigs) {
      expect(config.promptCachePolicy.appControlled, isTrue,
          reason: config.model);
    }
    for (final model in [
      'qwen/qwen3.5-plus-02-15',
      'qwen/unknown',
      'openai/gpt-fixture',
      'anthropic/claude-unknown'
    ]) {
      expect(
          PromptCachePolicy.forConnection(
                  'openRouter', model, 'https://openrouter.ai/api/v1')
              .appControlled,
          isFalse,
          reason: model);
    }
    expect(
        PromptCachePolicy.forConnection(
                'openai', 'gpt-6.1-sol', 'https://proxy.invalid/v1')
            .appControlled,
        isFalse);
    expect(
        PromptCachePolicy.forConnection(
                'openAICompatible', 'gpt-6.1-sol', 'https://api.openai.com/v1')
            .appControlled,
        isTrue);
    expect(PromptCachePolicy.modernOpenAi('gpt-5.5'), isFalse);
    expect(PromptCachePolicy.modernOpenAi('gpt-5.6-20260901'), isTrue);
    expect(
        PromptCachePolicy.forConnection('gemini', 'gemini-2.5-flash',
                'https://generativelanguage.googleapis.com/v1beta')
            .mode,
        PromptCacheMode.implicit);
    expect(
        PromptCachePolicy.forConnection('gemini', 'gemini-2.0-flash',
                'https://generativelanguage.googleapis.com/v1beta')
            .mode,
        PromptCacheMode.resource);
  });

  for (final config in explicitConfigs) {
    for (final streaming in [false, true]) {
      test(
          '${config.provider.name}/${config.model} stable prefixes and exact protocol, stream=$streaming',
          () async {
        final h = _Adapter(config.provider);
        final service = LLMService(dio: h.dio);
        final original = jsonEncode(transcript);
        Future<PromptCacheUsage?> call(
            List<Map<String, dynamic>> messages) async {
          if (!streaming)
            return (await service.generateWithReasoning(messages, config))
                .cacheUsage;
          final chunks = await service
              .generateStreamWithReasoning(messages, config)
              .toList();
          expect(
              chunks.map((c) => c.content).whereType<String>().join(), 'Reply');
          final counters = chunks
              .map((c) => c.cacheUsage)
              .whereType<PromptCacheUsage>()
              .toList();
          expect(counters, hasLength(1),
              reason: 'Cumulative usage must not be counted twice.');
          return counters.single;
        }

        final usage = await call(transcript);
        expect(usage!.cachedTokens, 900);
        expect(usage.cacheWriteTokens, 100);
        await call([
          ...transcript,
          const {'role': 'assistant', 'content': 'Reply'},
          const {'role': 'user', 'content': 'Follow up'}
        ]);
        final first = h.requests[0].data as Map;
        final second = h.requests[1].data as Map;
        final ai =
            config.promptCachePolicy.mode == PromptCacheMode.openAiBreakpoints;
        expect(OpenRouterPromptCache.countBreakpoints(first), greaterThan(0));
        expect(OpenRouterPromptCache.countBreakpoints(first),
            lessThanOrEqualTo(4));
        expect(jsonEncode(first),
            contains(ai ? 'prompt_cache_breakpoint' : 'cache_control'));
        expect(jsonEncode(first),
            isNot(contains(ai ? 'cache_control' : 'prompt_cache_breakpoint')));
        if (ai)
          expect(first['prompt_cache_options'], {'mode': 'explicit'});
        else
          expect(first.containsKey('prompt_cache_options'), isFalse);
        final instructions = config.provider == LLMProvider.claude
            ? first['system']
            : (first['messages'] as List).first['content'];
        final nextInstructions = config.provider == LLMProvider.claude
            ? second['system']
            : (second['messages'] as List).first['content'];
        expect(instructions, nextInstructions);
        expect(jsonEncode(transcript), original);
        expect(jsonEncode(first), isNot(contains('prewarm')));
        expect(h.requests, hasLength(2));
        h.dio.close();
      });
    }
    test('${config.provider.name}/${config.model} opt-out adds no markers',
        () async {
      final off = config.copyWith(
          promptCacheEnabled: false,
          openRouterPromptCacheEnabled: false,
          automaticPromptCacheEnabled: false);
      final h = _Adapter(off.provider);
      await LLMService(dio: h.dio).generateWithReasoning(transcript, off);
      final request = h.requests.single.data as Map;
      expect(OpenRouterPromptCache.countBreakpoints(request), 0);
      if (off.promptCachePolicy.mode == PromptCacheMode.openAiBreakpoints) {
        expect(request['prompt_cache_options'], {'mode': 'explicit'});
      }
      expect(LLMConfig.fromJson(off.toJson()).automaticCacheEnabled, isFalse);
      h.dio.close();
    });
  }

  test(
      'implicit providers and compatible proxies receive no explicit cache controls',
      () async {
    final cases = [
      (LLMProvider.openai, 'gpt-4.1', 'https://api.openai.com/v1'),
      (LLMProvider.deepSeek, 'deepseek-chat', 'https://api.deepseek.com/v1'),
      (LLMProvider.moonshot, 'kimi-k3', 'https://api.moonshot.ai/v1'),
      (LLMProvider.zai, 'glm-5', 'https://api.z.ai/api/paas/v4'),
      (LLMProvider.miniMax, 'MiniMax-M3', 'https://api.minimax.io/v1'),
      (LLMProvider.siliconFlow, 'unknown', 'https://api.siliconflow.com/v1'),
      (
        LLMProvider.openAICompatible,
        'gpt-6.1-sol',
        'https://custom.invalid/v1'
      ),
      (LLMProvider.openRouter, 'x-ai/grok-4', 'https://openrouter.ai/api/v1'),
    ];
    for (final (provider, model, url) in cases) {
      final h = _Adapter(provider);
      final config = LLMConfig(
          provider: provider, model: model, apiKey: 'synthetic', apiUrl: url);
      final response = await LLMService(dio: h.dio)
          .generateWithReasoning(transcript, config);
      final request = h.requests.single.data as Map;
      expect(request['messages'], transcript);
      expect(request.containsKey('prompt_cache_options'), isFalse,
          reason: provider.name);
      expect(OpenRouterPromptCache.countBreakpoints(request), 0,
          reason: provider.name);
      expect(response.cacheUsage!.cachedTokens, 900);
      h.dio.close();
    }
  });

  test(
      'numeric usage adapters retain zeros, reject private and invalid data, and do not mislabel misses as writes',
      () {
    expect(
        PromptCacheUsage.fromOpenAi({
          'prompt_cache_hit_tokens': 100,
          'prompt_cache_miss_tokens': 500
        })!
            .toJson(),
        {'cached_tokens': 100});
    expect(
        PromptCacheUsage.fromOpenAi({
          'prompt_tokens_details': {
            'cached_tokens': 0,
            'cache_creation_input_tokens': 12
          },
          'prompt': 'private'
        })!
            .toJson(),
        {'cached_tokens': 0, 'cache_write_tokens': 12});
    expect(
        PromptCacheUsage.fromAnthropic({
          'cache_read_input_tokens': 123,
          'cache_creation_input_tokens': 456,
          'private': 'secret'
        })!
            .toJson(),
        {'cached_tokens': 123, 'cache_write_tokens': 456});
    expect(
        PromptCacheUsage.fromGemini({'cachedContentTokenCount': 78})!.toJson(),
        {'cached_tokens': 78});
    for (final bad in ['300', -1, double.nan, 0.5]) {
      expect(
          PromptCacheUsage.fromOpenAi({
            'prompt_tokens_details': {'cached_tokens': bad}
          }),
          isNull);
    }
    expect(PromptCacheUsage.fromOpenAi({'prompt_tokens': 100}), isNull);
    expect(
        PromptCacheUsage.snapshot(const PromptCacheUsage(cachedTokens: 90),
                const PromptCacheUsage(cachedTokens: 90, cacheWriteTokens: 10))!
            .toJson(),
        {'cached_tokens': 90, 'cache_write_tokens': 10});
  });

  test('legacy config and saved metrics migrate without overriding opt-outs',
      () async {
    final legacy = explicitConfigs.first.toJson()
      ..remove('promptCacheEnabled')
      ..remove('automaticPromptCacheEnabled');
    expect(LLMConfig.fromJson(legacy).automaticCacheEnabled, isTrue);
    legacy['promptCacheEnabled'] = false;
    expect(LLMConfig.fromJson(legacy).automaticCacheEnabled, isFalse);
    expect(
        PromptCacheUsage.forSwipe({
          'openRouterCacheUsageBySwipe': {
            '0': {'cached_tokens': 91}
          }
        }, 0)!
            .cachedTokens,
        91);
    SharedPreferences.setMockInitialValues(
        {'llm_config': jsonEncode(explicitConfigs[1].toJson())});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final settings = LLMConfigNotifier(prefs, db);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    settings.updateAutomaticPromptCacheEnabled(false);
    await settings.flushPersistence();
    final reloaded = LLMConfigNotifier(prefs, db);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reloaded.state.automaticPromptCacheEnabled, isFalse);
    reloaded.dispose();
    settings.dispose();
    await db.close();
  });

  test(
      'native Gemini stream accepts usage-only and repeated cumulative objects without creating resources',
      () async {
    final h = _Adapter(LLMProvider.gemini);
    final config = LLMConfig(
        provider: LLMProvider.gemini,
        model: 'gemini-3.1-pro',
        apiKey: 'synthetic',
        apiUrl: 'https://generativelanguage.googleapis.com/v1beta');
    final service = LLMService(dio: h.dio);
    final chunks =
        await service.generateStreamWithReasoning(transcript, config).toList();
    expect(chunks.map((c) => c.content).whereType<String>().join(), 'Reply');
    expect(chunks.where((c) => c.cacheUsage != null), hasLength(1));
    expect(chunks.last.cacheUsage!.cachedTokens, 900);
    expect(chunks.last.cacheUsage!.cacheWriteTokens, isNull);
    final response = await service.generateWithReasoning(transcript, config);
    expect(response.cacheUsage!.cachedTokens, 900);
    expect(h.requests, hasLength(2));
    expect(h.requests.every((r) => !r.path.contains('cachedContents')), isTrue);
    expect(
        h.requests.every((r) => !jsonEncode(r.data).contains('cache_control')),
        isTrue);
    h.dio.close();
  });

  test('native tool requests retain schemas, signatures and provider counters',
      () async {
    for (final provider in [LLMProvider.claude, LLMProvider.gemini]) {
      final config = provider == LLMProvider.claude
          ? explicitConfigs.first
          : const LLMConfig(
              provider: LLMProvider.gemini,
              model: 'gemini-2.5-flash',
              apiKey: 'synthetic',
              apiUrl: 'https://generativelanguage.googleapis.com/v1beta');
      final h = _Adapter(provider);
      final result = await LLMService(dio: h.dio).generateToolTurn(
          baseMessages: transcript,
          continuationMessages: const [],
          config: config,
          toolConfiguration: ToolCallingConfiguration.enabled(tools: [
            ToolDefinition(
                name: 'fixture_tool',
                description: 'Synthetic test tool',
                inputSchema: {
                  'type': 'object',
                  'properties': <String, dynamic>{}
                }),
          ]),
          adapter: provider == LLMProvider.claude
              ? const ClaudeToolCallingAdapter()
              : const GeminiToolCallingAdapter(),
          cancellationToken: ToolCancellationController().token);
      expect(result.cacheUsage!.cachedTokens, 900);
      expect(result.assistant.text, 'Reply');
      expect((h.requests.single.data as Map)['tools'], isNotEmpty);
      if (provider == LLMProvider.claude) {
        expect(OpenRouterPromptCache.countBreakpoints(h.requests.single.data),
            greaterThan(0));
      } else {
        expect(
            OpenRouterPromptCache.countBreakpoints(h.requests.single.data), 0);
      }
      h.dio.close();
    }
  });

  test('official ChatGPT Responses only reports confirmed final numeric usage',
      () async {
    final events = [
      {'type': 'response.output_text.delta', 'delta': 'Reply'},
      {
        'type': 'response.completed',
        'response': {
          'status': 'completed',
          'usage': {
            'input_tokens_details': {
              'cached_tokens': 30,
              'cache_write_tokens': 4
            },
            'private': 'must-not-persist'
          }
        }
      },
    ];
    final chunks = await parseChatGptPlanStream(Stream.value(utf8
            .encode(events.map((e) => 'data: ${jsonEncode(e)}\n\n').join())))
        .toList();
    expect(chunks.first.text, 'Reply');
    expect(chunks.last.cacheUsage!.toJson(),
        {'cached_tokens': 30, 'cache_write_tokens': 4});
    final request = chatGptPlanRequest('gpt-6-astra', transcript);
    expect(request['store'], isFalse);
    expect(request['stream'], isTrue);
    expect(request.containsKey('prompt_cache_options'), isFalse);
    expect(OpenRouterPromptCache.countBreakpoints(request), 0);
  });

  test(
      'tools and manual markers share the four-breakpoint budget; signatures remain untouched',
      () {
    final original = [
      ...transcript,
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'thinking',
            'thinking': 'Synthetic',
            'signature': 'signature'
          },
          {'type': 'text', 'text': 'prefill'}
        ]
      },
    ];
    final plain = jsonEncode(original);
    final out = OpenRouterPromptCache.apply(original, reservedBreakpoints: 3);
    expect(OpenRouterPromptCache.countBreakpoints(out), 1);
    expect(out.last, original.last);
    expect(jsonEncode(original), plain);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.provider) {
    dio = Dio()..httpClientAdapter = this;
  }
  final LLMProvider provider;
  late final Dio dio;
  final requests = <RequestOptions>[];
  static const aiUsage = {
    'prompt_tokens_details': {'cached_tokens': 900, 'cache_write_tokens': 100}
  };
  static const claudeUsage = {
    'cache_read_input_tokens': 900,
    'cache_creation_input_tokens': 100
  };
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(request);
    final streaming = (request.data as Map)['stream'] == true ||
        request.path.contains('streamGenerateContent');
    final geminiResponse = {
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': 'Reply'}
            ]
          }
        }
      ],
      'usageMetadata': {'cachedContentTokenCount': 900}
    };
    final response = provider == LLMProvider.claude
        ? {
            'content': [
              {'type': 'text', 'text': 'Reply'}
            ],
            'usage': claudeUsage
          }
        : provider == LLMProvider.gemini
            ? geminiResponse
            : {
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': 'Reply'}
                  }
                ],
                'usage': aiUsage
              };
    if (!streaming)
      return ResponseBody.fromString(jsonEncode(response), 200, headers: {
        'content-type': ['application/json']
      });
    if (provider == LLMProvider.gemini) {
      return ResponseBody.fromString(
          jsonEncode([
            geminiResponse,
            {
              'usageMetadata': {'cachedContentTokenCount': 900}
            }
          ]),
          200,
          headers: {
            'content-type': ['application/json']
          });
    }
    final events = provider == LLMProvider.claude
        ? [
            {
              'type': 'message_start',
              'message': {'usage': claudeUsage}
            },
            {
              'type': 'content_block_delta',
              'delta': {'type': 'text_delta', 'text': 'Reply'}
            },
            {'type': 'message_delta', 'usage': claudeUsage},
            {'type': 'message_stop'},
          ]
        : [
            {
              'choices': [
                {
                  'delta': {'content': 'Reply'}
                }
              ]
            },
            {'choices': <Map<String, dynamic>>[], 'usage': aiUsage},
            {'choices': <Map<String, dynamic>>[], 'usage': aiUsage},
          ];
    return ResponseBody.fromString(
        events.map((e) => 'data: ${jsonEncode(e)}\n\n').join() +
            'data: [DONE]\n\n',
        200,
        headers: {
          'content-type': ['text/event-stream']
        });
  }

  @override
  void close({bool force = false}) {}
}
