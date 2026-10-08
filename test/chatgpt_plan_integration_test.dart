import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:native_tavern/domain/services/chatgpt_plan_client.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/tts_service.dart';
import 'package:native_tavern/domain/services/stt_service.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/chat_providers.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/providers/tts_providers.dart';
import 'package:native_tavern/presentation/providers/stt_providers.dart';
import 'package:native_tavern/presentation/providers/vector_storage_providers.dart';
import 'package:native_tavern/presentation/screens/ai_config/ai_config_screen.dart';
import 'package:native_tavern/presentation/screens/ai_config/chatgpt_plan_tile.dart';
import 'package:native_tavern/presentation/screens/chat/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chatgpt_plan_fixture.dart';
import 'support/fake_system_tts_backend.dart';
import 'support/fake_stt_backends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() async {
    h = await _Harness.create();
  });
  tearDown(() async {
    await h.close();
  });

  test(
      'saved plan settings restore, reconnect retains the model, and API settings survive',
      () async {
    final config = h.container.read(llmConfigProvider);
    expect(config.provider, LLMProvider.chatgptPlan);
    expect(config.apiKey, isEmpty);
    expect(config.hasConnectionSettings, isTrue);
    expect(h.container.read(llmConnectionReadyProvider), isTrue);
    final settings = h.container.read(llmConfigProvider.notifier);
    settings.updateChatGptProfile(config.chatgptProfileId);
    expect(settings.state.model, config.model);
    await settings.updateProvider(LLMProvider.openai);
    settings.updateApiKey('synthetic-api-key');
    settings.updateModel('api-model');
    await settings.flushPersistence();
    // An OAuth completion after switching provider must not erase an API key.
    settings.updateChatGptProfile('oaiapp_fixture');
    expect(settings.state.apiKey, 'synthetic-api-key');
    expect(settings.state.model, 'api-model');
    await settings.updateProvider(LLMProvider.chatgptPlan);
    expect(settings.state.chatgptProfileId, config.chatgptProfileId);
    expect(settings.state.model, config.model);
    expect(settings.state.apiKey, isEmpty);
    await settings.flushPersistence();
    final restored = LLMConfigNotifier(h.prefs, h.database);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(restored.state.toJson(), settings.state.toJson());
    restored.dispose();
    final json = jsonEncode(await settings.getAllProviderConfigs());
    expect(json, isNot(contains('synthetic-oaiapp')));
    expect(json, isNot(contains('synthetic-refresh')));
  });

  test('identity-only session is connected but never configured for inference',
      () async {
    h.fixture.store.value = ChatGptPlanMemoryStore(sharing: false).value;
    h.container.invalidate(chatGptAccountsProvider);
    final account =
        (await h.container.read(chatGptAccountsProvider.future)).first;
    expect(account.connected, isTrue);
    expect(account.sharing, isFalse);
    expect(h.container.read(llmConnectionReadyProvider), isFalse);
    expect(h.container.read(chatGptConnectionIssueProvider),
        contains('Enable plan usage'));
    final fetch = h.container.read(modelFetchProvider.notifier);
    await fetch.fetchModels(fixturePlanConfig);
    expect(fetch.state.status, ModelFetchStatus.error);
    expect(fetch.state.errorMessage, contains('Enable ChatGPT plan usage'));
    await expectLater(
        h.fixture.service.generate([
          {'role': 'user', 'content': 'Hello'}
        ], fixturePlanConfig),
        throwsA(isA<ChatGptPlanException>()));
    expect(h.fixture.requests, isEmpty);
  });

  test(
      'catalog restores account ordering, filters hidden models, and selects a default',
      () async {
    final settings = h.container.read(llmConfigProvider.notifier);
    settings.updateModel('');
    final fetch = h.container.read(modelFetchProvider.notifier);
    await fetch.ensureModels(settings.state);
    expect(fetch.state.models, ['fixture-model-b', 'fixture-model-a']);
    expect(fetch.state.modelNames,
        {'fixture-model-b': 'Fixture B', 'fixture-model-a': 'Fixture A'});
    expect(settings.state.model, 'fixture-model-b');
    expect(fetch.state.isFor(settings.state), isTrue);
    await fetch.ensureModels(settings.state);
    expect(h.fixture.requests, hasLength(1));
    await settings.flushPersistence();
  });

  test(
      'account switch invalidates an in-flight catalog and cannot select the old model',
      () async {
    final waiting = Completer<ResponseBody>();
    h.fixture.modelHandler = (r) async {
      if (r.headers['Authorization'] == 'Bearer synthetic-oaiapp_fixture') {
        return await waiting.future;
      }
      return fixtureJson({
        'models': [
          {
            'slug': 'second-model',
            'display_name': 'Second model',
            'visibility': 'list'
          }
        ]
      });
    };
    final settings = h.container.read(llmConfigProvider.notifier);
    final fetch = h.container.read(modelFetchProvider.notifier);
    settings.updateModel('');
    final oldFetch = fetch.fetchModels(settings.state);
    await Future<void>.delayed(Duration.zero);
    settings.updateChatGptProfile('oaiapp_second');
    await fetch.fetchModels(settings.state);
    waiting.complete(fixtureJson({
      'models': [
        {'slug': 'old-account-model', 'visibility': 'list'}
      ]
    }));
    await oldFetch;
    expect(fetch.state.models, ['second-model']);
    expect(settings.state.model, 'second-model');
    expect(fetch.state.isFor(settings.state), isTrue);
    await settings.updateProvider(LLMProvider.openai);
    expect(fetch.state.status, ModelFetchStatus.idle);
    expect(h.container.read(llmConnectionReadyProvider), isFalse);
  });

  for (final streaming in [true, false]) {
    test(
        'restored plan generates and persists an actual chat reply, UI stream=$streaming',
        () async {
      final settings = h.container.read(llmConfigProvider.notifier);
      settings.updateStreamEnabled(streaming);
      final notifier = h.container.read(activeChatProvider.notifier);
      await notifier.sendMessage('Which way?', settings.state);
      expect(notifier.state.error, isNull);
      expect(notifier.state.isGenerating, isFalse);
      final saved = await h.repository.getMessages(h.chatId);
      expect(saved.map((m) => m.content), ['Which way?', 'A saved reply ✓']);
      final request = h.fixture.requests.single;
      expect(request.path, ChatGptPlanClient.apiRoot + '/responses');
      expect(request.method, 'POST');
      expect(
          request.headers['Authorization'], 'Bearer synthetic-oaiapp_fixture');
      final body = request.data as Map;
      expect(body['model'], 'fixture-model-b');
      expect(body['store'], isFalse);
      expect(body['stream'], isTrue);
      final input = body['input'] as List;
      expect(input.any((m) => m['role'] == 'system'), isFalse);
      expect(input.where((m) => m['role'] == 'user').last['content'],
          'Which way?');
      expect(body.keys, unorderedEquals(['model', 'input', 'store', 'stream']));
    });
  }

  test(
      'policy denial reaches the chat error and is not reported as a saved assistant reply',
      () async {
    h.fixture.responseHandler = (_) => fixtureJson({
          'error': {
            'code': 'subscription_sharing_user_not_eligible',
            'message': 'synthetic-secret-must-not-be-shown',
          }
        }, status: 403);
    final notifier = h.container.read(activeChatProvider.notifier);
    await notifier.sendMessage('Hello', h.container.read(llmConfigProvider));
    expect(notifier.state.error, contains('not enabled ChatGPT plan usage'));
    expect(notifier.state.error, contains('HTTP 403'));
    expect(notifier.state.error, contains('req_fixture'));
    expect(notifier.state.error, isNot(contains('synthetic-secret')));
    expect(notifier.state.isGenerating, isFalse);
    expect((await h.repository.getMessages(h.chatId)).map((m) => m.content),
        ['Hello']);
    expect(h.fixture.requests, hasLength(1));
  });

  for (final kind in ['failed', 'incomplete', 'disconnected']) {
    test(
        'late $kind stream remains a user-facing failure through the chat pipeline',
        () async {
      h.fixture.responseHandler = (_) => fixtureEvents([
            {'type': 'response.output_text.delta', 'delta': 'Partial reply'},
            if (kind != 'disconnected')
              {
                'type': 'response.' + kind,
                'response': {
                  'error': {
                    'code': 'subscription_sharing_usage_limit_exceeded',
                    'message': 'synthetic-secret-must-not-be-shown',
                  }
                }
              },
          ]);
      final notifier = h.container.read(activeChatProvider.notifier);
      await notifier.sendMessage('Hello', fixturePlanConfig);
      expect(notifier.state.error, isNotNull);
      expect(
          notifier.state.error,
          contains(kind == 'disconnected'
              ? 'before response.completed'
              : 'usage limit reached'));
      expect(notifier.state.error, isNot(contains('synthetic-secret')));
      expect(notifier.state.isGenerating, isFalse);
      expect((await h.repository.getMessages(h.chatId)), hasLength(1));
    });
  }

  test(
      'connection test requires completed inference, not successful OAuth or model discovery',
      () async {
    h.fixture.responseHandler = (_) => fixtureJson({
          'error': {'code': 'chatpass_v2_scope_not_authorized'}
        }, status: 403);
    final connection = h.container.read(connectionTestProvider.notifier);
    await connection.testConnection(fixturePlanConfig);
    expect(connection.state.status, ConnectionStatus.error);
    expect(connection.state.message, contains('Enable plan usage'));
    expect(h.fixture.requests, hasLength(1));
    expect(h.fixture.requests.single.path, endsWith('/responses'));
  });

  test('switching accounts discards a late connection-test result', () async {
    final pending = Completer<ResponseBody>();
    h.fixture.responseHandler = (_) => pending.future;
    final connection = h.container.read(connectionTestProvider.notifier);
    final checking = connection.testConnection(fixturePlanConfig);
    await Future<void>.delayed(Duration.zero);
    h.container
        .read(llmConfigProvider.notifier)
        .updateChatGptProfile('oaiapp_second');
    pending.complete(fixtureEvents([
      {'type': 'response.output_text.delta', 'delta': 'Connected'},
      fixtureCompleted,
    ]));
    await checking;
    expect(connection.state.status, ConnectionStatus.idle);
    expect(h.fixture.requests, hasLength(1));
  });

  testWidgets(
      'normal Model tile restores the catalog and displays searchable account model names',
      (tester) async {
    await tester.pumpWidget(h.app(const LLMModelTile()));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('llm-model')), findsOneWidget);
    await _pumpUntil(
        tester,
        () =>
            h.container.read(modelFetchProvider).status ==
            ModelFetchStatus.success);
    expect(find.text('Fixture B'), findsOneWidget);
    expect(h.fixture.requests.where((r) => r.path.endsWith('/models')),
        hasLength(1));
    await tester.tap(find.byKey(const ValueKey('llm-model')));
    await tester.pumpAndSettle();
    expect(find.text('Fixture A'), findsOneWidget);
    expect(find.text('hidden-model'), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    await tester.enterText(find.byType(TextField), 'Fixture A');
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'Fixture A'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Fixture A'));
    await tester.pumpAndSettle();
    expect(h.container.read(llmConfigProvider).model, 'fixture-model-a');
    var persisted = false;
    h.container.read(llmConfigProvider.notifier).flushPersistence().then((_) {
      persisted = true;
    });
    await _pumpUntil(tester, () => persisted);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await _closeWidgetHarness(tester, h);
  });

  testWidgets(
      'catalog denial is persistent and offers an explicit retry without sign-in loops',
      (tester) async {
    h.fixture.modelHandler = (_) => fixtureJson({
          'error': {'code': 'subscription_sharing_user_not_eligible'}
        }, status: 403);
    await tester.pumpWidget(h.app(const LLMModelTile()));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await _pumpUntil(
        tester,
        () =>
            h.container.read(modelFetchProvider).status ==
            ModelFetchStatus.error);
    expect(find.byKey(const ValueKey('model-catalog-error')), findsOneWidget);
    expect(find.text('Retry models'), findsOneWidget);
    await tester.pump();
    expect(h.fixture.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await _closeWidgetHarness(tester, h);
  });

  testWidgets(
      'identity-only account offers plan authorization next to the existing connection settings',
      (tester) async {
    h.fixture.store.value = ChatGptPlanMemoryStore(sharing: false).value;
    h.container.invalidate(chatGptAccountsProvider);
    await tester
        .runAsync(() => h.container.read(chatGptAccountsProvider.future));
    await tester.pumpWidget(h.app(const ChatGptPlanTile()));
    await tester.pump();
    expect(find.text('Enable plan usage'), findsOneWidget);
    expect(find.text('ChatGPT plan usage authorized'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await _closeWidgetHarness(tester, h);
  });

  for (final mime in ['text/event-stream', 'application/json']) {
    testWidgets(
        'chat composer sends through protected plan auth without an API key, MIME=$mime',
        (tester) async {
      h.fixture.responseHandler = (_) {
        final response = fixtureEvents([
          {'type': 'response.output_text.delta', 'delta': 'A saved reply ✓'},
          fixtureCompleted
        ]);
        response.headers[Headers.contentTypeHeader] = [mime];
        return response;
      };
      await tester.pumpWidget(h.app(ChatScreen(chatId: h.chatId)));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(find.text('API Not Configured'), findsNothing);
      expect(find.text('ChatGPT setup required'), findsNothing);
      final input = find.byType(TextField).first;
      await tester.enterText(input, 'Hello from the composer');
      await tester.tap(find.byIcon(Icons.send));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      await _pumpUntil(
          tester,
          () =>
              !h.container.read(activeChatProvider).isGenerating &&
              h.container.read(activeChatProvider).messages.last.content ==
                  'A saved reply ✓');
      final saved =
          await tester.runAsync(() => h.repository.getMessages(h.chatId));
      expect(saved!.map((m) => m.content),
          ['Hello from the composer', 'A saved reply ✓']);
      expect(h.fixture.requests.single.path, endsWith('/responses'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await _closeWidgetHarness(tester, h);
      await tester.pump();
    });
  }

  testWidgets(
      'HTTP 200 JSON denial reaches the real composer with safe diagnostics',
      (tester) async {
    h.container.read(llmConfigProvider.notifier).updateModel('gpt-6-astra');
    h.fixture.responseHandler = (_) => fixtureJson({
          'error': {
            'code': 'subscription_sharing_user_not_eligible',
            'message': 'PRIVATE_CHAT_AND_TOKEN'
          }
        });
    await tester.pumpWidget(h.app(ChatScreen(chatId: h.chatId)));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField).first, 'Synthetic denial test.');
    await tester.tap(find.byIcon(Icons.send));
    await _pumpUntil(tester, () {
      final state = h.container.read(activeChatProvider);
      return !state.isGenerating && state.error != null;
    });
    final error = h.container.read(activeChatProvider).error!;
    expect(error, contains('subscription_sharing_user_not_eligible'));
    expect(error, contains('HTTP 200'));
    expect(error, contains('Content type: application/json'));
    expect(error, contains('req_fixture'));
    expect(error, isNot(contains('PRIVATE_CHAT_AND_TOKEN')));
    expect(find.textContaining('subscription_sharing_user_not_eligible'),
        findsOneWidget);
    expect(find.text('OpenAI returned an unexpected response type.'),
        findsNothing);
    expect(h.fixture.requests, hasLength(1));
    expect((h.fixture.requests.single.data as Map)['model'], 'gpt-6-astra');
    final saved =
        await tester.runAsync(() => h.repository.getMessages(h.chatId));
    expect(saved!.map((m) => m.content), ['Synthetic denial test.']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await _closeWidgetHarness(tester, h);
  });
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
  final ChatGptPlanFixture fixture;
  final ChatRepository repository;
  final ProviderContainer container;
  final String chatId;

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({
      'llm_config': jsonEncode(fixturePlanConfig.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final directory =
        await Directory.systemTemp.createTemp('nt-plan-integration-');
    final repository = ChatRepository(database);
    final characters = CharacterRepository(database, directory.path);
    final fixture = ChatGptPlanFixture();
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
      name: 'Narrator',
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
    await database.close();
    await directory.delete(recursive: true);
  }
}
