import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/core/services/initialization_service.dart';
import 'package:native_tavern/data/database/database.dart' hide Character, Chat;
import 'package:native_tavern/data/models/character.dart';
import 'package:native_tavern/data/models/chat.dart';
import 'package:native_tavern/data/repositories/character_repository.dart';
import 'package:native_tavern/data/repositories/chat_repository.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/screens/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory dataDirectory;
  late ChatRepository chats;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    dataDirectory = Directory.systemTemp.createTempSync('home-chat-list-qol-');
    final characters = CharacterRepository(database, dataDirectory.path);
    chats = ChatRepository(database);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        dataPathProvider.overrideWithValue(dataDirectory.path),
        characterRepositoryProvider.overrideWithValue(characters),
        chatRepositoryProvider.overrideWithValue(chats),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );

    final now = DateTime.now();
    for (final entry in const [('alice', 'Alice'), ('bob', 'Bob')]) {
      await characters.createCharacter(
        Character(
            id: entry.$1, name: entry.$2, createdAt: now, modifiedAt: now),
      );
      await chats.createChat(
        Chat(
          id: 'chat-${entry.$1}',
          characterId: entry.$1,
          title: entry.$2,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await chats.addMessage(
      ChatMessage(
        id: 'm1',
        chatId: 'chat-alice',
        role: MessageRole.user,
        content: '<b>Hello</b>\n\n  *waves*   there',
        timestamp: now,
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    dataDirectory.deleteSync(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester) async {
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
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('previews are one clean line prefixed for the user',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('You: Hello waves there'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('swipe to delete asks first, then removes the chat',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('Alice'), findsOneWidget);

    await tester.drag(find.text('Alice'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete Chat'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    expect(await tester.runAsync(() => chats.getChat('chat-alice')), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelling the confirmation keeps the chat', (tester) async {
    await pumpHome(tester);

    await tester.drag(find.text('Alice'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(
      await tester.runAsync(() => chats.getChat('chat-alice')),
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning off delete confirmations skips the dialog',
      (tester) async {
    container.read(appSettingsProvider.notifier);
    // Let the settings finish loading before flipping the toggle.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    container.read(appSettingsProvider.notifier).updateConfirmBeforeDelete(
          false,
        );
    await pumpHome(tester);

    await tester.drag(find.text('Bob'), const Offset(-600, 0));
    await settle(tester);

    expect(find.text('Delete Chat'), findsNothing);
    expect(find.text('Bob'), findsNothing);
    expect(await tester.runAsync(() => chats.getChat('chat-bob')), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
