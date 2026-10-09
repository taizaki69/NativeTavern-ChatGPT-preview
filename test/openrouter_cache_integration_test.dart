import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/core/services/initialization_service.dart';
import 'package:native_tavern/data/database/database.dart';
import 'package:native_tavern/data/models/character.dart' as models;
import 'package:native_tavern/data/repositories/character_repository.dart';
import 'package:native_tavern/data/repositories/chat_repository.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_platform.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/tts_service.dart';
import 'package:native_tavern/domain/services/stt_service.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/chat_providers.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/providers/tts_providers.dart';
import 'package:native_tavern/presentation/providers/stt_providers.dart';
import 'package:native_tavern/presentation/providers/vector_storage_providers.dart';
import 'package:native_tavern/presentation/screens/chat/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chatgpt_plan_fixture.dart';
import 'support/fake_system_tts_backend.dart';
import 'support/fake_stt_backends.dart';

const routerConfig = LLMConfig(
  provider: LLMProvider.openRouter,
  model: 'anthropic/claude-sonnet-5.5',
  apiKey: 'synthetic-router-key',
  apiUrl: 'https://openrouter.ai/api/v1',
  autoSummarizeEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() async {
    h = await _Harness.create();
  });
  tearDown(() async {
    await h.close();
  });

  for (final stream in [true, false]) {
    test('actual chat saves reported cache counters, streaming=$stream',
        () async {
      final config =
          h.container.read(llmConfigProvider).copyWith(streamEnabled: stream);
      final notifier = h.container.read(activeChatProvider.notifier);
      await notifier.sendMessage('Synthetic first question', config);
      var saved = await h.repository.getMessages(h.chatId);
      expect(saved.last.content, 'Cached fixture reply');
      expect(PromptCacheUsage.forSwipe(saved.last.metadata, 0)!.cachedTokens,
          1000);
      expect(jsonEncode(saved.last.metadata),
          isNot(contains('private-server-field')));
      await notifier.sendMessage('Synthetic next question', config);
      saved = await h.repository.getMessages(h.chatId);
      expect(h.fixture.requests, hasLength(2));
      final first = h.fixture.requests[0].data as Map;
      final next = h.fixture.requests[1].data as Map;
      expect(_count(first['messages']), greaterThan(0));
      expect(_count(next['messages']), inInclusiveRange(1, 4));
      expect(_plainLeading(first['messages']), _plainLeading(next['messages']));
      expect(
          (next['messages'] as List)
              .lastWhere((m) => m['role'] == 'user')['content'],
          'Synthetic next question');
      expect(
          PromptCacheUsage.forSwipe(saved.last.metadata, 0)!.cacheWriteTokens,
          100);
      expect(h.container.read(activeChatProvider).error, isNull);
    });
  }

  test('regeneration and provider changes retain correct swipe metadata',
      () async {
    final notifier = h.container.read(activeChatProvider.notifier);
    final config = h.container.read(llmConfigProvider);
    await notifier.sendMessage('Synthetic question', config);
    h.fixture.cachedTokens = 2000;
    await notifier.regenerateLastMessage(config);
    var saved = await h.repository.getMessages(h.chatId);
    expect(saved.last.swipes, hasLength(2));
    expect(
        PromptCacheUsage.forSwipe(saved.last.metadata, 0)!.cachedTokens, 1000);
    expect(
        PromptCacheUsage.forSwipe(saved.last.metadata, 1)!.cachedTokens, 2000);
    await notifier.regenerateLastMessage(config.copyWith(
        provider: LLMProvider.openai, model: 'fixture-other-provider'));
    saved = await h.repository.getMessages(h.chatId);
    expect(PromptCacheUsage.forSwipe(saved.last.metadata, 2), isNull);
    expect(
        PromptCacheUsage.forSwipe(saved.last.metadata, 0)!.cachedTokens, 1000);
    await notifier.deleteSwipe(saved.last.id, 0);
    saved = await h.repository.getMessages(h.chatId);
    expect(saved.last.swipes, hasLength(2));
    expect(
        PromptCacheUsage.forSwipe(saved.last.metadata, 0)!.cachedTokens, 2000);
    expect(PromptCacheUsage.forSwipe(saved.last.metadata, 1), isNull);
    expect(PromptCacheUsage.forSwipe(saved.last.metadata, 2), isNull);
  });

  testWidgets('composer renders cache counters from the saved reply',
      (tester) async {
    await tester.pumpWidget(h.app(ChatScreen(chatId: h.chatId)));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField).first, 'Synthetic composer question');
    await tester.tap(find.byIcon(Icons.send));
    await _pumpUntil(
        tester,
        () =>
            !h.container.read(activeChatProvider).isGenerating &&
            h.container.read(activeChatProvider).messages.isNotEmpty &&
            h.container.read(activeChatProvider).messages.last.content ==
                'Cached fixture reply');
    expect(find.text('Cache read: 1000 tokens · Cache write: 100 tokens'),
        findsOneWidget);
    expect(h.fixture.requests.single.path, endsWith('/chat/completions'));
    final saved =
        await tester.runAsync(() => h.repository.getMessages(h.chatId));
    expect(
        PromptCacheUsage.forSwipe(saved!.last.metadata, 0)!.cachedTokens, 1000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await _closeWidgetHarness(tester, h);
  });
}

