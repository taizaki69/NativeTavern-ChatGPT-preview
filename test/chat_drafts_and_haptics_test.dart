import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:native_tavern/presentation/providers/chat_draft_providers.dart';
import 'package:native_tavern/presentation/providers/chat_providers.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/providers/stt_providers.dart';
import 'package:native_tavern/presentation/providers/tts_providers.dart';
import 'package:native_tavern/presentation/screens/chat/chat_screen.dart';
import 'package:native_tavern/presentation/screens/home/home_screen.dart';
import 'package:native_tavern/presentation/widgets/common/haptics.dart';
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
    dataDirectory = await Directory.systemTemp.createTemp('chat-drafts-');
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
    for (var i = 0; i < 4; i++) {
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

  Future<void> pumpChat(WidgetTester tester) async {
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
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }

  EditableText input(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText).last);

  testWidgets('unsent text survives leaving and reopening a chat',
      (tester) async {
    await pumpChat(tester);
    await tester.enterText(find.byType(EditableText).last, 'Half-written idea');
    await tester.pump();
    await leave(tester);

    expect(
      container.read(chatDraftStoreProvider).read(chatId),
      'Half-written idea',
    );

    await pumpChat(tester);
    expect(input(tester).controller.text, 'Half-written idea');

    // Clearing the field removes the saved draft after the debounce.
    await tester.enterText(find.byType(EditableText).last, '');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(container.read(chatDraftStoreProvider).read(chatId), isNull);
    await leave(tester);
  });

  testWidgets('home shows a draft instead of the last message', (tester) async {
    await tester.runAsync(
      () => container
          .read(chatDraftStoreProvider)
          .write(chatId, 'Reply to\nthe letter'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Draft: Reply to the letter'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('haptics follow the settings toggle', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    playHaptic(context, TavernHaptic.selection);
    expect(calls, ['HapticFeedbackType.selectionClick']);

    container.read(appSettingsProvider.notifier).updateHaptics(false);
    playHaptic(context, TavernHaptic.medium);
    expect(calls, hasLength(1));
    await leave(tester);
  });
}
