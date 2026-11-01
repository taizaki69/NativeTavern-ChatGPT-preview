import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/core/services/initialization_service.dart';
import 'package:native_tavern/data/database/database.dart';
import 'package:native_tavern/data/models/character.dart' as models;
import 'package:native_tavern/data/models/chat.dart' as models;
import 'package:native_tavern/data/repositories/character_repository.dart';
import 'package:native_tavern/data/repositories/chat_repository.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/stt_service.dart';
import 'package:native_tavern/domain/services/tts_service.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/chat_providers.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/providers/stt_providers.dart';
import 'package:native_tavern/presentation/providers/tts_providers.dart';
import 'package:native_tavern/presentation/screens/chat/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_stt_backends.dart';
import 'support/fake_system_tts_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory dataDirectory;
  late ProviderContainer container;
  late String chatId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    dataDirectory = await Directory.systemTemp.createTemp('chat-jump-');
    final characterRepository =
        CharacterRepository(database, dataDirectory.path);
    final chatRepository = ChatRepository(database);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        dataPathProvider.overrideWithValue(dataDirectory.path),
        characterRepositoryProvider.overrideWithValue(characterRepository),
        chatRepositoryProvider.overrideWithValue(chatRepository),
        sharedPreferencesProvider.overrideWithValue(preferences),
        llmServiceProvider.overrideWithValue(LLMService()),
        ttsServiceProvider
            .overrideWithValue(TTSService(systemTts: FakeSystemTTSBackend())),
        ttsStopProvider.overrideWithValue(({String? ownerId}) async {}),
        sttServiceProvider.overrideWithValue(STTService(
          systemBackend: FakeSystemSTTBackend(),
          recorder: FakeSTTAudioRecorder(),
          remoteBackend: FakeRemoteSTTBackend(),
          permissionGateway: FakeSTTPermissionGateway(),
        )),
      ],
    );

    final now = DateTime.utc(2026, 10, 1);
    await characterRepository.createCharacter(
      models.Character(
        id: 'jump-character',
        name: 'Jumper',
        createdAt: now,
        modifiedAt: now,
      ),
    );
    chatId = (await container
        .read(activeChatProvider.notifier)
        .createChat('jump-character'))!;
    for (var i = 0; i < 40; i++) {
      await chatRepository.addMessage(
        models.ChatMessage(
          id: 'message-$i',
          chatId: chatId,
          role:
              i.isEven ? models.MessageRole.user : models.MessageRole.assistant,
          content: 'Message number $i with enough text to take some room.',
          timestamp: now.add(Duration(minutes: i)),
        ),
      );
    }
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    await dataDirectory.delete(recursive: true);
  });

  ScrollPosition messagePosition(WidgetTester tester) {
    return tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((state) => state.position)
        .firstWhere(
          (position) =>
              position.axis == Axis.vertical && position.maxScrollExtent > 0,
        );
  }

  double jumpOpacity(WidgetTester tester) {
    return tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(const Key('chat-jump-to-latest')),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
  }

  testWidgets('jump-to-latest appears after scrolling up and returns to bottom',
      (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(chatId: chatId),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(jumpOpacity(tester), 0, reason: 'hidden at the newest message');

    final position = messagePosition(tester);
    position.jumpTo(1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(jumpOpacity(tester), 1);

    await tester.tap(find.byKey(const Key('chat-jump-to-latest')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(messagePosition(tester).pixels, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(jumpOpacity(tester), 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
