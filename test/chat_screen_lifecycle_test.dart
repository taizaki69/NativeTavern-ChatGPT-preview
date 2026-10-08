import 'dart:io';

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
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/tts_service.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/chat_providers.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/providers/tts_providers.dart';
import 'package:native_tavern/presentation/screens/chat/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chatgpt_plan_fixture.dart';
import 'support/fake_system_tts_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory dataDirectory;
  late ProviderContainer container;
  late String chatId;
  String? stoppedOwnerId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    dataDirectory = await Directory.systemTemp.createTemp(
      'chat-screen-lifecycle-',
    );
    final characterRepository = CharacterRepository(
      database,
      dataDirectory.path,
    );
    final chatRepository = ChatRepository(database);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        dataPathProvider.overrideWithValue(dataDirectory.path),
        characterRepositoryProvider.overrideWithValue(characterRepository),
        chatRepositoryProvider.overrideWithValue(chatRepository),
        sharedPreferencesProvider.overrideWithValue(preferences),
        llmServiceProvider.overrideWithValue(LLMService()),
        chatGptPlanPlatformProvider
            .overrideWithValue(ChatGptPlanFixture().platform),
        ttsServiceProvider
            .overrideWithValue(TTSService(systemTts: FakeSystemTTSBackend())),
        ttsStopProvider.overrideWithValue(({String? ownerId}) async {
          stoppedOwnerId = ownerId;
        }),
      ],
    );

    final now = DateTime.utc(2026, 8, 8);
    await characterRepository.createCharacter(
      models.Character(
        id: 'lifecycle-character',
        name: 'Lifecycle Tester',
        description: 'Exercises chat navigation disposal.',
        createdAt: now,
        modifiedAt: now,
      ),
    );
    chatId = (await container
        .read(activeChatProvider.notifier)
        .createChat('lifecycle-character'))!;
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    await dataDirectory.delete(recursive: true);
  });

  testWidgets('connected ChatGPT plan is not blocked by the API-key banner',
      (tester) async {
    await tester.runAsync(() =>
        container.read(llmConfigProvider.notifier).applyConfig(const LLMConfig(
              provider: LLMProvider.chatgptPlan,
              model: 'fixture-model',
              apiKey: '',
              apiUrl: 'https://api.openai.com/v1',
              chatgptProfileId: 'oaiapp_fixture',
            )));
    await tester.runAsync(() => container.read(chatGptAccountsProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(
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
        home: ChatScreen(chatId: chatId),
      ),
    ));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(ChatScreen)));
    expect(find.text('ChatGPT setup required'), findsNothing);
    expect(find.text(l10n.apiNotConfigured), findsNothing,
        reason:
            'The ChatGPT provider authenticates with protected OAuth, not an API key.');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('leaving chat stops TTS without using a disposed ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(chatId: chatId),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(stoppedOwnerId, chatId);
  });
}