int _count(Object? value) {
  if (value is List) return value.fold(0, (n, item) => n + _count(item));
  if (value is Map)
    return (value.containsKey('cache_control') ? 1 : 0) +
        value.values.fold<int>(0, (n, item) => n + _count(item));
  return 0;
}

List<String> _plainLeading(dynamic messages) => (messages as List)
    .takeWhile((m) => m['role'] == 'system')
    .map((m) => m['content'] is String
        ? m['content'] as String
        : (m['content'] as List).map((p) => p['text']).join())
    .toList();

class _RouterFixture implements HttpClientAdapter {
  _RouterFixture() {
    dio = Dio()..httpClientAdapter = this;
    service = LLMService(dio: dio, chatGptClient: plan.client);
  }
  final plan = ChatGptPlanFixture();
  ChatGptPlanPlatform get platform => plan.platform;
  late final Dio dio;
  late final LLMService service;
  int cachedTokens = 1000;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions request,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (request.uri.host == 'api.openai.com') return await plan.handle(request);
    if (request.method == 'GET')
      return fixtureJson({
        'data': [
          {'id': routerConfig.model, 'name': 'Sonnet fixture'}
        ]
      });
    requests.add(request);
    final cacheUsage = {
      'prompt_tokens_details': {
        'cached_tokens': cachedTokens,
        'cache_write_tokens': 100
      },
      'private-server-field': 'must-not-persist',
    };
    if ((request.data as Map)['stream'] == true) {
      final events = [
        {
          'choices': [
            {
              'delta': {'content': 'Cached fixture reply'}
            }
          ]
        },
        {'choices': <Map<String, dynamic>>[], 'usage': cacheUsage},
      ];
      return ResponseBody.fromString(
          events.map((e) => 'data: ${jsonEncode(e)}\n\n').join() +
              'data: [DONE]\n\n',
          200,
          headers: {
            'content-type': ['text/event-stream']
          });
    }
    return fixtureJson({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'Cached fixture reply'}
        }
      ],
      'usage': cacheUsage,
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _closeWidgetHarness(WidgetTester tester, _Harness h) async {
  var closed = false;
  h.close().then((_) {
    closed = true;
  });
  await _pumpUntil(tester, () => closed);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() finished) async {
  for (var attempt = 0; attempt < 100 && !finished(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pump();
  expect(finished(), isTrue,
      reason: 'The integration must reach its terminal state.');
}

class _Harness {
  _Harness(this.database, this.directory, this.prefs, this.fixture,
      this.repository, this.container, this.chatId);
  final AppDatabase database;
  final Directory directory;
  final SharedPreferences prefs;
  final _RouterFixture fixture;
  final ChatRepository repository;
  final ProviderContainer container;
  final String chatId;

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({
      'llm_config': jsonEncode(routerConfig.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final directory =
        await Directory.systemTemp.createTemp('nt-plan-integration-');
    final repository = ChatRepository(database);
    final characters = CharacterRepository(database, directory.path);
    final fixture = _RouterFixture();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(database),
      dataPathProvider.overrideWithValue(directory.path),
      sharedPreferencesProvider.overrideWithValue(prefs),
      characterRepositoryProvider.overrideWithValue(characters),
      chatRepositoryProvider.overrideWithValue(repository),
      llmServiceProvider.overrideWithValue(fixture.service),
      chatGptPlanPlatformProvider.overrideWithValue(fixture.platform),
      ragContextProvider.overrideWithValue((_) async => null),
      sttServiceProvider.overrideWithValue(STTService(
        systemBackend: FakeSystemSTTBackend(),
        recorder: FakeSTTAudioRecorder(),
        remoteBackend: FakeRemoteSTTBackend(),
        permissionGateway: FakeSTTPermissionGateway(),
      )),
      ttsServiceProvider
          .overrideWithValue(TTSService(systemTts: FakeSystemTTSBackend())),
      ttsStopProvider.overrideWithValue(({String? ownerId}) async {}),
    ]);
    container.read(llmConfigProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await container.read(chatGptAccountsProvider.future);
    final now = DateTime.now();
    await characters.createCharacter(models.Character(
      id: 'plan-character',
      name: 'Cache fixture',
      description: 'Stable fixture description. ' * 100,
      createdAt: now,
      modifiedAt: now,
    ));
    final chatId = (await container
        .read(activeChatProvider.notifier)
        .createChat('plan-character'))!;
    return _Harness(
        database, directory, prefs, fixture, repository, container, chatId);
  }

  Widget app(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: child is ChatScreen
              ? child
              : Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await container.read(llmConfigProvider.notifier).flushPersistence();
    container.dispose();
    fixture.dio.close(force: true);
    fixture.plan.dio.close(force: true);
    await database.close();
    await directory.delete(recursive: true);
  }
}
