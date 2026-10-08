import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/data/database/database.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('API keys survive rapid settings writes and provider switching',
      () async {
    const initial = LLMConfig(
      provider: LLMProvider.openai,
      model: 'gpt-test',
      apiKey: 'old-key',
      apiUrl: 'https://example.com/v1',
    );
    SharedPreferences.setMockInitialValues({
      'llm_config': jsonEncode(initial.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final notifier = LLMConfigNotifier(prefs, database);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    notifier.updateApiKey('new-key');
    for (var index = 0; index < 20; index++) {
      notifier.updateTemperature(0.5 + index / 100);
    }
    await notifier.flushPersistence();

    expect(notifier.state.apiKey, 'new-key');
    final activeRow = await (database.select(database.globalStates)
          ..where((row) => row.key.equals('llm_config')))
        .getSingle();
    expect(
      (jsonDecode(activeRow.value) as Map<String, dynamic>)['apiKey'],
      'new-key',
    );
    final providerRow = await (database.select(database.globalStates)
          ..where((row) => row.key.equals('llm_provider_config_openai')))
        .getSingle();
    expect(
      (jsonDecode(providerRow.value) as Map<String, dynamic>)['apiKey'],
      'new-key',
    );

    await notifier.updateProvider(LLMProvider.openRouter);
    notifier.updateApiKey('router-key');
    await notifier.flushPersistence();
    await notifier.updateProvider(LLMProvider.openai);
    expect(notifier.state.apiKey, 'new-key');
    await notifier.updateProvider(LLMProvider.openRouter);
    expect(notifier.state.apiKey, 'router-key');
  });

  test('parameter send toggles persist and reload', () async {
    const initial = LLMConfig(
      provider: LLMProvider.openai,
      model: 'gpt-test',
      apiKey: 'key',
      apiUrl: 'https://example.com/v1',
    );
    SharedPreferences.setMockInitialValues({
      'llm_config': jsonEncode(initial.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final notifier = LLMConfigNotifier(prefs, database);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    notifier.updateParameterEnabled(SamplerParameters.presencePenalty, false);
    await notifier.flushPersistence();

    final row = await (database.select(database.globalStates)
          ..where((r) => r.key.equals('llm_config')))
        .getSingle();
    final decoded = jsonDecode(row.value) as Map<String, dynamic>;
    expect(decoded['disabledParameters'], contains('presence_penalty'));

    final restored = LLMConfig.fromJson(decoded);
    expect(restored.sendsParameter(SamplerParameters.presencePenalty), isFalse);
    expect(restored.sendsParameter(SamplerParameters.temperature), isTrue);

    notifier.updateParameterEnabled(SamplerParameters.presencePenalty, true);
    await notifier.flushPersistence();
    expect(
      notifier.state.sendsParameter(SamplerParameters.presencePenalty),
      isTrue,
    );
  });

  test(
      'plan profile survives provider switching without sharing API keys or OAuth secrets',
      () async {
    const initial = LLMConfig(
        provider: LLMProvider.openai,
        model: 'fixture',
        apiKey: 'fixture-api-key',
        apiUrl: 'https://api.openai.com/v1');
    SharedPreferences.setMockInitialValues(
        {'llm_config': jsonEncode(initial.toJson())});
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final notifier = LLMConfigNotifier(prefs, database);
    addTearDown(notifier.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await notifier.updateProvider(LLMProvider.chatgptPlan);
    notifier.updateChatGptProfile('oaiapp_fixture');
    notifier.updateApiKey('must-not-save');
    notifier.updateModel('fixture-model');
    await notifier.flushPersistence();
    expect(notifier.state.apiKey, '');
    final configs = await notifier.getAllProviderConfigs();
    expect(configs['chatgptPlan']!['chatgptProfileId'], 'oaiapp_fixture');
    expect(configs['chatgptPlan']!['apiKey'], '');
    await notifier.updateProvider(LLMProvider.openai);
    expect(notifier.state.apiKey, 'fixture-api-key');
    await notifier.updateProvider(LLMProvider.chatgptPlan);
    expect(notifier.state.chatgptProfileId, 'oaiapp_fixture');
    expect(notifier.state.model, 'fixture-model');
    expect(notifier.state.apiKey, '');
    await notifier.restoreProviderConfigs({
      'chatgptPlan': {
        'apiKey': 'must-not-save',
        'access_token': 'must-not-export',
        'refresh_token': 'must-not-export',
        'model': 'fixture-model'
      }
    });
    await notifier.forceSetProvider(LLMProvider.chatgptPlan);
    final row = await (database.select(database.globalStates)
          ..where((r) => r.key.equals('llm_provider_config_chatgptPlan')))
        .getSingle();
    expect(row.value, isNot(contains('must-not')));
    expect(notifier.state.chatgptProfileId, 'oaiapp_fixture');
    await notifier.applyConfig(const LLMConfig(
        provider: LLMProvider.chatgptPlan,
        apiKey: 'must-not-save',
        apiUrl: 'https://attacker.invalid',
        model: 'fixture',
        chatgptProfileId: 'oaiapp_fixture'));
    expect(notifier.state.apiKey, '');
    expect(notifier.state.apiUrl, 'https://api.openai.com/v1');
  });
  test(
      'incomplete plan snapshots recover only their saved account and model binding',
      () async {
    SharedPreferences.setMockInitialValues({
      'llm_config': jsonEncode(const LLMConfig(
        provider: LLMProvider.chatgptPlan,
        model: 'orphan-model',
        apiKey: '',
        apiUrl: 'https://api.openai.com/v1',
      ).toJson()),
      'llm_provider_config_chatgptPlan': jsonEncode({
        'apiKey': '',
        'apiUrl': 'https://api.openai.com/v1',
        'chatgptProfileId': 'oaiapp_saved',
        'model': 'saved-model',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final settings = LLMConfigNotifier(prefs, database);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await settings.flushPersistence();
    expect(settings.state.chatgptProfileId, 'oaiapp_saved');
    expect(settings.state.model, 'saved-model');
    expect(settings.state.apiKey, isEmpty);
    await settings.applyConfig(const LLMConfig(
      provider: LLMProvider.chatgptPlan,
      model: '',
      apiKey: '',
      apiUrl: 'https://api.openai.com/v1',
      temperature: 0.5,
    ));
    expect(settings.state.chatgptProfileId, 'oaiapp_saved');
    expect(settings.state.model, 'saved-model');
    expect(settings.state.temperature, 0.5);
    settings.dispose();
    await database.close();
  });
}
